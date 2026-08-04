#!/usr/bin/env bash
# Spike 007 · T7 — generate deploymentSettings.json by merging the committed per-solution
# SKELETON (static LogicalName + ConnectorId for first-party refs) with the app-supplied
# bindings (the per-env ConnectionId, the ONLY value the app injects — no human GUID paste).
#
# Usage: gen-deployment-settings.sh <skeleton.json> <bindings.json> <out.json>
#   bindings.json = the client_payload.bindings array: [{LogicalName, ConnectionId, ConnectorId}]
#
# Behavior:
#   - First-party refs: ConnectionId injected by LogicalName; ConnectorId kept from skeleton.
#   - Custom-connector refs: ConnectorId is env-specific → taken from the binding (per-target
#     substitution), not the skeleton. LogicalName is the join key.
#   - Fails loudly if any skeleton ref is left with an empty ConnectionId (unbound → silent
#     runtime break otherwise).
set -euo pipefail
SKELETON="${1:?skeleton.json}"; BINDINGS="${2:?bindings.json}"; OUT="${3:?out.json}"

jq -n --slurpfile sk "$SKELETON" --slurpfile bn "$BINDINGS" '
  ($bn[0]) as $bindings
  | ($sk[0]) as $skeleton
  | $skeleton
  | .ConnectionReferences = [
      $skeleton.ConnectionReferences[]
      | . as $ref
      | ($bindings[] | select(.LogicalName == $ref.LogicalName)) as $b
      | {
          LogicalName: $ref.LogicalName,
          ConnectionId: ($b.ConnectionId // $ref.ConnectionId // ""),
          # custom-connector refs carry an env-specific ConnectorId in the binding; prefer it
          ConnectorId: ($b.ConnectorId // $ref.ConnectorId)
        }
    ]
' > "$OUT"

# Fail loud on any unbound reference.
UNBOUND=$(jq -r '.ConnectionReferences[] | select(.ConnectionId == "" or .ConnectionId == null) | .LogicalName' "$OUT")
if [ -n "$UNBOUND" ]; then
  echo "::error::unbound connection references (no ConnectionId): $UNBOUND" >&2
  exit 1
fi
echo "Wrote $OUT"
