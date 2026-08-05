# deploy-repo — app-driven GitHub Actions deploy engine (promotion staging tree)

**Promoted:** 2026-08-03 · Phase 18 (gate-rehearsals-go-no-go), plan 18-02, decision **D-15**
(promote-and-prove, keep the repo).

This tree is the **near-final** set of files Phase 19 ships as the GitHub Actions deploy
mover. It was **promoted (copied + SHA-pinned + parameterized), not rewritten**, from
`.planning/spikes/007-alm-github-actions-deploy-from-app/feasibility-test/`. In plan **18-03**
the owner pushes this tree to a **throwaway GitHub repo** to run the no-tenant spine (T4
dispatch+correlation, T11 approval gate). Per D-15 that throwaway repo then **graduates into
the project's real deploy repo** — the workflow + Environment config carry forward into Phase
19 with no re-authoring.

## Tree

```
deploy-repo/
├── .github/workflows/deploy-solution.yml   # promoted + SHA-pinned + zip-patch repointed
├── scripts/
│   ├── dispatch.probe.sh                    # T4 correlationId probe (verbatim copy)
│   ├── gen-deployment-settings.sh           # T7 settings-gen (verbatim copy)
│   └── author-missing-columns.ps1           # Phase 18 T9/D-14 parameterized port script (copy)
├── models/                                  # committed snapshot of app src/generated/models/*Model.ts (D-12)
│   ├── *Model.ts                            #   value→label maps the zip-patch reads (self-contained)
│   └── README.md                            #   snapshot rationale + re-sync + firm follow-up
├── deploymentSettings.skeleton.json         # T7 per-solution skeleton (verbatim copy)
└── README.md                                # this promotion log
```

## Self-contained workflow (D-12, Wave-3 on-ramp fix)

The `build-artifact` job is **self-contained**: it does a plain default checkout of **this** repo
(no `ref:`) and reads everything it needs locally — `./scripts/*`, `./deploymentSettings.skeleton.json`,
and the committed `models/` snapshot that the zip-patch's `-ModelsDir "models"` reads. This fixes a
19-02 promotion-era gap surfaced by the 19-05 e2e: the original single checkout used
`ref: appBuiltFromSha` (an **app-repo** SHA) with no `repository:`, so it failed to resolve inside the
deploy repo and would have clobbered the repo's own scripts. `appBuiltFromSha` is retained in
`client_payload` as **informational** (commit-drift context), not used for checkout.

**Option A (deferred firm-hardening upgrade, 18.x):** instead of a committed snapshot, the
`build-artifact` job checks out the **app repo** (`mflavan13/PowerAppCodeApp-PPTeamManagement`) at
`appBuiltFromSha` — with a `Contents:read` PAT — so the value→label maps are always exactly the ones
the running app was built from (no snapshot to re-sync). See `models/README.md`.

## What was promoted, and what (if anything) was authored

| File | Source (feasibility-test/ unless noted) | Authoring on promotion |
|------|------|------|
| `.github/workflows/deploy-solution.yml` | `deploy-solution.yml` | **SHA-pinned every `uses:`** (table below); **repointed** the zip-patch step to `./scripts/author-missing-columns.ps1` and the settings step to `./scripts/gen-deployment-settings.sh` + `./deploymentSettings.skeleton.json`; header note updated. `secrets` refs, `run-asynchronously` input, job graph, and T4/T8/T11 markers left intact. |
| `scripts/dispatch.probe.sh` | `dispatch.probe.sh` | **Verbatim copy** (byte-identical). Only real `<owner> <repo>` args differ at run time. |
| `scripts/gen-deployment-settings.sh` | `gen-deployment-settings.sh` | **Verbatim copy** (byte-identical). |
| `deploymentSettings.skeleton.json` | `deploymentSettings.skeleton.json` | **Verbatim copy** (byte-identical). |
| `scripts/author-missing-columns.ps1` | `scripts/port/author-missing-columns.ps1` (Phase 18 T9/D-14) | **Verbatim copy** of the parameterized, byte-identical + idempotent port script. The workflow's mandatory zip-patch step invokes it `-SolutionZip … -ModelsDir … -OutZip …`. |

## SHA-pin table (T-18-05 supply-chain mitigation)

Every `uses:` in the workflow is pinned to a **40-hex commit SHA**; the trailing `# <tag>`
comment records the moving tag each SHA resolved to. Resolved **2026-08-03** with:
`git ls-remote --tags https://github.com/<repo>.git <tag>` (all four are lightweight tags, so
the advertised ref SHA is the commit SHA). Re-run that command to audit for drift.

| Action (`uses:`) | Tag | Pinned commit SHA |
|------------------|-----|-------------------|
| `actions/checkout` | v4 | `11d5960a326750d5838078e36cf38b85af677262` |
| `actions/upload-artifact` | v4 | `ea165f8d65b6e75b540449e92b4886f43607fa02` |
| `actions/download-artifact` | v4 | `d3f86a106a0bac45b974a628896c90dbdf5c8093` |
| `microsoft/powerplatform-actions/*` (actions-install, export-solution, import-solution, check-solution) | v1 | `0e44beb5424af932af47250a2568eba4c259e3d8` |

> The four `powerplatform-actions` sub-actions are paths within one repo
> (`microsoft/powerplatform-actions`) at one `v1` tag, so they share a single commit SHA.
> The commented deferred `check-solution` hook is pinned to the same SHA so no bare `@v` tag
> survives anywhere in the file.

## Secrets (T-18-06 — nothing sensitive is committed)

No secret or PAT literal is committed anywhere under `deploy-repo/`. The workflow reads
`${{ secrets.PP_APP_ID }}` / `${{ secrets.PP_CLIENT_SECRET }}` / `${{ secrets.PP_TENANT_ID }}`
as **GitHub Actions secret references only** — real values are injected as repo/Environment
secrets in 18-03 / Phase 19. `scripts/dispatch.probe.sh` reads a fine-grained PAT from the
`GH_PAT` env var at run time; its header shows the usage placeholder `github_pat_...` (an
ellipsis, **not** a token body).

## Run order on the throwaway repo (18-03, no tenant)

```bash
# T4 — trigger + correlation (put deploy-solution.yml in .github/workflows/ on the repo):
export GH_PAT=github_pat_xxx        # fine-grained, single repo, Contents:write
./scripts/dispatch.probe.sh <owner> <repo>
gh run list --repo <owner>/<repo> --event repository_dispatch   # match run-name deploy-<correlationId>

# T11 — configure a GitHub Environment with required reviewers + prevent self-review;
#        confirm the import-to-target job pauses, and that self-approval is blocked.
```

Notes carried from the feasibility harness: import input is **`run-asynchronously`** (not
`async`); `runs-on: ubuntu-latest` (Linux) for forward-slash zip entries; checkout the **exact
commit the app was built from** (the `*Model.ts` value→label maps drive column authoring);
trigger auth is a **fine-grained PAT** (no GitHub App RS256 signing in a connector policy).

## Out of scope here (Phase 19)

No custom connector, run-status poller, or app-side mover wiring is added in this promotion —
those are Phase 19 build concerns. The deferred solution-checker / unpack+PR-diff /
connector-DLP / version-lint hooks remain pre-slotted (commented) in the workflow.
