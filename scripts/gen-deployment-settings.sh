#!/usr/bin/env bash
# Spike 007 · T7 — generate deploymentSettings.json.
#
# BINDINGS-DRIVEN design (the running app is the source of truth for which refs exist):
# ConnectionReferences are built from the app-supplied BINDINGS (arg 2). The app resolved
# every reference it actually uses (LogicalName + per-env ConnectionId + ConnectorId) and
# nested them under client_payload.bindings — that is the authoritative list. The committed
# SKELETON (arg 1) NO LONGER carries example ConnectionReferences; its only remaining role is
# EnvironmentVariables — and as of 19-09 (OI-1 option A / D-23) the skeleton DECLARES the
# solution's env-var SchemaNames ONLY; the per-target VALUES come from a committed, MAINTAINED
# config file (arg 4: config/env-vars.<envkey>.json) — NEVER copied from the source env.
# Secret-type / Key Vault env vars carry the @Microsoft.KeyVault(SecretUri=...) REFERENCE
# only — the raw secret stays in Key Vault, resolved by Power Platform in the TARGET env.
# Rationale: a generic skeleton ref list can never match the real solution's hashed
# LogicalNames, so iterating the skeleton silently dropped the app's real binding →
# OI-5 "no ConnectionIds present in DeploymentSettings.json" (the Wave-3 on-ramp defect
# this fixes).
#
# Usage: gen-deployment-settings.sh <skeleton.json> <bindings.json> <out.json> [env-vars.json]
#   bindings.json = the client_payload.bindings array: [{LogicalName, ConnectionId, ConnectorId}]
#   env-vars.json = the per-target env-var config (config/env-vars.<envkey>.json): an array of
#                   {SchemaName, Value} — required whenever the skeleton declares any env var.
#
# Behavior:
#   - ConnectionReferences: one per binding, straight from the app (LogicalName + ConnectionId +
#     ConnectorId) — first-party AND custom-connector refs alike; the app already knows the
#     env-specific ConnectorId.
#   - EnvironmentVariables: skeleton-declared SchemaNames ⊕ per-target values from arg 4,
#     merged by SchemaName (19-09). Skeleton Values (if any) are IGNORED — no blind source
#     copy (D-23). Config entries not declared by the skeleton are ignored with a notice.
#   - Fails loudly if any binding is left with an empty ConnectionId (unbound → silent
#     runtime break otherwise), and if any skeleton-declared env var has no per-target
#     value (missing config file, missing SchemaName, or empty Value — no silent skips).
set -euo pipefail
SKELETON="${1:?skeleton.json}"; BINDINGS="${2:?bindings.json}"; OUT="${3:?out.json}"
ENVVARS="${4:-}"   # optional UNLESS the skeleton declares env vars (then required, fail-loud)

# ── 19-09 fail-loud preflight: declared env vars REQUIRE a per-target config ──
DECLARED=$(jq -r '(.EnvironmentVariables // []) | map(.SchemaName) | join(" ")' "$SKELETON")
if [ -n "$DECLARED" ]; then
  if [ -z "$ENVVARS" ]; then
    echo "::error::skeleton declares environment variables ($DECLARED) but no per-target env-var config was supplied (arg 4: config/env-vars.<envkey>.json)" >&2
    exit 1
  fi
  if [ ! -f "$ENVVARS" ]; then
    echo "::error::per-target env-var config not found: $ENVVARS — the skeleton declares: $DECLARED" >&2
    exit 1
  fi
fi

# Slurp the per-target env-var config (absent/omitted → empty; only legal when nothing declared).
ENVVARS_FILE="$ENVVARS"
if [ -z "$ENVVARS" ] || [ ! -f "$ENVVARS" ]; then ENVVARS_FILE=/dev/null; fi

jq -n --slurpfile sk "$SKELETON" --slurpfile bn "$BINDINGS" --slurpfile ev "$ENVVARS_FILE" '
  ($sk[0] // {}) as $skeleton
  | ($bn[0] // []) as $bindings
  | (($ev[0] // []) | if type == "array" then . else [] end) as $envcfg
  | ($envcfg | map(select(.SchemaName != null) | {key: .SchemaName, value: (.Value // "")}) | from_entries) as $envmap
  | {
      EnvironmentVariables: [
        ($skeleton.EnvironmentVariables // [])[]
        | { SchemaName: .SchemaName, Value: ($envmap[.SchemaName] // "") }
      ],
      ConnectionReferences: [
        $bindings[]
        | { LogicalName: .LogicalName, ConnectionId: (.ConnectionId // ""), ConnectorId: .ConnectorId }
      ]
    }
' > "$OUT"

# Fail loud on any unbound reference.
UNBOUND=$(jq -r '.ConnectionReferences[] | select(.ConnectionId == "" or .ConnectionId == null) | .LogicalName' "$OUT")
if [ -n "$UNBOUND" ]; then
  echo "::error::unbound connection references (no ConnectionId): $UNBOUND" >&2
  exit 1
fi

# Fail loud on any declared env var left without a per-target value (19-09 / D-23 — a
# required var missing from the target config fails the job, never a silent skip).
MISSING_VARS=$(jq -r '[.EnvironmentVariables[] | select(.Value == "" or .Value == null) | .SchemaName] | join(" ")' "$OUT")
if [ -n "$MISSING_VARS" ]; then
  echo "::error::missing per-target environment-variable values (declared in skeleton, absent/empty in ${ENVVARS:-<no env-var config>}): $MISSING_VARS" >&2
  exit 1
fi

# Notice (non-fatal): per-target config entries the skeleton does not declare are ignored —
# the skeleton is the single declaration of what THIS solution needs.
if [ "$ENVVARS_FILE" != "/dev/null" ]; then
  EXTRA=$(jq -r --slurpfile sk "$SKELETON" '
    (($sk[0].EnvironmentVariables // []) | map(.SchemaName)) as $declared
    | [ .[] | select(.SchemaName != null) | .SchemaName | select(. as $s | $declared | index($s) | not) ] | join(" ")
  ' "$ENVVARS")
  if [ -n "$EXTRA" ]; then
    echo "notice: env-var config entries not declared by the skeleton (ignored): $EXTRA"
  fi
fi

echo "Wrote $OUT"
