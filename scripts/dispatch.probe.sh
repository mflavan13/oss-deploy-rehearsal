#!/usr/bin/env bash
# Spike 007 · T4 (runnable NOW, no Power Platform tenant) — fire a repository_dispatch
# and confirm the workflow triggers with the nested bindings intact.
#
# Usage:
#   export GH_PAT=github_pat_...          # fine-grained PAT, single repo, Contents:write
#   ./dispatch.probe.sh <owner> <repo>
#
# Then: gh run list --event repository_dispatch   (or GET /actions/runs?event=repository_dispatch)
# and match run-name  deploy-<correlationId>  → recovers the run handle the 204 didn't return.
set -euo pipefail
OWNER="${1:?owner}"; REPO="${2:?repo}"
CORR="oss-deploy-$(date +%s)-$RANDOM"   # correlationId the 204 response will NOT echo back

curl -sS -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GH_PAT:?set GH_PAT}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${OWNER}/${REPO}/dispatches" \
  -d @- <<JSON
{
  "event_type": "deploy-solution",
  "client_payload": {
    "correlationId": "${CORR}",
    "sourceSolution": "PlatformHub",
    "sourceEnvUrl": "https://dev.crm.dynamics.com",
    "targetEnvUrl": "https://qa.crm.dynamics.com",
    "appBuiltFromSha": "0000000000000000000000000000000000000000",
    "bindings": [
      { "LogicalName": "oss_sharedsql_abc12", "ConnectionId": "0f1e2d3c4b5a69788796a5b4c3d2e1f0", "ConnectorId": "/providers/Microsoft.PowerApps/apis/shared_sql" },
      { "LogicalName": "oss_sharedoffice365_def34", "ConnectionId": "1122334455667788990011223344556677", "ConnectorId": "/providers/Microsoft.PowerApps/apis/shared_office365" }
    ]
  }
}
JSON

echo
echo "Dispatched. Expect HTTP 204 (no body, no run id)."
echo "correlationId = ${CORR}"
echo "Recover the run:  gh run list --repo ${OWNER}/${REPO} --event repository_dispatch"
echo "                  (match run-name  deploy-${CORR})"
