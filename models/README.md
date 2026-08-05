# models/ — point-in-time snapshot of the app's generated models

These `*Model.ts` files are a **committed, point-in-time snapshot** of the app repo's
`src/generated/models/*Model.ts`. The mandatory zip-patch step in
`.github/workflows/deploy-solution.yml` invokes
`./scripts/author-missing-columns.ps1 -ModelsDir "models"`, which reads the value→label
constant blocks in these files to author the optionset/boolean columns the wedged source
org's exporter silently drops (0x8009050c).

## Why a committed snapshot (D-12, rehearsal-scoped)

The deploy repo is **self-contained** for the rehearsal: the `build-artifact` job does a plain
default checkout of *this* repo and reads `models/` locally — it does **not** check out the app
repo. This keeps the workflow runnable with a single repo + secrets.

- **For the current T8Probe solution** the authoring pass matches **0** columns (no optionsets),
  so the snapshot is not load-bearing yet — but the full snapshot keeps the fix general for later
  solutions (e.g. PlatformHub) whose exports **do** need the dropped columns re-authored.
- **Re-sync on schema change:** whenever the app's Dataverse schema changes (new/changed choice
  or boolean columns), regenerate the app models and re-copy them here:
  `cp ../src/generated/models/*Model.ts ./` (run from `deploy-repo/models/`), then commit.

## Firm-hardening follow-up (deferred, 18.x)

The firm design does **not** commit a snapshot. Instead the `build-artifact` job checks out the
**app repo** (`mflavan13/PowerAppCodeApp-PPTeamManagement`) at the `appBuiltFromSha` carried in
`client_payload` (plus a Contents:read PAT), so the value→label maps are always exactly the ones
the running app was built from. Until then, this snapshot is the source of truth for the zip-patch.
