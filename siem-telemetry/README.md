# siem-telemetry

A Docker Sandboxes **mixin** that pipes sandbox observability into an external
SIEM HTTP event collector, giving the security platform visibility into what
runs *inside* the sandbox, the basis for dashboards, correlation, and automated
response.

## What it does

- Installs [Fluent Bit](https://fluentbit.io/) into the sandbox (idempotent),
  choosing the method by memory page size so it works on **both amd64 and
  arm64**:
  - **4 KB pages** (all amd64, and 4 KB-page arm64) → the fast prebuilt package,
    then a `--version` check that falls through to a source build if the binary
    doesn't run.
  - **16 KB pages** (the sandbox microVM on Apple Silicon) → a source build of
    v5.1.2 with `-DFLB_JEMALLOC=Off`. The prebuilt package bundles a jemalloc
    compiled for 4 KB pages and aborts on 16 KB pages with `Unsupported system
    page size`; a libc-malloc build runs on both.
- Runs it in the background at startup, tailing process/network/file/agent
  activity logs from `/var/log/sandbox/` and `~/.sandbox/logs/`.
- POSTs events as JSON lines to your SIEM's HTTP event collector over TLS.
- Injects the collector token via the sandbox proxy; the container never holds
  the real credential.

> **Build cost.** The prebuilt path (4 KB-page hosts, incl. amd64 CI) adds only
> a few seconds. The source-build path (16 KB-page arm64) adds ~2–3 min to the
> first `sbx create`. Both are guarded (`command -v fluent-bit || [ -x
> /opt/fluent-bit/bin/fluent-bit ]`) so they do not re-run on container
> restarts.

## Arguments

| Arg | Required | Default | Description |
|---|---|---|---|
| `siemCollectorHost` | yes | - | Collector ingestion FQDN (no scheme). |
| `siemCollectorPath` | no | `/logs/v1/event` | HTTP path events are POSTed to. |
| `siemCollectorAuthId` | no | `""` | Cortex XSIAM HTTP Collector API key ID (numeric, non-secret), sent as the `x-xdr-auth-id` header. Required by XSIAM; leave empty for collectors that authenticate with the `Authorization` header alone. |

## Credential binding

The collector token is supplied with a **custom secret**, bound to the
collector host and exposed to the sandbox as the `SIEM_COLLECTOR_TOKEN`
environment variable:

```bash
sbx secret set-custom \
  --host collector.example.internal \
  --env SIEM_COLLECTOR_TOKEN \
  --value "$SIEM_COLLECTOR_TOKEN"
```

The sandbox only ever sees a **placeholder** in `SIEM_COLLECTOR_TOKEN`. Fluent
Bit sends that placeholder in the `Authorization` header (see
`sandbox-telemetry.conf`), and the sandbox proxy swaps it for the real token on
requests to the collector host, so the container never holds the real value.
The `--host` must match your `siemCollectorHost`.

Scope the secret to one sandbox with `--sandbox <name>`, or omit it to apply
globally. If no custom secret is set, the header expands to empty and events
are sent unauthenticated.

### Cortex XSIAM

XSIAM's HTTP collector authenticates with **two** values: the API key
(`Authorization` header, above) and its numeric key **ID** (`x-xdr-auth-id`
header). The ID is a non-secret identifier, so pass it as a plain arg rather
than a secret:

```bash
sbx run claude \
  --kit ./siem-telemetry/ \
  --arg siem-telemetry.siemCollectorHost=api-<tenant>.xdr.<region>.paloaltonetworks.com \
  --arg siem-telemetry.siemCollectorAuthId=<key-id> .
```

XSIAM rejects requests missing either value, so both are needed for a live
tenant. Non-XSIAM collectors that need only the `Authorization` token can leave
`siemCollectorAuthId` empty.

## Usage

Published OCI artifact:

```bash
sbx run claude \
  --kit docker.io/ajeetraina777/sbx-kits-panw:siem-telemetry \
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

## Network access

The kit's `permissions.network.allow` lists every host either install path or
the forwarder reaches: the collector (`siemCollectorHost`), the prebuilt
package (`raw.githubusercontent.com`, `packages.fluentbit.io`), the source
tarball (`github.com`, `codeload.github.com`), and apt
(`archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com`,
`download.docker.com`).

> **Under organization-managed governance**, a deny-by-default org policy takes
> precedence over a kit's own allow-list; the kit declaring a host is not
> enough, the org must also permit it, or the build fails at the proxy with
> `403 Forbidden`. Ensure the hosts above are allowed in your org policy.

## Composing with endpoint enforcement

The two kits stack: endpoint enforcement governs *where* the agent may run,
SIEM telemetry reports *what* it did:

```bash
sbx run claude \
  --kit ./endpoint-enforcement/ \
  --kit ./siem-telemetry/ \
  --arg siem-telemetry.siemCollectorHost=collector.example.internal .
```
