# syntax=docker/dockerfile:1
#
# endpoint-enforcement overlay. A MIXIN recipe is an overlay, not a root
# filesystem: it carries no ENTRYPOINT (the base workload's launch command
# stays) and ships no files here — the marker file is written at create by the
# lifecycle `files:` entry in endpoint-enforcement.yaml.
#
# The overlay exists only to carry the constant environment variable the v2 kit
# declared. SANDBOX_ENFORCED=1 is static, so it belongs in the image config as
# an ENV; env is an additive image-config field that merges into the composed
# image at assembly (SPEC-v3 §10), so a mixin's ENV reaches the agent. It sits
# on the final (and only) stage, since a build stage's config is discarded.
#
# The other v2 env var, SANDBOX_ENFORCEMENT_MARKER, is NOT set here: it is
# arg-derived and must resolve at create, so it rides the markerId arg's `env:`
# export instead (see the descriptor).
FROM scratch
ENV SANDBOX_ENFORCED=1
