# Docker Sandboxes security kits

Two [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) mixins
(`kind: mixin`) that integrate sandboxed AI coding agents with an external
security platform along two axes:

- **Where an agent may run** — enforced at the host endpoint.
- **What an agent did** — reported to a SIEM.

Both are `kind: mixin`, `schemaVersion: "2"`, and layer onto any base agent
(e.g. `claude`).

Source and full docs: https://github.com/ajeetraina/sbx-kits-panw

## Image tags

| Tag | Kit | Purpose |
|-----|-----|---------|
| `endpoint-enforcement` | [endpoint-enforcement](https://github.com/ajeetraina/sbx-kits-panw/tree/main/endpoint-enforcement) | Marks sandbox-wrapped agent processes so a host-side endpoint policy can permit them and deny agents spawned outside a sandbox. |
| `siem-telemetry` | [siem-telemetry](https://github.com/ajeetraina/sbx-kits-panw/tree/main/siem-telemetry) | Forwards sandbox observability (process, network, file, agent activity) to a SIEM HTTP event collector via Fluent Bit, with a proxy-injected collector credential. |

## Quick start

Run a base agent with one kit:

    sbx run claude --kit docker.io/ajeetraina777/sbx-kits-panw:endpoint-enforcement .

Stack both — enforcement governs *where* the agent runs, telemetry reports
*what* it did:

    sbx run claude \
      --kit docker.io/ajeetraina777/sbx-kits-panw:endpoint-enforcement \
      --kit docker.io/ajeetraina777/sbx-kits-panw:siem-telemetry \
      --kit-arg siem-telemetry.siemCollectorHost=collector.example.internal .

See each kit's README on GitHub for its arguments, credential bindings, and the
published-OCI / git-reference / local-path invocation forms.
