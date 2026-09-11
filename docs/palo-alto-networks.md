# Palo Alto Networks integration

These kits are written against **vendor-generic** abstractions ("SIEM HTTP event
collector", "host-side endpoint security policy engine") so they compose with any
comparable platform. This page maps those generic terms to the concrete **Palo
Alto Networks** products the repo is designed for, and states what each side owns.

## Mapping at a glance

| Kit | Generic term | Palo Alto Networks product | Configured where |
|---|---|---|---|
| [`siem-telemetry`](../siem-telemetry/) | SIEM HTTP event collector | **Cortex XSIAM** HTTP Log Collector | In-kit (this repo) + XSIAM tenant |
| [`endpoint-enforcement`](../endpoint-enforcement/) | Host-side endpoint security policy engine | **Cortex XDR** agent (host) | Cortex XDR / XSIAM console (out of kit) |

A kit can only act *inside* the container. The host-side enforcement and the SIEM
tenant-side parsing are configured on the Palo Alto Networks products themselves —
the kits supply the in-container signals and the outbound event stream those
products consume.

## `siem-telemetry` → Cortex XSIAM

The kit ships sandbox activity to the [Cortex XSIAM HTTP Log
Collector](https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-3.x-Documentation/Set-up-an-HTTP-log-collector-to-receive-logs).
The defaults are already XSIAM-shaped:

| Kit setting | Value | XSIAM meaning |
|---|---|---|
| `siemCollectorPath` (default) | `/logs/v1/event` | XSIAM HTTP collector ingestion path |
| `siemCollectorHost` | `api-<tenant>.xdr.<region>.paloaltonetworks.com` | Tenant collector FQDN |
| `SIEM_COLLECTOR_TOKEN` (proxy-managed) | → `Authorization` header | XSIAM collector API **key** |
| `siemCollectorAuthId` (arg) | → `x-xdr-auth-id` header | XSIAM collector API **key ID** (numeric, non-secret) |

XSIAM authenticates with **both** the key (`Authorization`) and the numeric key
ID (`x-xdr-auth-id`); the kit sends both (the ID only when set). Event delivery
details — `Content-Type: application/json`, and the ISO 8601 `timestamp` field
XSIAM maps to `_time` — are covered in
[`siem-telemetry/test/README.md`](../siem-telemetry/test/README.md), which also
includes a live-tenant runbook.

### Tenant-side setup (in the XSIAM console)

1. **Settings → Data Sources → Add Custom Collector → HTTP** to create a collector;
   copy its **API key** and **key ID** and note the ingestion FQDN.
2. Store the API key as a sandbox custom secret and pass the key ID as an arg —
   see [`siem-telemetry/README.md`](../siem-telemetry/README.md#credential-binding).
3. Add a **parsing rule** so XSIAM promotes the flattened JSON fields (`event_type`,
   `action`, …) and maps `timestamp` → `_time`. The kit already delivers one JSON
   object per line with top-level fields, so no unwrapping is needed on the XSIAM side.

## `endpoint-enforcement` → Cortex XDR agent

The kit marks every sandbox-wrapped agent process with `SANDBOX_ENFORCED=1`,
`SANDBOX_ENFORCEMENT_MARKER=<markerId>`, and a read-only attestation file at
`~/.sandbox-enforced`. Enforcement itself runs on the **Cortex XDR agent** on the
host, which keys a policy on that marker:

> Permit agent processes **only** when they carry the sandbox marker; deny (or
> alert on) any agent binary that spawns outside a sandbox.

### Host-side setup (in the Cortex XDR / XSIAM console)

1. Deploy the **Cortex XDR agent** to the hosts that run `sbx`.
2. Author a **Restrictions / Behavioral Threat** or custom prevention rule that
   allow-lists processes carrying the marker (environment variable
   `SANDBOX_ENFORCEMENT_MARKER=<markerId>` or the file `~/.sandbox-enforced`) and
   blocks the same agent binaries when the marker is absent.
3. Keep `markerId` in sync between the kit
   ([`endpoint-enforcement/README.md`](../endpoint-enforcement/README.md)) and the
   XDR rule — the marker is the shared contract.

The sandbox's own allow/deny network policy still applies on top of this: endpoint
enforcement governs *where* the agent may run; XDR does not replace the sbx egress
policy.

## What the kits do **not** do

- They do not configure the XSIAM tenant or the Cortex XDR policy — those are
  console-side, out of a kit's reach.
- They do not hold real credentials: the collector token is proxy-managed, and the
  container only ever sees a placeholder.
- End-to-end delivery to a live XSIAM tenant is validated manually (runbook above);
  CI covers delivery against a mock collector.
