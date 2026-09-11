# endpoint-enforcement

A Docker Sandboxes **mixin** that marks agent processes as sandbox-wrapped so a
host-side endpoint security policy engine can enforce a simple rule:

> Permit agent processes **only** when they run inside a sandbox. Deny any agent
> process that spawns outside one.

Docker controls the runtime blast radius (the micro VM); the endpoint policy
engine enforces at the host using the marker this kit supplies.

## What it does

- Sets `SANDBOX_ENFORCED=1` and `SANDBOX_ENFORCEMENT_MARKER=<markerId>` in the
  container environment.
- Writes an on-disk attestation marker at `~/.sandbox-enforced` (read-only,
  written once) that the endpoint agent can verify independently of the process
  environment.
- Appends agent instructions describing the enforcement contract.

Enforcement itself is configured on the host endpoint agent (out of scope for a
kit, which can only act inside the container). This kit provides the identifiable
signal the host policy keys on.

## Palo Alto Networks (Cortex XDR)

The "host-side endpoint security policy engine" this kit targets is the **Cortex
XDR agent**. Deploy it to the hosts that run `sbx`, then author a Restrictions /
Behavioral Threat or custom prevention rule that:

- **allow-lists** agent processes carrying this kit's marker — environment
  variable `SANDBOX_ENFORCEMENT_MARKER=<markerId>` or the file
  `~/.sandbox-enforced`; and
- **denies (or alerts on)** the same agent binaries when the marker is absent —
  i.e. an agent spawned outside a sandbox.

Keep `markerId` in sync between this kit and the XDR rule — the marker is the
shared contract. See [`docs/palo-alto-networks.md`](../docs/palo-alto-networks.md)
for the full product mapping.

## Arguments

| Arg | Default | Description |
|---|---|---|
| `markerId` | `sandbox-wrapped` | Identity string the host endpoint policy allow-lists. |

## Usage

Published OCI artifact:

```bash
sbx run claude --kit docker.io/ajeetraina777/sbx-kits-panw:endpoint-enforcement .
```

Git reference:

```bash
sbx run claude --kit "git+https://github.com/ajeetraina/sbx-kits-panw.git#ref=<40-hex-sha>&dir=endpoint-enforcement" .
```

Local path:

```bash
sbx run claude --kit ./endpoint-enforcement/ .
```

Override the marker:

```bash
sbx run claude --kit ./endpoint-enforcement/ --arg endpoint-enforcement.markerId=my-fleet .
```
