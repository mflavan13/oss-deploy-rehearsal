#!/usr/bin/env bash
# Spike 007 · T7 — generate deploymentSettings.json.
#
# BINDINGS-DRIVEN design (the running app is the source of truth for which refs exist):
# ConnectionReferences are built from the app-supplied BINDINGS (arg 2). The app resolved
# every reference it actually uses (LogicalName + per-env ConnectionId + ConnectorId) and
# nested them under client_payload.bindings — that is the authoritative list. The committed
# SKELETON (arg 1) NO LONGER carries example ConnectionReferences; its only remaining role is
# EnvironmentVariables (the solution's per-env config, populated per-target by wave 19-09).
# Rationale: a generic skeleton ref list can never match the real solution's hashed
# LogicalNames, so iterating the skeleton silently dropped the app's real binding →
# OI-5 "no ConnectionIds present in DeploymentSettings.json" (the Wave-3 on-ramp defect
# this fixes).
#
# Usage: gen-deployment-settings.sh <skeleton.json> <bindings.json> <out.json>
#   bindings.json = the client_payload.bindings array: [{LogicalName, ConnectionId, ConnectorId}]
#
# Behavior:
#   - ConnectionReferences: one per binding, straight from the app (LogicalName + ConnectionId +
#     ConnectorId) — first-party AND custom-connector refs alike; the app already knows the
#     env-specific ConnectorId.
#   - EnvironmentVariables: taken from the skeleton (its remaining role until 19-09).
#   - Fails loudly if any binding is left with an empty ConnectionId (unbound → silent
#     runtime break otherwise).
set -euo pipefail
SKELETON="${1:?skeleton.json}"; BINDINGS="${2:?bindings.json}"; OUT="${3:?out.json}"

jq -n --slurpfile sk "$SKELETON" --slurpfile bn "$BINDINGS" '
  ($sk[0] // {}) as $skeleton
  | ($bn[0] // []) as $bindings
  | {
      EnvironmentVariables: ($skeleton.EnvironmentVariables // []),
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
echo "Wrote $OUT"
