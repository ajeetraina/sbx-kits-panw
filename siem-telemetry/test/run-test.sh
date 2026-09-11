#!/usr/bin/env bash
# End-to-end delivery test for the siem-telemetry forwarder against a MOCK
# collector — no SIEM/XSIAM tenant required. Proves the behaviour issues #3/#4
# call out:
#   - events reach the collector as flattened top-level JSON fields (Parser json),
#   - Content-Type is application/json (Format json_lines, XSIAM-compatible),
#   - an ISO 8601 `timestamp` field is present (XSIAM maps it to _time),
#   - the Authorization and x-xdr-auth-id auth headers are sent.
#
# Runs Fluent Bit against a test conf modelled on the kit's [OUTPUT] (the kit conf
# itself carries `${{ kit.args.* }}` placeholders that only sbx substitutes, so we
# use a localhost conf here). Exit 0 = pass. In CI ($CI set) a missing fluent-bit
# is a failure; locally it is a skip.
set -euo pipefail

PORT="${MOCK_PORT:-8899}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'kill "${FLB_PID:-}" "${MOCK_PID:-}" 2>/dev/null || true; rm -rf "$WORK"' EXIT

FLB="$(command -v fluent-bit || true)"
[ -z "$FLB" ] && [ -x /opt/fluent-bit/bin/fluent-bit ] && FLB=/opt/fluent-bit/bin/fluent-bit
if [ -z "$FLB" ]; then
  if [ -n "${CI:-}" ]; then
    echo "FAIL: fluent-bit not found (required in CI)" >&2
    exit 1
  fi
  echo "SKIP: fluent-bit not installed; install it to run this test locally." >&2
  exit 0
fi

# Sample activity line: one JSON object, as the kit requires log producers to emit.
printf '%s\n' '{"event_type":"process_exec","action":"spawn","pid":4242}' > "$WORK/sample.log"

# Reuse the kit's parser so the test exercises the real flattening behaviour.
cp "$HERE/../files/home/.config/fluent-bit/parsers.conf" "$WORK/parsers.conf"

# Test conf: mirrors the kit's [OUTPUT] but points at the local mock and pins the
# two auth headers (what run-telemetry.sh appends when their values are set).
cat > "$WORK/telemetry-test.conf" <<EOF
[SERVICE]
    Flush         1
    Daemon        Off
    Log_Level     error
    Parsers_File  $WORK/parsers.conf
[INPUT]
    Name          tail
    Path          $WORK/sample.log
    Tag           sandbox.activity
    Read_from_Head On
    Parser        json
[FILTER]
    Name          record_modifier
    Match         *
    Record        source docker-sandbox
[OUTPUT]
    Name             http
    Match            *
    Host             127.0.0.1
    Port             $PORT
    URI              /logs/v1/event
    TLS              Off
    Format           json_lines
    Json_Date_Key    timestamp
    Json_Date_Format iso8601
    Retry_Limit      3
    Header Authorization test-token-placeholder
    Header x-xdr-auth-id 1234567
EOF

CAP="$WORK/captured.json"
python3 "$HERE/mock-collector.py" "$PORT" "$CAP" & MOCK_PID=$!

# Wait for the mock to accept connections.
for _ in $(seq 1 50); do
  if python3 -c "import socket,sys; s=socket.socket(); sys.exit(0 if s.connect_ex(('127.0.0.1',$PORT))==0 else 1)"; then break; fi
  sleep 0.1
done

"$FLB" -c "$WORK/telemetry-test.conf" >"$WORK/flb.log" 2>&1 & FLB_PID=$!

# Wait for the collector to capture a request.
for _ in $(seq 1 100); do
  [ -s "$CAP" ] && break
  sleep 0.1
done

if [ ! -s "$CAP" ]; then
  echo "FAIL: no event reached the mock collector within timeout" >&2
  echo "--- fluent-bit log ---" >&2; cat "$WORK/flb.log" >&2 || true
  exit 1
fi

# Assert on the captured request.
python3 - "$CAP" <<'PY'
import json, sys

cap = json.load(open(sys.argv[1]))
errs = []

if cap["method"] != "POST":
    errs.append(f'method: expected POST, got {cap["method"]}')
if cap["path"] != "/logs/v1/event":
    errs.append(f'path: expected /logs/v1/event, got {cap["path"]}')

h = cap["headers"]
ct = h.get("content-type", "")
if "application/json" not in ct:
    errs.append(f'Content-Type: expected application/json, got {ct!r}')
if h.get("authorization") != "test-token-placeholder":
    errs.append(f'Authorization header missing/wrong: {h.get("authorization")!r}')
if h.get("x-xdr-auth-id") != "1234567":
    errs.append(f'x-xdr-auth-id header missing/wrong: {h.get("x-xdr-auth-id")!r}')

# Body is newline-delimited JSON; first line is our event.
first = cap["body"].strip().splitlines()[0]
event = json.loads(first)
# Flattened: producer keys sit at the top level, not nested under "log".
if event.get("event_type") != "process_exec":
    errs.append(f'event_type not flattened to top level: {event!r}')
if event.get("action") != "spawn":
    errs.append('action field missing from flattened event')
if "log" in event:
    errs.append('event still nested under "log" — Parser json not applied')
# Timestamp present (XSIAM maps this to _time).
if "timestamp" not in event:
    errs.append('timestamp field missing (needed for XSIAM _time mapping)')
# record_modifier enrichment applied.
if event.get("source") != "docker-sandbox":
    errs.append('source enrichment field missing')

if errs:
    print("FAIL:", file=sys.stderr)
    for e in errs:
        print("  -", e, file=sys.stderr)
    sys.exit(1)
print("PASS: event delivered with flattened JSON, application/json, timestamp, and both auth headers")
PY
