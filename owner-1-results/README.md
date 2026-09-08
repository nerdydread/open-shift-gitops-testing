# TT-17018 QA — Owner 1 (kind & render) results

**Tester:** automated run driven by Claude Code on Mohammed's laptop
**Date:** 2026-08-26
**Tree under test:** `TykTechnologies/tyk-charts` `main` @ **`39957f3660212154296b6ffc9ab733f822e6809d`**
(HEAD of `main` at clone time; the ticket's day-0 SHA was not available to this run — see D-08)
**Chart version in tree:** `5.3.0` for all four umbrellas (§8 Q4 — see D-09)
**Clusters:** kind `v1.26.13` and `v1.30.0` (created serially, one at a time), OrbStack Docker, Apple M4 Pro (arm64), 12 CPU / 13.7 GiB to Docker
**Tooling:** helm `v3.18.6` (packet says 3.18.4 — minor drift, recorded), helm-unittest `v0.7.2`, kind `v0.30.0`, kubectl `v1.33.9`, crane `0.22.0`, yq `v4.53.6`, jq `1.8.1`
**Dependencies:** `helm dependency update` run for all four umbrellas; Redis + PostgreSQL from Bitnami OCI charts per `00-shared-setup.md` §5
**Licences:** internal dashboard licence and MDCB licence (both expire 2026-09-19) supplied mid-run, so **no leg stayed blocked** — the `tyk-control-plane` rows below were completed in a second pass
**Evidence:** `~/playground/tt17018-owner1/evidence/` (per-step logs, renders, dry-run output, full 1.30 transcript)

---

## Verdict summary

| §6 row | Item | Verdict |
|---|---|---|
| 1 | TC-01 on 1.26 + 1.30, ± `--reuse-values` | **FAIL on the `--reuse-values` leg for `tyk-oss`** (D-01, P0 candidate). Plain-upgrade leg PASS on both k8s versions for **all four umbrellas** — `tyk-control-plane` and MDCB-connected `tyk-data-plane` included, once the MDCB licence arrived. `--reuse-values` on the dashboard/MDCB-managed umbrellas carries the same UID split but keeps working (latent) |
| 2 | TC-02 documented + pinned-old-tag decision | **PASS** — failure reproduced verbatim and is documented in-repo; decision (§8 Q1) still owed by the team |
| 4 | Three `ci/no-securitycontext-values.yaml` authored; gap #9 resolved | **PASS (files) + gap #9 CONFIRMED** (D-02, low severity — docs name the working key, umbrella `values.yaml` does not) |
| 6 | TC-06 incl. the `useSecretName` + literal `connectionString` upgrade regression | **PASS** (render + live install + upgrade), plus the new secret path verified live |
| 9 | TC-09 green with the anti-vacuity revert check | **PASS with caveats** — 216/216 green, revert goes red; a 23-site mutation sweep found 1 real untested path (D-03) |
| 10 | TC-10 zero field leaks under server-side dry-run | **PASS** — 8/8 components clean on 1.26 and 1.30; strict decoding proven live |
| 11 | TC-11 green on 1.26 and 1.30 | **PASS**, with Step 3 only reachable via a retagged image (D-04) |
| 13 | Upgrade release note | Draft addition supplied below — the existing in-repo note is good but **silent on `--reuse-values`** (D-01) |
| 14 | OpenShift docs complete | **Partially** — opt-out documented; image-tag *bands* and the Redis/PostgreSQL-on-OpenShift caveat are missing (D-05, D-06) |

**Escalation:** D-01 is the one finding that should be treated as a same-day P0 decision (§8 Q3).
Everything else is either documentation, test-coverage or plan-accuracy work.

---

## Defects and gaps found

### D-01 · P0 candidate · `helm upgrade --reuse-values` silently breaks the gateway's file writes

**Umbrellas:** reproduced end-to-end on `tyk-oss`; the same UID mismatch is present on `tyk-stack` (latent there).
**k8s:** reproduced on 1.26.13 and 1.30.0.

Sequence (verbatim commands in `evidence/tc01-oss-126-*`, `evidence/k130-full-run.log`):

```bash
helm install tyk-oss tyk-helm/tyk-oss --version 5.3.0 -n tyk-ru --create-namespace --wait \
  --set global.redis.addrs={redis-master.tyk.svc:6379}
helm upgrade tyk-oss ./tyk-oss -n tyk-ru --wait --timeout 10m --reuse-values
```

Result — pods **Ready**, rollout **successful**, `helm` reports `STATUS: deployed`, and then:

```
$ curl .../tyk/apis -d '{...}'
HTTP 500
{"status":"error","message":"file object creation failed, write error"}

gateway log:
level=error msg="Failed to create file! - open /mnt/tyk-gateway/apps/ru2.json: permission denied"
```

Rendered pod spec after the upgrade:

```
CTR_SC  = {... "runAsNonRoot":true, "runAsUser":1000 ...}   <- stale, carried by --reuse-values
INIT_SC = {... "runAsNonRoot":true, "runAsUser":65532 ...}  <- new chart default
IMAGE   = docker.tyk.io/tyk-gateway/tyk-gateway:v5.9.1      <- stale
```

**Mechanism.** Released 5.3.0 renders the `setup-directories` init container from
`gateway.containerSecurityContext` (there is no init-specific key in that chart — verified in the
released tarball). `main` gives the init container its own block defaulting to `runAsUser: 65532`.
`--reuse-values` carries the old `containerSecurityContext.runAsUser: 1000` forward but cannot carry a
value for a key that did not exist, so the **init container comes up as 65532 while the main container
stays 1000**. The init container creates `apps/`, `middleware/`, `policies/` in the `tyk-scratch`
emptyDir as 65532; the gateway then cannot write into them. This is exactly the UID-mismatch class
fixed in `e92f013`, reachable again through a documented upgrade flag.

**Why it is worse than a crash:** nothing fails admission, the readiness probe (`/hello`) passes, no
warning events are emitted. A customer sees a healthy rollout and 500s only when something writes.

**Workaround, verified:** `helm upgrade ... --reset-then-reuse-values` recovers on the spot
(container `runAsUser` dropped, image moves to v5.13.1, API create returns 200 and proxies 200).
Explicitly re-aligning `gateway.containerSecurityContext.runAsUser` would also work.

**Notes on scope.** On `tyk-stack` the same stale-1000 / new-65532 split is present after
`--reuse-values` (`evidence/tc01-stack-126-settled.txt`) but stock dashboard-managed traffic does not
write to that emptyDir, so no error surfaced in a short run. Anything that does write there (plugin
bundles, for instance) would hit the same wall; that specific path was **not** tested.

**Blocks 5.4.0: recommend yes for a decision** — either a `NOTES.txt` / release-note warning naming
`--reuse-values`, or template-level defence (e.g. deriving the init UID from the main container's when
one is set). §6 row 1 names both upgrade paths, so row 1 cannot be signed off as-is.

### D-02 · low · gap #9 confirmed: the umbrellas expose a dead operator key

```bash
helm template t ./tyk-control-plane --set global.components.operator=true \
  --set tyk-operator.podSecurityContext.enabled=false | yq '...operator...spec.template.spec.securityContext'
# -> runAsNonRoot: true      (block NOT removed)

helm template t ./tyk-control-plane --set global.components.operator=true \
  --set tyk-operator.managerPodSecurityContext.enabled=false | yq '...'
# -> null                    (block removed)
```

`components/tyk-operator/templates/all.yaml` reads `managerPodSecurityContext` (pod) and
`securityContext` (container). All four umbrella `values.yaml` files expose only
`tyk-operator.podSecurityContext`, annotated `NOTE: unused/dead key — no template reads it`.

**Severity is lower than the packet assumed:** `tyk-stack/README.md` documents
`tyk-operator.managerPodSecurityContext` correctly, and Helm passes the key through to the subchart, so
Owner 2 **can** opt the operator out — via `--set tyk-operator.managerPodSecurityContext.enabled=false`
or a values file. Also, the surviving block is only `runAsNonRoot: true`, which an OpenShift SCC
satisfies by injecting a UID (operator image USER is `65532:65532`). **Blocks 5.4.0: no.**
Fix: add `managerPodSecurityContext` to the umbrella values and delete or annotate the dead key (§7.6).

### D-03 · medium (test quality) · the init-container fallback's `enabled` strip is untested

TC-09 Step 3 was run as specified (revert the null-`annotations` fix → suite goes red, 1 test naming
`metadata.annotations expected to NOT exists`) **and** extended into a full mutation sweep: each of the
23 render sites that strip the synthetic `enabled` flag was mutated back to the original leaking form
(`toYaml (omit $x "enabled")` → `toYaml $x`), one at a time, subcharts re-vendored, all 216 tests re-run.
Full table: `evidence/tc09-mutation-sweep.txt`.

**21 of 23 sites are caught. Two are not:**

| Site | Assessment |
|---|---|
| `components/tyk-gateway/templates/deployment-gw-repset.yaml:118` — the init container's **fallback** branch (`else if $mainOn`) | **Real gap.** Verified non-equivalent: with the mutation and `initContainers.setupDirectories.securityContext.enabled=false`, the init container renders `enabled: true` inside `securityContext` — the exact invalid field the API server rejects — and every test stays green. The suite exercises the fallback but only asserts `notExists` on `runAsUser`; the `enabled`-strip assertion only covers the primary branch. |
| `components/tyk-operator/templates/all.yaml:378` — operator container-level block | **Equivalent mutant, not a gap in behaviour** — but it shows the existing "renders fields without leaking enabled" case is *vacuous* for the operator: it sets fields without `enabled`, and the operator default is `{}`, so no test ever renders that block with `enabled: true` present. |

Fix is two test cases, not chart code. **Blocks 5.4.0: no.**

### D-04 · low (pre-existing) · the legacy dashboard init container can never render for a published tag

`components/tyk-dashboard/templates/deployment-dashboard.yaml:1` gates the `init-analytics-conf` init
container (and its `analytics-conf` volume) on
`$isSemVer && semverCompare "<=5.0.2" .Values.dashboard.image.tag`, where `$isSemVer` is a strict
semver regex that **rejects a `v` prefix**. Published dashboard tags are `v`-prefixed only:

```
tykio/tyk-dashboard:5.0.2   MISSING
tykio/tyk-dashboard:v5.0.2  EXISTS
```

So with any real tag the legacy branch is dead. Identical regex exists in released 5.3.0 → **pre-existing,
not introduced by TT-17018. Blocks 5.4.0: no**, but it makes TC-11 Step 3 untestable as written; I tested
it by retagging `v5.0.2` locally as `5.0.2` and loading it into kind (see TC-11 Step 3 below).

### D-05 · docs (§6 row 14) · image-tag *bands* are not documented

`tyk-stack/README.md` documents the failure, the per-chart default-tag table and how to check an image's
USER with `crane`. It does **not** state that the gateway's USER is non-monotonic — that `v5.8.13–v5.8.15`
and `v5.13+` are safe while **`v5.9.0`–`v5.12.0` are `USER 0`**. Re-verified this run:

```
docker.tyk.io/tyk-gateway/tyk-gateway:v5.9.1   USER=0
docker.tyk.io/tyk-gateway/tyk-gateway:v5.12.0  USER=0
docker.tyk.io/tyk-gateway/tyk-gateway:v5.13.1  USER=65532
tykio/tyk-dashboard:v5.0.2 / v5.4.0            USER=EMPTY (=root)
tykio/tyk-dashboard:v5.9.1 / v5.12.0 / v5.13.1 USER=65532
```

A customer re-pinning "something newer than 5.8" lands in the root band. One table row fixes it.

### D-06 · docs (§7.7) · nothing documents Redis/PostgreSQL on OpenShift

No file in the repo mentions the Bitnami `runAsUser/fsGroup: 1001` problem under `restricted-v2`. What
the repo *does* say (`components/tyk-dashboard/README.md:95-121`) points at
`helm repo add bitnami https://charts.bitnami.com/bitnami`, and the current Bitnami catalogue serves
**rolling `:latest` image tags** — every install in this run printed
`WARNING: Rolling tag detected (bitnami/redis:latest)`. Both belong in the same doc fix, and both are
inputs to §8 Q2.

### D-07 · plan accuracy · four commands in the owner packet do not do what they claim

Found by running them verbatim. All four silently under-report rather than failing loudly.

1. **TC-09 Step 1** — `helm unittest $CHARTS` where `CHARTS` holds newline-separated paths works in bash
   but **fails in zsh** (no word splitting): `Error: stat ./components/tyk-bootstrap\n./components/...: no such file or directory`, reported as `1 failed, 1 errored`. Quote/split explicitly.
2. **TC-09 Step 2** — `find . -maxdepth 2 -name Chart.yaml` finds only the **4 umbrellas**; the 7
   component charts are at depth 3. As written it lints 4 of 11 charts and still looks green. With
   `-maxdepth 3` (excluding `charts/`): **11 linted, 0 failed**, one `[INFO] icon is recommended` on the operator.
3. **TC-02 Step 1** — the packet's replacement image loop uses `awk '{print $2}'` on lines matched with
   `^[[:space:]]+image:`, so every image rendered as a **list item** (`- image: ...`) is dropped:
   the dashboard and the dev portal never appear. Same silent-omission class the packet criticises in
   the master plan. Fixed extraction is in `evidence/tc02-image-users.txt`.
4. **TC-01 Step 5 / TC-11** — `kubectl get pod -l app.kubernetes.io/name=tyk-gateway` matches **nothing**;
   the chart labels pods `app=gateway-<release>-tyk-gateway` / `release=<release>`. The packet's jsonpath
   then errors with `array index out of bounds` (or, worse, silently prints nothing).

Also: the packet's PostgreSQL command installs release `postgres` (service `postgres-postgresql`) while
the charts default `global.postgres.host` to **`tyk-postgres-postgresql.tyk.svc`** — install it as
`tyk-postgres` or override the host.

### D-08 · process · no day-0 SHA was pinned, and `main` has moved again

`main` is now at `39957f3`, three commits past the tree the packet was written against (`4e0f1be`):
`08fbb45` (dashboard HPA), `fb7b449` (**TT-16572 lifecycle enhancements — the re-land of the commit that
was reverted by `4e0f1be`**), `39957f3` (dashboard log format/verbosity). All results here are against
`39957f3`. If TT-17018 pinned an earlier SHA, the upgrade legs should be re-confirmed, because
`fb7b449` touches pod templates.

### D-09 · §8 Q4 is sharper than stated · the released chart is *also* 5.3.0

`helm search repo tyk-helm/tyk-oss --versions` → latest published is **5.3.0**, and the tree under test
also reads `5.3.0`. So TC-01's "upgrade from the last released chart" is a 5.3.0 → 5.3.0 upgrade:
`helm history` shows no version change, and a customer cannot tell from chart metadata whether they have
the TT-17018 behaviour. The release-prep bump to 5.4.0 needs to be tracked and must land before release.

---

## Deliverables

### 1. The three opt-out values files (§6 row 4, TC-04 Step 1)

Written to the working copy, no PR (as scoped):

- `tyk-control-plane/ci/no-securitycontext-values.yaml` — gateway (+init), dashboard (+init), pump, MDCB, bootstrap, dev-portal (+bootstrapJob), operator
- `tyk-stack/ci/no-securitycontext-values.yaml` — as above minus MDCB, plus the `tests:` block
- `tyk-data-plane/ci/no-securitycontext-values.yaml` — gateway (+init), pump, `tests:`

Each disables **all three** gateway blocks (pod, container, init) — a partial opt-out leaves the init
container inheriting `runAsNonRoot: true` with no UID over `busybox:1.32`, which has no USER, and that
fails admission on vanilla Kubernetes. Key irregularities are preserved, not normalised: MDCB
`podSecurityContext`, operator `managerPodSecurityContext` (pod) + `securityContext` (container),
dev-portal blocks at the chart root, and no `tests:` block for `tyk-control-plane`.

Note for Owner 2: the operator and dev-portal sections only render with
`global.components.operator=true` / `devPortal=true`. All of my renders and dry-runs were also run with
those toggles on, so the opt-out surface of every component in every umbrella is covered, not just the
defaults.

Gap found in the **shipped** file while doing this: `tyk-oss/ci/no-securitycontext-values.yaml` has no
operator section, so with `global.components.operator=true` the operator pod keeps
`securityContext: {runAsNonRoot: true}` under the file that is supposed to strip everything
(`evidence/tc04/render-tyk-oss-optout-all.yaml:646`). Harmless on kind and SCC-satisfiable on
OpenShift, but the shipped example is incomplete — worth two lines in the same §7 follow-up as the
three new files.

### 2. Image `USER` table, regenerated against `39957f3` (TC-02 Step 1, §6 row 14)

Every image the four umbrellas render, at the registry the chart actually points at, with all
components enabled. `crane` output; `arch` from the manifest list.

| Image (as the chart sets it) | USER | linux arches |
|---|---|---|
| `docker.tyk.io/tyk-gateway/tyk-gateway:v5.13.1` (`tyk-oss`) | `65532` | amd64, arm64, s390x |
| `tykio/tyk-gateway-ee:v5.13.1` (`tyk-stack`, `tyk-control-plane`, `tyk-data-plane`) | `65532` | amd64, arm64 |
| `docker.tyk.io/tyk-pump/tyk-pump:v1.16.0` (`tyk-oss`) | `65532` | amd64, arm64 |
| `tykio/tyk-pump-docker-pub:v1.16.0` (other three) | `65532` | amd64, arm64 |
| `tykio/tyk-dashboard:v5.13.1` | `65532` | amd64, arm64, s390x |
| `tykio/tyk-mdcb-docker:v2.12.0` | `65532` | amd64, arm64, s390x |
| `tykio/portal:v1.18.0` | `65532` | amd64, arm64, s390x |
| `tykio/tyk-operator:v1.4.2` | `65532:65532` | amd64, arm64 |
| `tykio/tyk-k8s-bootstrap-{pre-install,post,pre-delete}:v2.2.0` | `65532:65532` | amd64, arm64 |
| `busybox:1.32` (gateway init) | **EMPTY (=root)** — safe only because the chart pins `runAsUser: 65532` on that container | multi |
| `curlimages/curl:8.8.0` (portal bootstrapJob) | **`curl_user` (symbolic)** — inert today, no `runAsNonRoot` is asserted over it | multi |
| `zalbiraw/alpine-curl-jq` (helm-test pod, **untagged**) | **EMPTY (=root)** | amd64, arm64 |

Corrections to the packet's own table:

- **The registry split is per umbrella.** `docker.tyk.io/...` is used by **`tyk-oss` only**. `tyk-stack`,
  `tyk-control-plane` and `tyk-data-plane` render `tykio/tyk-gateway-ee` and `tykio/tyk-pump-docker-pub`
  from Docker Hub. The packet's shared-setup table presents `docker.tyk.io` as the gateway/pump source
  generally, which is only true for OSS.
- **`tykio/tyk-gateway-ee:v5.13.1` is still in use** and is numeric (`65532`) — the packet's note that
  `e92f013` "moved the umbrellas off `tyk-gateway-ee`" does not hold for this tree. Since the EE tag is
  in the safe band this is not a defect, but the audit table should say so.
- **`gcr.io/kubebuilder/kube-rbac-proxy` never renders.** Operator v1.4.2 secures metrics in the manager
  itself; no sidecar appears in any umbrella's output. The umbrella values still carry
  `tyk-operator.rbac.image.tag: v0.8.0` (the packet expected `v0.15.0`) — dead config, worth a §7 note.
  "Operator sidecar not checked" is therefore moot rather than outstanding.
- **The helm-test pod image is a third-party personal Docker Hub repo, pinned to nothing**
  (`zalbiraw/alpine-curl-jq`, no tag → `:latest`, root). It is only used by `helm test`, but it is an
  unpinned mutable dependency in a shipped chart and it is worth raising separately from TT-17018.

### 3. Release-note addition for the 5.4.0 changelog (§6 row 13)

The repo already carries a good upgrade note (`tyk-stack/README.md` "Upgrade notes", mirrored per
component). It documents the failure string, both failing image classes, which default tags changed, how
to check an image's USER, and the `enabled: false` opt-out with the full irregular-key table. Three
additions are needed — the third added by Owner 2 after the ROSA run established the per-chart split:

> **Do not use `helm upgrade --reuse-values` for this upgrade.** `--reuse-values` carries your previous
> release's `containerSecurityContext.runAsUser` (`1000` on charts ≤ 5.3.0) forward, while the
> `setup-directories` init container — which is a **new** values key in this release — takes its new
> default of `65532`. The two UIDs then disagree: the init container creates
> `/mnt/tyk-gateway/{apps,middleware,policies}` as `65532` and the gateway, still running as `1000`,
> cannot write to them. Pods stay Ready and no events are emitted; the symptom is `HTTP 500`
> `file object creation failed, write error` from the gateway API, with
> `Failed to create file! - open /mnt/tyk-gateway/apps/<id>.json: permission denied` in the log.
> Use `--reset-then-reuse-values` (Helm ≥ 3.14) or pass your overrides explicitly. If you have already
> upgraded this way, `helm upgrade --reset-then-reuse-values` repairs it with no further changes.

> **How badly this bites depends on the chart — but every chart ends up in the same broken state.**
> On **`tyk-oss`** the failure is immediate and obvious: API definitions are stored as files in
> `/mnt/tyk-gateway/apps`, so the very next API create or update returns the `HTTP 500` above.
> On **`tyk-stack`**, **`tyk-control-plane`** and **`tyk-data-plane`** the same mismatched UIDs are
> present, but API definitions live in the dashboard database, so ordinary traffic never touches that
> volume and **nothing surfaces** — pods are Ready, requests proxy normally, and the install looks
> healthy. The likely trigger there is anything that writes to the volume at runtime, plugin bundle
> downloads into `/mnt/tyk-gateway/middleware` being the obvious one. **Apply the repair regardless of
> which chart you run** — a latent mismatch is still a mismatch, and it will surface at whatever moment
> the gateway first needs to write.

> **The gateway's image `USER` is not monotonic across versions.** `v5.8.13`–`v5.8.15` and `v5.13.0`+ ship
> `USER 65532`; **`v5.9.0` through `v5.12.0` ship `USER 0`**. Re-pinning to a "newer" tag in that band
> reintroduces the admission failure above. Dashboard images are non-root from `v5.5.0`.

### 4. Notes handed to Owner 2

- The three values files above (they are the inputs to TC-04 Steps 4–10).
- Gap #9 verdict: `tyk-operator.podSecurityContext` is dead; use
  `--set tyk-operator.managerPodSecurityContext.enabled=false` (or the values file above). You are **not**
  blocked, and the surviving default (`runAsNonRoot: true`, image USER `65532:65532`) is SCC-compatible.
- The image/USER/arch table above, including the per-umbrella registry split.
- TC-06 secret shape used here, so your Step 6 live check matches: secret `mdcb-creds` with keys
  `orgId`, `userApiKey`, `groupID` for `useSecretName`; separate secret `mdcb-conn2` with key
  `connectionString` for `connectionStringSecretName`.
- Redis/PostgreSQL: install PostgreSQL as release **`tyk-postgres`** or override
  `global.postgres.host`; the chart default is `tyk-postgres-postgresql.<ns>.svc`. Bitnami now serves
  rolling `:latest` images (D-06) — pin them yourself if that matters on your cluster.

---

## CI coverage, verified in `.github/workflows/` (not inferred)

Checked because several §7 follow-ups depend on it:

| Claim | Verified on `39957f3` |
|---|---|
| CI never installs the opt-out values files beyond `tyk-oss` | **True.** `smoke-tests-no-securitycontext` hardcodes `-f ./tyk-oss/ci/no-securitycontext-values.yaml` (`run-tests.yaml:265`) and is pinned to a single k8s version, `v1.30.0`. Adding the three new files changes nothing until that job is parameterised. |
| `ct` is lint-only | **True.** `ct lint --config ct.yaml --all` (`run-tests.yaml:60`); there is no `ct install` anywhere. |
| CI's "upgrade" coverage is the branch chart onto itself | **True.** `helm upgrade ... ./tyk-oss --reuse-values --set tyk-gateway.gateway.kind=DaemonSet` (`:109`) and the same for `tyk-data-plane` (`:144`). Same chart both sides — which is exactly why **D-01 was invisible to CI even though CI uses `--reuse-values`**. |
| The smoke matrix ends at 1.26.13 / 1.30.0 | **True** for `smoke-tests` (`["v1.26.13","v1.27.10","v1.28.6","v1.29.4","v1.30.0"]`), so testing the two ends matches CI's own bounds. Note `integration-tests` separately runs on **`kindest/node:v1.34.0`** — a version outside the plan's matrix entirely. |
| Unit-test discovery is fixed | **True.** `unit-tests.yaml` vendors `file://` deps for every chart and then discovers any chart with root-level `tests/*_test.yaml`, which is the same set my run used (6 charts / 31 suites / 216 tests). |
| Bitnami dependency handling | CI **already works around the Bitnami catalogue change** by overriding every image to `bitnamilegacy/*` (`run-tests.yaml:92-99`). The packet's and the repo docs' Redis/PostgreSQL commands do not, which is why every install in this run printed `WARNING: Rolling tag detected (bitnami/redis:latest)`. Copy CI's overrides into the docs (D-06). |

---

## Scope: what this run did not cover

Stated so the sign-off meeting accepts it knowingly.

| Not done | Why / what it would take |
|---|---|
| **TC-11 on k8s 1.27, 1.28, 1.29** | The two ends agreed on every criterion, so there is nothing to bisect. Kept in reserve, per the packet. |
| **CI's `integration-tests` k8s version (`v1.34.0`)** | Outside the plan's matrix. Not run here. Worth adding to the plan rather than to this pass — the ends of the *plan's* matrix are 1.26/1.30, but CI already exercises 1.34 elsewhere. |
| **Anything OpenShift / SCC** | Owner 2's packet by design. PSA `restricted` on kind is the closest analogue and it passed. |
| **The `tyk-stack` gateway's emptyDir write paths after `--reuse-values`** | The UID mismatch is present but stock dashboard-managed traffic does not write there, so no failure was provoked. Plugin-bundle downloads are the plausible way to hit it; not tested. |
| **`helm test` on `tyk-control-plane`** | It ships no test pod by design (no `tests:` block) — confirmed, not a gap. |

## For the Thursday review

| # | Question | What this run adds |
|---|---|---|
| **Q1** | Pinned-old-tag upgrades: release note only, or a `semverCompare` guard / `NOTES.txt` warning? | The in-repo note is already strong (failure string, both failing image classes, per-chart tag table, `crane` recipe, escape route). What it lacks is the **`--reuse-values` hazard (D-01)** and the **non-monotonic tag bands (D-05)**. My recommendation: ship the note with those two additions, and add a `NOTES.txt` warning only for the `--reuse-values` case, because that one is silent and a note nobody reads cannot save them. |
| **Q3** | If QA finds a P0 — revert or fix forward? | **This is now live: D-01.** It is not fixed by reverting TT-17018 either — the init-container key is what creates the asymmetry, so a revert removes the feature *and* the hazard, while fixing forward means a doc/`NOTES.txt` warning or making the init UID follow the main container's when one is explicitly set. Needs a decision, not a preference. |
| **Q4** | Chart version reads `5.3.0` while the fix version is 5.4.0 | Confirmed, and **sharper than the plan thought: the latest *published* chart is also 5.3.0** (D-09). The upgrade under test does not change the chart version at all. |
| **Q6** | Gap #9 — expose `managerPodSecurityContext`, remove or document the dead key? | Verdict delivered (D-02): dead key confirmed dead, working key confirmed working and already documented in the README. Recommend adding `managerPodSecurityContext` to the umbrella values and deleting `podSecurityContext`. Not a blocker. |
| **Q7** | Confirm the scope trims | All four trims held up. Additionally: the three values files genuinely add **no** CI install coverage without editing `run-tests.yaml` (verified, see the CI table). |

---

## Per-test-case results

Format follows `00-shared-setup.md` §6. SHA is `39957f3` throughout; cluster is stated per row.

### TC-04 Steps 1–3 · opt-out values files, render check, gap #9

| Step | Command | Result | Verdict |
|---|---|---|---|
| 1 | (authored three `ci/no-securitycontext-values.yaml` files) | All three parse, cover every component in their umbrella, disable all three gateway blocks | **PASS** |
| 2 | `helm template t ./<u> -f ./<u>/ci/no-securitycontext-values.yaml \| grep -nE 'fsGroup:\|runAsUser:\|enabled:'` | **No matches** for all four umbrellas, both with default toggles and with `pump`/`devPortal`/`operator` all enabled. Anti-vacuity: the same grep against the baseline render matches 5–10 times per umbrella, so the grep is meaningful. Only surviving block anywhere is the operator's under `tyk-oss`'s **shipped** file, which has no operator section | **PASS** |
| 3 | `--set tyk-operator.podSecurityContext.enabled=false` vs `--set tyk-operator.managerPodSecurityContext.enabled=false` | dead key → `runAsNonRoot: true` survives; live key → `null`. Gap #9 **confirmed** | **PASS** on the packet's criterion (second command works) + **defect D-02** on the first |

### TC-09 · regression suite, lint, anti-vacuity — kind 1.26 (render-level, cluster-independent)

| Step | Result | Verdict |
|---|---|---|
| 1 · unit tests | `helm unittest` over the 6 discovered charts: **216 passed / 216, 31 suites, 6 charts** (re-baselined from the branch's 189/29/6). Two warnings on `tests.containerSecurityContext.{capabilities,seccompProfile}`: `cannot overwrite table with non table` | **PASS** |
| 2 · lint | **11 charts linted, 0 failed** (packet's own command lints only 4 — D-07) | **PASS** |
| 3 · anti-vacuity | Reverted the null-`annotations` guard on `bootstrap-serviceaccount.yml` → suite goes **red**, `components/tyk-bootstrap/tests/bootstrapRbacMetadata_test.yaml` fails with `metadata.annotations expected to NOT exists`. Tree restored. Extended to a 23-site mutation sweep: 21 caught, 1 real gap, 1 equivalent mutant | **PASS + defect D-03** |
| 4 · CI discovery | Out of scope by design; CI config inspected instead (see CI table) | skipped knowingly |

Worth noting from the sweep: the umbrella-level suite `tyk-stack/tests/bootstrapAnnotationQuoting_test.yaml`
stayed green for the Step-3 revert while the component-level suite failed, i.e. the umbrella copy of that
suite does not cover the ServiceAccount path.

### TC-10 · field-leak / API-strictness sweep

| Step | Result | Verdict |
|---|---|---|
| Anti-vacuity first | A hand-written Deployment carrying `securityContext.enabled: true` at pod and container level is **rejected**: `strict decoding error: unknown field "spec.template.spec.containers[0].securityContext.enabled", unknown field "spec.template.spec.securityContext.enabled"`. The same manifest **passes** `--dry-run=client`, confirming the false-pass trap | proven |
| 1 · four umbrellas, server-side | Clean on **kind 1.26.13 and 1.30.0**, with default toggles and with all components enabled | **PASS** |
| 2 · per component (8) | gateway, dashboard, pump, MDCB, dev-portal, operator, bootstrap, helm-test pod — each rendered with only its own opt-out and applied server-side: **no `unknown field` for any of the 8**. The helm-test pods (`tyk-oss`, `tyk-stack`, `tyk-data-plane`) render with `podSC: null`, `ctrSC: null` and are accepted | **PASS** |

The operator's own dry-run is partial on a cluster without cert-manager: `Certificate` and `Issuer`
have no mapping (`ensure CRDs are installed first`). Service, Deployment and both webhook
configurations were validated.

### TC-02 · pinned older image tag · **P0**

| Step | Result | Verdict |
|---|---|---|
| 1 · image USER audit | Full table above. Every Tyk image numeric (`65532`); `busybox:1.32` empty (safe, UID pinned by the chart); `curlimages/curl:8.8.0` symbolic `curl_user` (inert — the rendered bootstrap job carries no `runAsNonRoot`); `zalbiraw/alpine-curl-jq` untagged and root | **PASS** (+ two packet corrections, D-07 #3) |
| 1b · gateway default tag in the safe band | `docker.tyk.io/tyk-gateway/tyk-gateway:v5.13.1` → `USER=65532`. Bands re-confirmed: `v5.9.1` → `0`, `v5.12.0` → `0`, `v5.13.1` → `65532` | **PASS** |
| 1c · the two non-numeric images | Confirmed as described. Rendered portal bootstrap job has **no** `runAsNonRoot`, so `curl_user` is not asserted against | **PASS** |
| 2 · install released chart with an old pinned tag | `helm install tyk-stack tyk-helm/tyk-stack --version 5.3.0 -n tyk-old --set tyk-dashboard.dashboard.image.tag=v5.4.0` → all three pods Ready; dashboard pod carries `runAsUser: 1000` at pod and container level | **PASS** |
| 3 · upgrade to `main` keeping the pin | Dashboard pod → **`CreateContainerConfigError`**, event verbatim: `Error: container has runAsNonRoot and image will run as root (pod: "dashboard-tyk-stack-tyk-dashboard-...", container: dashboard-tyk-dashboard)`. Gateway and pump unaffected. `helm upgrade` itself exits 0 and reports `STATUS: deployed` | **PASS** (fails exactly as documented) |
| 4 · docs check | The failure string, both failing image classes, the per-chart default-tag table, the `crane` check and the `runAsUser` escape route are all in `tyk-stack/README.md` (and mirrored in `components/tyk-{dashboard,gateway}/README.md`). Missing: the tag **bands** (D-05) and `--reuse-values` (D-01) | **PASS with gaps** |
| 5 · escalate the decision | §8 Q1 recorded above; team decision still owed | open |

### TC-06 Steps 1–5 · data-plane connection-string secret

| Step | Result | Verdict |
|---|---|---|
| 1 · literal | renders `value: "tcp://mdcb:9091"`, no `valueFrom` | **PASS** |
| 2 · secret, default key | renders `valueFrom.secretKeyRef{name: mdcb-conn, key: connectionString}`, no literal alongside | **PASS** |
| 3 · custom key | `key: myKey` | **PASS** |
| extra · both set | secret wins, single `valueFrom`, no invalid dual render | **PASS** |
| 4 · the real regression | Installed released `tyk-data-plane` 5.3.0 with `useSecretName=mdcb-creds` (keys `orgId`/`userApiKey`/`groupID`, **no** `connectionString`) **plus** a literal `connectionString`, then upgraded to `main`. Rollout clean, **no** `couldn't find key connectionString in Secret`, no such string in gateway logs, and the live env still reads `RPCKEY→mdcb-creds/orgId`, `APIKEY→mdcb-creds/userApiKey`, `GROUPID→mdcb-creds/groupID`, `CONNECTIONSTRING=tcp://mdcb.example.svc:9091`. Decoupling holds | **PASS** |
| 5 · pump parity | `components/tyk-pump/templates/deployment-pmp.yaml:95-102` carries the identical `secretKeyRef` / `else` literal branch | **PASS** |
| bonus (Owner 2's Step 6, live) | Upgraded again with `connectionStringSecretName=mdcb-conn2`: live pod env shows `TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING → mdcb-conn2/connectionString`, gateway Ready | **PASS** |

### TC-01 · upgrade from the released chart · **P0**

Baseline in every row is released `tyk-helm/tyk-oss` (or `tyk-stack`) **5.3.0**; target is the working
copy at `39957f3`. Redis at `redis-master.tyk.svc:6379`; PostgreSQL at
`tyk-postgres-postgresql.tyk.svc` for the stack legs.

| Umbrella | k8s | Path | Result | Verdict |
|---|---|---|---|---|
| `tyk-oss` | 1.26.13 | plain `helm upgrade` | Rollout clean. Pod-level `fsGroup: 2000` **retained**, pod `runAsUser` removed; container `runAsUser` **removed** (not changed to 65532 — see note); init container keeps its own `runAsUser: 65532` and exits 0; image v5.9.1 → v5.13.1. New API create `200`, proxy `200` | **PASS** |
| `tyk-oss` | 1.30.0 | plain `helm upgrade` | Identical on every criterion | **PASS** |
| `tyk-oss` | 1.26.13 | `--reuse-values` | Pods Ready, but container stays `runAsUser: 1000` / image v5.9.1 while init moves to 65532 → API create `HTTP 500 file object creation failed, write error`, log `permission denied` | **FAIL — D-01** |
| `tyk-oss` | 1.30.0 | `--reuse-values` | Identical failure, same error strings | **FAIL — D-01** |
| `tyk-oss` | 1.26.13 / 1.30.0 | `--reset-then-reuse-values` (workaround) | Container `runAsUser` dropped, image v5.13.1, API create `200`, proxy `200` | **PASS** (this is the escape route) |
| `tyk-stack` | 1.26.13 | plain `helm upgrade` | Gateway, dashboard, pump all Ready; container `runAsUser` removed, init 65532, image `tykio/tyk-gateway-ee:v5.13.1` | **PASS** |
| `tyk-stack` | 1.30.0 | plain `helm upgrade` | Identical; `helm test` passes twice afterwards | **PASS** |
| `tyk-stack` | 1.26.13 | `--reuse-values` | Same stale-1000 / new-65532 split as `tyk-oss`; pods Ready and no write error surfaced in a short run (dashboard-managed gateway does not write to that emptyDir) | **latent — see D-01 scope note** |
| `tyk-data-plane` | 1.26.13 | plain `helm upgrade` (via TC-06 Step 4) | Rollout clean, gateway and pump Ready, env resolution intact | **PASS** |
| `tyk-control-plane` | 1.26.13 + 1.30.0 | plain `helm upgrade` | Gateway, dashboard, **MDCB** all Ready on both versions; MDCB reconnects to Redis/Postgres; dashboard-created API still served; a **new** API created post-upgrade reaches a released-5.3.0 data plane over MDCB RPC and proxies `200` | **PASS** |
| `tyk-control-plane` | 1.26.13 + 1.30.0 | `--reuse-values` | Same stale-1000 / init-65532 split as the others, **but everything keeps working**: dashboard `200`, gateway serves a newly created API `200`, zero `permission denied` — dashboard-managed APIs live in Postgres, not the emptyDir. **Latent**, not failing | **PASS (latent D-01)** |
| `tyk-data-plane` vs **real MDCB** | 1.26.13 + 1.30.0 | plain + `--reuse-values` | Full topology: CP API syncs over RPC and proxies `200` before, during and after every upgrade path. Under `--reuse-values` straight off 5.3.0 (1.30, ns `tyk-dp3`) the UID split is present but RPC-loaded APIs live in memory → still `200`, zero write errors. **D-01 does not bite MDCB mode** | **PASS (latent D-01)** |

Two methodology notes that matter for anyone re-running this:

- **Step 5's pass criterion needs rewording.** The container's UID does not "move `1000 → 65532`" — the
  chart stops emitting `runAsUser` at all, and the effective UID comes from the image's `USER 65532`.
  The `--reuse-values` failure is itself the proof that the effective UID follows whatever the manifest
  says (writes into 65532-owned directories fail while the manifest pins 1000, and succeed once it is
  dropped). Note the gateway images are distroless, so `kubectl exec ... id` is not available to confirm
  it directly; an ephemeral-container probe was attempted and abandoned as not worth the time.
- **Step 2/Step 7's "state survived" leg cannot pass by construction.** `tyk-oss` stores API definitions
  as files under `/mnt/tyk-gateway/apps`, and that path is an **emptyDir** (`tyk-scratch`) with no PVC
  option in the chart. Any pod replacement loses them, so a pre-upgrade API always returns 404
  afterwards — on both versions, on a fixed tree as much as a broken one. **The meaningful signal is the
  write leg (create a *new* API), which is exactly what caught D-01.** Recommend the packet drop the read
  leg or replace it with a dashboard-managed umbrella where state lives in PostgreSQL.

### TC-11 · backwards compatibility on vanilla Kubernetes · **P0**

Stock values (no opt-out), fresh installs of the chart under test.

| Step | 1.26.13 | 1.30.0 | Verdict |
|---|---|---|---|
| 1 · gateway init container + emptyDir | init exits 0, gateway Ready, pod-level `fsGroup: 2000` present | same | **PASS** |
| 2 · init/main UID alignment | API create `200`, proxy `200` | same | **PASS** |
| 3 · dashboard `init-analytics-conf` on the legacy path | Init container renders **only for a non-`v` tag** (D-04). Rendered with `tag=5.0.2`: init has **its own** `securityContext` with `runAsUser: 1000` — not inheriting. Installed for real by retagging `v5.0.2 → 5.0.2` locally and `kind load`-ing it, with `containerSecurityContext.runAsUser=1000` restored (needed because that image has no numeric USER): init exits 0, dashboard Ready | render verified; install verified on 1.26 | **PASS + D-04** |
| 4 · pump `extraContainers` with `pump.securityContext.enabled: false` | sidecar renders **and runs**: `containers = pump-tyk-pump qa-sidecar`, both `ready=true`, pod-level securityContext omitted | same, also under PSA `restricted` | **PASS** |
| 5 · Pod Security Admission `restricted` | namespace labelled, deployment restarted, pod admitted and Ready, zero `forbidden`/`violate`/`PodSecurity` events | same | **PASS** |
| 6 · `helm test` (run it twice) | `tyk-oss` **3 consecutive runs**, all `Phase: Succeeded`, **no** `configmaps ... already exists`; no leftover test pods or configmaps | `tyk-oss` ×3 and `tyk-stack` ×2, all Succeeded | **PASS — and the packet's "known-expected failure" no longer reproduces** |

On Step 6: `tyk-oss/templates/tests/script-configmap.yaml` already carries
`"helm.sh/hook-delete-policy": hook-succeeded,hook-failed`, which is the fix for the issue Sedky raised.
Treat that item as **fixed on `main`**, not as a defect to confirm — but do check the separate ticket was
closed rather than left open against a fixed tree.

### Bonus for Owner 2 · the three new values files were installed, not just rendered (gap #3)

The packet only asks for the files to be authored, with Owner 2 installing them on OpenShift. Since the
licence arrived, I installed two of them on kind `v1.30.0` first, so Owner 2 starts from a known-good
baseline rather than debugging the file and the SCC at the same time:

| Umbrella + opt-out file | Result |
|---|---|
| `tyk-data-plane` | gateway, pump Ready. Rendered pods carry **no** container or init `securityContext` at all (pod-level shows the API server's empty `{}`). `helm test` `Succeeded` with the `tests:` blocks disabled too |
| `tyk-stack` | gateway, dashboard, pump Ready. **Both bootstrap hook Jobs ran to completion with their security contexts disabled** (`bootstrap-pre-install` → `Job completed`, then `bootstrap-post-install`), the dashboard bootstrapped its org/user, and the gateway registered with it. `helm test` `Succeeded` |
| `tyk-control-plane` | not installed — MDCB licence missing. Render + server-side dry-run only |

This is the first time the dashboard, bootstrap and helm-test opt-outs have been **installed** anywhere
(gap #3). On kind nothing injects a UID, so this proves the manifests are valid and the workloads start
without any securityContext — **not** that an SCC accepts them. That part remains Owner 2's TC-04.

---

## Sign-off tracker — Owner 1 rows

| # | Item | Status |
|---|---|---|
| 1 | TC-01 on 1.26 + 1.30, three umbrellas, ± `--reuse-values` | ◐ **evidence complete for all four umbrellas on both k8s versions — held open only by the D-01 decision.** Plain path green everywhere; `--reuse-values` fails hard on `tyk-oss`, latent on the dashboard/MDCB umbrellas |
| 2 | TC-02 documented + pinned-tag decision made | ◐ evidence complete, **team decision outstanding** (§8 Q1) |
| 4 | Three values files authored; gap #9 resolved | ☑ files authored, rendered, dry-run and (2 of 3) installed; gap #9 verdict delivered (D-02) |
| 6 | TC-06 incl. the `useSecretName` upgrade regression | ☑ render + live install + upgrade + new secret path |
| 9 | TC-09 green with the anti-vacuity check | ☑ 216/216, revert goes red; D-03 filed against the suite, not the chart |
| 10 | TC-10 zero field leaks, server-side | ☑ 8/8 components, both k8s versions, strict decoding proven |
| 11 | TC-11 green on 1.26 and 1.30 | ☑ all six steps, both versions |
| 13 | Upgrade release note | ◐ draft additions supplied (D-01, D-05) — needs a home, since the repo has **no CHANGELOG**; today the note lives in each umbrella's README |
| 14 | OpenShift docs complete | ◐ opt-out documented well; tag bands (D-05) and Redis/PostgreSQL caveat (D-06) missing |

## Second pass — MDCB licence arrived; every blocked leg completed (2026-08-26, later the same day)

The MDCB licence unblocked everything that was licence-gated, and a second due-diligence sweep was run
over the areas the first pass could not reach. Same tree (`39957f3`), kind `v1.30.0` first, then a fresh
kind `v1.26.13` (`tyk-qa-126b`) for the 1.26 legs. Full transcripts: `evidence/k130-*`, `evidence/k126-p0-run.log`.

### Control plane, end to end — the last P0 hole, closed

Released `tyk-control-plane` 5.3.0 installed with dashboard + MDCB licences (gateway, dashboard, MDCB
all Ready), an API created through the dashboard, and a released `tyk-data-plane` 5.3.0 connected to
the **real MDCB** (`Detected 1 APIs`, proxies `200`). Then, on both 1.26.13 and 1.30.0:

| Leg | Result |
|---|---|
| CP plain upgrade → main | All three deployments roll cleanly; MDCB healthy; **cross-version sync proven**: an API created on the upgraded CP reaches a data plane still on 5.3.0 and proxies `200` |
| CP `--reuse-values` | UID split present (gateway container 1000, init 65532) — **latent, everything works**: dashboard-created API served `200`, zero `permission denied`. Dashboard-managed definitions live in Postgres, not the gateway emptyDir |
| DP plain upgrade → main (real MDCB) | Rollout clean, re-syncs, proxies `200` |
| DP `--reuse-values` straight off 5.3.0 (real MDCB, ns `tyk-dp3` on 1.30) | UID split present, **but RPC-loaded APIs live in memory → still `200`, zero write errors. D-01 does not bite MDCB mode** |
| CP opt-out values file installed live | All three pods Ready with every securityContext omitted, on both k8s versions — the control-plane opt-out file is now **installed**, not just rendered |
| TC-06 Step 6, live | Connection string moved to a secret with a **custom key** (`mdcb-conn-live/mdcbUrl`) against the real MDCB — gateway reconnects and proxies `200` |

This sharpens D-01's blast radius: **hard failure is `tyk-oss` only** (file-based API storage in the
emptyDir); `tyk-stack`, `tyk-control-plane` and MDCB-mode `tyk-data-plane` carry the same wrong UID pair
but keep serving. The release-note wording should say exactly that.

### TC-02, gateway leg (previously only the dashboard was pinned)

`helm install ./tyk-oss --set tyk-gateway.gateway.image.tag=v5.9.1` on main → the **init container
passes** (it pins 65532) and the **main container** fails with the verbatim documented error:
`Error: container has runAsNonRoot and image will run as root (container: gateway-tyk-gateway)`.
The documented escape route (`containerSecurityContext.runAsUser=1000` + pod-level ditto) upgrades to
`deployed` with `--wait`. Evidence: `evidence/tc02-gateway-pin-130.txt`.

### Operator and dev portal — installed for real (with cert-manager), two new findings

- **D-10 · plan accuracy · `global.license.operator` must be set explicitly, and the packet's day-0
  list omits it.** The operator accepts the **same JWT as the dashboard licence** (verified:
  `License validated successfully`), but the chart does not reuse `global.license.dashboard` for it —
  with `operator=true` and `global.license.operator` unset, tyk-operator v1.4.2 CrashLoops on
  `kindly specify a valid license key`. It admits and starts (so the TT-17018 securityContext part is
  fine) and then exits. The day-0 "Resolve licences" item names Dashboard and MDCB only; it should say
  "set the dashboard licence in *both* `global.license.dashboard` and `global.license.operator`". One more trap on the same
  path: the licence lands in the `tyk-operator-conf` Secret, so `helm upgrade` alone never fixes a
  crash-looping operator — the pod must be restarted (the chart's own NOTES say so, quietly).
  **Sharpened on `tyk-stack` (third pass):** enabling the operator on an *existing* release via
  `helm upgrade` fails twice over — (a) `tyk-operator-conf` is bootstrap-managed and the upgrade never
  writes `TYK_OPERATOR_LICENSEKEY` into it (crash: `kindly specify a valid license key`), and
  (b) Helm never installs subchart `crds/` on upgrade, so once the licence is fixed the operator
  crashes on `unable to create controller: no matches for kind`. Recovery: patch the secret, apply
  `tyk-operator-crds/crd-v1.4.2.yaml` by hand, restart the deployment — after which reconciliation
  works end to end. Enabling the operator at *install* time hits neither problem. Both are
  pre-existing operator-chart behaviours, not TT-17018 regressions, but they belong in the docs
  (`tyk-operator-crds/` exists precisely for this and nothing points at it).
- **Gap #9 verified live, not just in renders:** on the running operator,
  `--set tyk-operator.podSecurityContext.enabled=false` leaves `{"runAsNonRoot":true}` on the live pod;
  `--set tyk-operator.managerPodSecurityContext.enabled=false` rolls it to an empty pod securityContext
  with the operator Ready. Evidence: `evidence/operator-130-optout-live.txt`.
- **Dev portal installed** (`tyk-stack` + `devPortal=true` + `tyk-dev-portal.license=<dashboard licence>`):
  portal StatefulSet Ready, the `curlimages/curl` **bootstrapJob ran to completion**, portal answers
  HTTP 200. Then upgraded with the new opt-out file: portal pod re-rolls with **no securityContext at
  all and stays Ready**, still HTTP 200. The portal + bootstrapJob opt-outs — the last never-installed
  blocks — are now installed. Evidence: `evidence/portal-130-*.txt`.

### The 5.4.0 bump itself, simulated

`tyk-oss/Chart.yaml` bumped to `version: 5.4.0` locally, then released 5.3.0 → local 5.4.0 upgraded:
`helm history` shows `tyk-oss-5.3.0 → tyk-oss-5.4.0`, rollout clean, post-upgrade API create/proxy `200`.
The bump is mechanical; nothing in the upgrade path depends on it. §8 Q4 still needs the real bump
tracked — this proves it is release-prep work, not a test risk. Evidence: `evidence/tc-540-bump-history.txt`.

### Due-diligence sweep over what the first pass took on trust

| Check | Result |
|---|---|
| **Full render diff, released 5.3.0 → main, all four umbrellas** | Only intended deltas: the securityContext work; `tyk-oss` gateway v5.9.1→v5.13.1; bootstrap RBAC/pod metadata (labels added, null annotations gone); dashboard `TYK_DB_LOGFORMAT`/`TYK_DB_LOGLEVEL` env vars (TT-16461); and removal of **empty `volumeMounts:`/`volumes:` stubs** the old pump deployment rendered. No unexplained changes from the three post-packet commits. `evidence/render-diff-summary.txt` |
| **Umbrella helm-test templates** (separate `omit` implementations the component mutation sweep never touched) | All three strip `enabled` correctly with fields + `enabled: true` set — no leak |
| **The new ci files under CI's own lint** | `ct lint` lints every `ci/*-values.yaml` it finds, so the three new files become CI input the moment they merge — all three pass `helm lint -f` today |
| **TC-06 docs** | `tyk-data-plane/README.md` already documents `connectionStringSecretName`/`connectionStringSecretKey`, the `useSecretName` independence, and the migration note — no docs gap here |
| **HPA (TT-15287) + lifecycle (TT-16572) under the opt-out file** | Render together cleanly, HPA object present, zero parse errors — no interaction with the securityContext work |
| **MDCB observation (not TT-17018)** | MDCB v2.12.0 logs `relation "tyk_client_idps" does not exist` warnings on a fresh Postgres before continuing — benign but worth a known-issues line somewhere |

### Updated verdict on §6 row 1

All four umbrellas now have live upgrade evidence on both matrix ends, both upgrade paths. The row is
**evidence-complete**; what holds it open is only the D-01 decision (release note + `NOTES.txt` warning
vs template-level defence), which is §8 Q3's call, not more testing.

## Third pass — functional smoke beyond deployability (2026-08-27)

TT-17018 is a deployability ticket, so the packet's evidence stops at "pods Ready and traffic proxies."
On request, a full functional chain was run on top of the chart under test (`tyk-stack` +
`devPortal=true` from `main`, kind `v1.26.13`, ns `tyk-full`) to confirm the deployed stack actually
*works* as a product, not just as a set of Ready pods. Evidence: `evidence/functional-flow-summary.txt`
plus browser screenshots in the session.

| Step | Result |
|---|---|
| Dashboard UI login (email/password, CSRF-correct form post) | `302 /` on success; `302 /?fail=true` on a wrong password |
| API + policies via dashboard API | `orders-api` (auth-token), product policy (`partitions.acl`), Bronze plan (`rate 10/60s`, `quota 1000/h`) — product/plan split imports exactly as the partitions dictate |
| Portal provider | connected to the dashboard over the admin API, synchronized; product + plan imported |
| Publishing | product + plan published to the Public Catalogue (`PUT /portal-api/catalogues/1` with **plain-ID arrays** — object arrays are silently ignored) |
| Developer signup | created via `portal-api`; **the activation email fails without SMTP** (`default from email not set`), so `Active` + password were set through the admin API — expected behaviour for a mail-less cluster, worth knowing for demos |
| Developer UI login | works in a real browser. **Not scriptable with curl**: the portal theme injects the CSRF token from a `<meta>` tag via JavaScript, so plain form posts get `400 Bad Request` from `nosurf` even with the cookie — a browser (or headless JS) is required |
| Access request | catalogue → product page → Bronze plan → cart → app selected → submitted (`pending`) |
| Approval + provisioning | approved via `PUT /portal-api/access_requests/1/approve`; credential issued and provisioned into the gateway |
| Enforcement | portal-issued key → `200`; no key → `401`; bogus key → `403`; **the Bronze plan's 10/min rate limit returns `429` from exactly the 11th call in the window** |
| Standalone component charts | `components/tyk-gateway` and `components/tyk-pump` installed directly (not through an umbrella) — both Ready, same securityContext rendering |
| **Operator reconciliation** | On the live cluster (`tyk-stack` + `operator=true` + cert-manager): an `ApiDefinition` CR reaches `status.latestTransaction: Successful`, the API answers `200` through the gateway, and **deleting the CR takes the route back to `404`** — full create/delete reconciliation proven, licence validated (`Valid till 2026-09-19`), 13 controllers running |

### Chart-level coverage matrix (which of the 11 charts got what)

Installs in passes 1–2 all went **through the umbrellas** — that is how the packet, CI and customers
consume the components, and the umbrellas vendor them via `file://` so the exercised templates are
byte-identical to the component charts. What each chart got directly:

| Chart | lint | unit tests | standalone render + server-side dry-run | installed & running |
|---|---|---|---|---|
| tyk-oss / tyk-stack / tyk-data-plane / tyk-control-plane | ✅ | ✅ (stack, CP; oss/dp suites live in-umbrella) | ✅ | ✅ (installed + upgraded, both k8s versions) |
| components/tyk-gateway | ✅ | via umbrella suites | ✅ | ✅ via every umbrella **and standalone** (`tyk-solo`) |
| components/tyk-pump | ✅ | ✅ | ✅ | ✅ via umbrellas **and standalone** (`tyk-solo`) |
| components/tyk-dashboard | ✅ | ✅ | ✅ | ✅ via tyk-stack / tyk-control-plane |
| components/tyk-mdcb | ✅ | via CP umbrella suite | ✅ | ✅ via tyk-control-plane (real MDCB, licence) |
| components/tyk-dev-portal | ✅ | ✅ | ✅ | ✅ via tyk-stack (`devPortal=true`, bootstrapJob ran) |
| components/tyk-bootstrap | ✅ | ✅ | ✅ | ✅ via tyk-stack hooks (pre/post jobs completed) |
| components/tyk-operator | ✅ | via umbrella suites | ✅ (cert-manager CRDs excepted) | ✅ via `operator=true` + cert-manager + licence (D-10) |

Nothing ships from this repo that was never installed. `tyk-operator-crds/` is not a Helm chart at all —
it is a directory of raw CRD manifests (`crd-v*.yaml`, no `Chart.yaml`), applied by the operator install
flow; it has no render surface and is outside `helm lint`/`ct` entirely.

## Reproducing this

```bash
cd ~/playground/tt17018-owner1                 # clone + evidence + helper scripts
git -C tyk-charts rev-parse HEAD               # 39957f3660212154296b6ffc9ab733f822e6809d
./mutation-sweep.sh                            # TC-09 Step 3, extended (uses tyk-charts-mutation/)
./run130.sh                                    # the whole kind v1.30.0 pass, start to finish
./gw-api.sh <ns> <release> create|get|proxy <api-id>   # gateway API state helper
./stack-leg.sh <ns> <postgres-db> ["--reuse-values"]   # released tyk-stack -> main
```

Clusters ran one at a time throughout, per the packet: `tyk-qa-126` (pass 1) and `tyk-qa-130` were
deleted after their runs. The second-pass 1.26 cluster **`tyk-qa-126b` is still running** with the
control-plane/data-plane topology in place (`tyk`, `tyk-cp`, `tyk-cp-ru`, `tyk-dp`) if anything needs
re-checking — `kind delete cluster --name tyk-qa-126b` when done.

Evidence index (`~/playground/tt17018-owner1/evidence/`):

| File | Contains |
|---|---|
| `k130-full-run.log` | the entire kind 1.30 pass, verbatim |
| `k126-p0-run.log` | the second-pass 1.26 control-plane/data-plane matrix, verbatim |
| `tc01-cp-130-*`, `tc01-dp-130-*` | control-plane and MDCB-connected data-plane upgrade legs |
| `operator-130-*`, `portal-130-*` | operator and dev-portal installs, live opt-outs |
| `tc02-gateway-pin-130.txt` | the pinned-gateway admission failure, verbatim |
| `render-diff-summary.txt` | released 5.3.0 → main full render diff, all umbrellas |
| `tc-540-bump-history.txt` | the simulated 5.3.0 → 5.4.0 release-bump upgrade |
| `tc04/render-*.yaml` | every render: baseline, opt-out, all-components, per umbrella |
| `tc09-unittest.log`, `tc09-lint-all.log` | 216/216 and 11/11 |
| `tc09-step3-revert.diff`, `tc09-unittest-reverted.log` | the anti-vacuity revert and its red run |
| `tc09-mutation-sweep.txt` | the 23-site mutation table |
| `tc02-images.txt`, `tc02-image-users.txt`, `tc02-image-arch.txt` | image audit |
| `tc02-step2-*`, `tc02-step3-*` | pinned-old-tag install, upgrade, verbatim kubelet error |
| `tc01-oss-126-*`, `tc01-stack-126-*` | the 1.26 upgrade legs, including `--reuse-values` |
| `tc06-*` | connection-string renders and the live secret checks |
| `tc10-*` | dry-run sweeps, per component and per umbrella |
| `tc11-126-*` | TC-11 evidence on 1.26, including the retagged legacy-dashboard install |
