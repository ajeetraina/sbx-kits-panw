# siem-telemetry

A Docker Sandboxes **mixin** that pipes sandbox observability into an external
SIEM HTTP event collector, giving the security platform visibility into what
runs *inside* the sandbox — the basis for dashboards, correlation, and automated
response.

## What it does

- Installs [Fluent Bit](https://fluentbit.io/) into the sandbox (idempotent).
- Runs it in the background at startup, tailing process/network/file/agent
  activity logs from `/var/log/sandbox/` and `~/.sandbox/logs/`.
- POSTs events as JSON lines to your SIEM's HTTP event collector over TLS.
- Injects the collector token via the sandbox proxy — the container never holds
  the real credential.

## Arguments

| Arg | Required | Default | Description |
|---|---|---|---|
| `siemCollectorHost` | yes | — | Collector ingestion FQDN (no scheme). |
| `siemCollectorPath` | no | `/logs/v1/event` | HTTP path events are POSTed to. |

## Credential binding

The kit declares a `siem` credential injected as the `Authorization` header on
requests to `siemCollectorHost`. Bind your token in
`~/.config/sbx/credentials.yaml`:

```yaml
credentials:
  - service: siem
    apiKey: op://vault/siem-collector/token   # or an env/literal binding
```

## Usage

Published OCI artifact:

```bash
sbx run claude \
  --kit docker.io/sbx/siem-telemetry-kit:latest \
  --arg siem-telemetry.siemCollectorHost=collector.example.internal .
```

Git reference:

```bash
sbx run claude \
  --kit "git+https://github.com/ajeetraina/sbx-kits-panw.git#ref=<40-hex-sha>&dir=siem-telemetry" \
  --arg siem-telemetry.siemCollectorHost=collector.example.internal .
```

Local path:

```bash
sbx run claude \
  --kit ./siem-telemetry/ \
  --arg siem-telemetry.siemCollectorHost=collector.example.internal .
```

## Composing with endpoint enforcement

The two kits stack — endpoint enforcement governs *where* the agent may run,
SIEM telemetry reports *what* it did:

```bash
sbx run claude \
  --kit ./endpoint-enforcement/ \
  --kit ./siem-telemetry/ \
  --arg siem-telemetry.siemCollectorHost=collector.example.internal .
```
