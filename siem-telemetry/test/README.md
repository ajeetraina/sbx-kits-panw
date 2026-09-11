# siem-telemetry tests

## Automated: mock-collector delivery test

`run-test.sh` runs the Fluent Bit forwarder against a **mock** HTTP collector on
localhost — no SIEM/XSIAM tenant required — and asserts the delivery contract:

- events arrive as **flattened top-level JSON fields** (the `Parser json` on the
  tail input, not nested under `log`);
- `Content-Type: application/json` (XSIAM's requirement). `json_lines` defaults to
  `application/x-ndjson`, so the conf overrides it with an explicit header plus
  `allow_duplicated_headers off`; the test asserts exactly one Content-Type and
  that it is `application/json`;
- an ISO 8601 **`timestamp`** field is present (XSIAM's parsing rule maps this to
  `_time`; unrecognised times fall back to ingestion time);
- both the **`Authorization`** and **`x-xdr-auth-id`** auth headers are sent.

```bash
bash siem-telemetry/test/run-test.sh
```

Requires `fluent-bit` (and `python3`). If Fluent Bit is not installed the script
**skips** locally; in CI (`$CI` set) a missing binary is a **failure**. It is
wired into `.github/workflows/test-siem-telemetry.yaml`, which installs Fluent Bit
and runs it on every change under `siem-telemetry/`.

The test uses a localhost conf modelled on the kit's `[OUTPUT]` because the kit's
own `sandbox-telemetry.conf` carries `${{ kit.args.* }}` placeholders that only
`sbx` substitutes at decode time. Spec/arg validation is covered separately by
`sbx kit validate`.

## Manual: live Cortex XSIAM tenant runbook

The mock test can't exercise a real tenant. To validate end-to-end against Cortex
XSIAM:

1. **Create an HTTP collector** in XSIAM (**Settings → Data Sources → Add Custom
   Collector → HTTP**). Copy its **API key**, **key ID**, and ingestion FQDN.
2. **Bind the credentials** (see [`../README.md`](../README.md#credential-binding)):
   ```bash
   sbx secret set-custom \
     --host api-<tenant>.xdr.<region>.paloaltonetworks.com \
     --env SIEM_COLLECTOR_TOKEN \
     --value "<api-key>"
   ```
3. **Run an agent with the kit**, passing the host and key ID:
   ```bash
   sbx run claude \
     --kit ./siem-telemetry/ \
     --arg siem-telemetry.siemCollectorHost=api-<tenant>.xdr.<region>.paloaltonetworks.com \
     --arg siem-telemetry.siemCollectorAuthId=<key-id> .
   ```
4. **Emit a test event** from inside the sandbox:
   ```bash
   echo '{"event_type":"test","action":"manual-check","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)"'"}' \
     >> ~/.sandbox/logs/test.log
   ```
5. **Confirm in XSIAM** the event lands in your dataset within a minute or two,
   with `event_type`/`action` as queryable fields and `_time` set from
   `timestamp` (add a parsing rule if the fields need mapping).

If nothing arrives: check the collector FQDN is in the org egress allow-list
(see [`../README.md`](../README.md#network-access)), and that both the key and key
ID are correct — XSIAM rejects requests missing either.
