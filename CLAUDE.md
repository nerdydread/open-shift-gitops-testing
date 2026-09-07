# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A **QA planning and evidence repository** for Tyk ticket **TT-17018** — validating that the
`TykTechnologies/tyk-charts` Helm charts deploy on OpenShift with no Kustomize patches, after
container-level `securityContext` fields were made opt-out-able (PR #485, already merged to `main`
before QA sign-off).

There is **no application code here** — no build, no lint, no test suite for the repo itself. The
artefacts are Markdown documents, shell helper scripts, captured evidence files, and Helm values
files. The *subject* under test lives in a separate repo that is cloned to a scratch directory
(`~/playground/tt17018-owner1/tyk-charts` in the Owner 1 run) and never vendored here.

Editing work is therefore documentation work: keeping the plan, the two owner packets, and the
results consistent with each other and with what was actually observed.

## Document hierarchy — who defers to whom

```
TT-17018-test-plan.md      master plan. Authority on WHAT and WHY. 828 lines, §1–§8, TC-01…TC-12.
  README.md                the two-owner split, calendar, §6 sign-off tracker, defects already
                           found IN the master plan's own commands.
  00-shared-setup.md       both owners. Code under test, tooling, the `enabled: false` trap,
                           the privilege gate, Redis/PostgreSQL, reporting format.
    owner-1-kind-and-render.md   Owner 1 packet: kind + render. TC-01, TC-02, TC-04 S1–3,
                                 TC-06 S1–5, TC-09, TC-10, TC-11.
    owner-2-openshift.md         Owner 2 packet: OpenShift. TC-03, TC-04 S4–11, TC-05,
                                 TC-06 S6, TC-07, TC-08.
      owner-1-results/     Owner 1's completed run: README.md verdicts + D-01…D-10 defects,
                           evidence/ (verbatim logs), values-files/, *.sh helpers.
```

The owner packets **deliberately override the master plan** where the plan is wrong (see
README.md "Already found: three defects in the master plan's own commands"). When they conflict,
the packet wins and the divergence is stated explicitly. Do not silently "correct" a packet back
toward the master plan.

Each owner file is self-contained by design — someone running Owner 2's packet should never need
the master plan open. Preserve that when editing: prefer duplicating a needed detail into the
packet over adding a cross-reference.

## Conventions that must be preserved when editing

- **Every test step carries a `**Validates:** / **Pass:** / **Evidence:**` triplet** (some also
  `**Fail → raise a defect:**`). This is what makes sign-off explicit rather than inferred. A new
  step without the triplet is incomplete.
- **Identifiers are load-bearing and cross-referenced:** `TC-NN` test cases, `Step N`, `§N` master-plan
  sections, `§6 row N` sign-off rows, `gap #N` (the nine untested gaps), `D-NN` defects in
  `owner-1-results/README.md`, `S1…S7` setup sections in the owner packets. Renumbering one breaks
  references in three other files — grep before changing any of them.
- **Relative links must resolve inside the repo root** (commit `e2d6675` fixed this once already).
- **Scope trims are documented, not dropped.** Each packet ends with a "Deliberately not doing —
  and why" table so the review accepts the scope knowingly. Removing coverage means adding a row
  there, not deleting a section.
- **Results format** (`00-shared-setup.md` §6): Owner / Test / SHA / Cluster / Command / Output /
  Verdict / Notes. Every OpenShift result must carry `oc whoami` and the namespace UID range —
  a result without proof of unprivileged execution is not evidence.
- Tables and prose are wrapped at ~100 columns. Verdicts are bold (`**PASS**`, `**FAIL**`).

## Domain facts that make the difference between a real result and a false pass

These recur across every document. Getting one wrong invalidates a whole test leg.

- **`securityContext: {enabled: false}`, never `securityContext: {}`.** Helm deep-merges the
  component chart defaults back in, so `{}` is a silent no-op that produces a **false pass**.
  `enabled` is a synthetic chart flag — if it leaks into a rendered manifest, that is the TC-10
  field-leak defect.
- **Security-context key names are irregular across components and must not be normalised:**
  `securityContext` (gateway, dashboard, pump, bootstrap), `podSecurityContext` (MDCB),
  `managerPodSecurityContext` (operator — `tyk-operator.podSecurityContext` is a dead key, gap #9,
  confirmed as D-02), chart-root `securityContext` with no `.devPortal` nesting (dev-portal).
  Container level is `containerSecurityContext` throughout; init containers nest their own blocks.
- **The privilege gate, every OpenShift session.** `oc auth can-i use scc/anyuid` must return `no`.
  A cluster-admin gets `anyuid`, bypasses `restricted-v2`, and every SCC test then passes
  regardless of what the chart does.
- **Redis and PostgreSQL are separate Helm releases, not chart dependencies.** Setting
  `master.podSecurityContext.enabled=false` in *Tyk's* values is a no-op. Bitnami pins UID 1001,
  which `restricted-v2` rejects — so they must be turned off on the Redis/PostgreSQL release itself.
- **Gateway and pump images come from `docker.tyk.io`, not Docker Hub.** The master plan's names
  `tykio/tyk-pump`, `tykio/tyk-sink` and `tykio/tyk-bootstrap` do not exist. Full verified table in
  `00-shared-setup.md` §3b and, regenerated against the tested SHA, in `owner-1-results/README.md`.
- **The gateway image's non-root `USER` is not monotonic** — root on v5.9.0–v5.12.0, non-root on
  v5.8.13+ and v5.13.0+. Any tag re-pin needs re-checking against that band table.
- **Two failures are expected** and must not be filed as new defects: TC-02 Step 3 (pinned-old-tag
  upgrade fails with `CreateContainerConfigError` — the pass criterion is that it matches the
  release note verbatim) and TC-11 Step 6 (second `helm test` run fails with `configmaps already
  exists`, a missing `hook-delete-policy`).

## Working with the evidence pack

`owner-1-results/` is a **completed, immutable-in-spirit record** of a run against
`tyk-charts` @ `39957f3660212154296b6ffc9ab733f822e6809d` on kind v1.26.13 and v1.30.0. Files in
`evidence/` are verbatim captured output. Do not edit them to fix formatting or reconcile a number —
if a figure is wrong, the correction belongs in `owner-1-results/README.md` alongside the original.

Helper scripts (zsh, written for `~/playground/tt17018-owner1`, paths hardcoded to that layout):

```bash
./owner-1-results/run130.sh                       # the whole kind v1.30.0 pass, start to finish
./owner-1-results/run126-p0.sh                    # 1.26 control-plane / data-plane P0 matrix
./owner-1-results/mutation-sweep.sh               # TC-09 Step 3 extended: 23-site anti-vacuity sweep
./owner-1-results/stack-leg.sh <ns> <pg-db> ["--reuse-values"]   # released tyk-stack -> main upgrade
./owner-1-results/gw-api.sh <ns> <release> create|get|proxy|list|health [api-id]
```

`values-files/*.yaml` are the three `ci/no-securitycontext-values.yaml` files authored for TC-04
Step 1 (§6 row 4). They are **inputs** to testing — `helm install -f <path>` behaves identically
from a working copy, so no PR against `tyk-charts` is required to validate them. Their header
comments encode the key irregularities above; keep those comments when editing.

## The subject repo — commands the documents prescribe

These run against a clone of `TykTechnologies/tyk-charts`, not against this repository:

```bash
git clone https://github.com/TykTechnologies/tyk-charts.git && cd tyk-charts
git rev-parse HEAD    # must equal the SHA pinned on TT-17018 — results against different trees don't aggregate
for u in tyk-oss tyk-stack tyk-control-plane tyk-data-plane; do helm dependency update ./$u; done

helm unittest ./components/tyk-gateway ./components/tyk-dashboard ...   # TC-09, expect 216/216
ct lint --all                                                          # TC-09, expect 11/11
helm template t ./tyk-control-plane -f ./tyk-control-plane/ci/no-securitycontext-values.yaml
helm template t ./<umbrella> ... | kubectl apply --dry-run=server -f -  # TC-10 field-leak sweep
```

Tooling the packets pin: helm 3.18.4 (3.18.6 was used and the drift recorded), helm-unittest
v0.7.2, kind, `crane` (image `USER` inspection — handles the `docker.tyk.io` token redirect that
hand-rolled `curl` does not), `yq`, `oc` (Owner 2).

## Status

**All QA testing is complete (2026-09-07). 10 of 14 §6 rows closed.** Both owners tested
`39957f3660212154296b6ffc9ab733f822e6809d`. The four open rows need three decisions and two pieces of
writing — none needs a cluster, a licence, or QA time. `README.md`'s "What's left" section is the
authority on what remains.

`owner-2-results/` mirrors `owner-1-results/`: a `README.md` with verdict summary, defects and
per-test-case detail; `evidence/` (119 verbatim captures, prefixed by test case); and `scripts/`
(the runbooks, which hardcode `~/playground/tt17018-owner2` and read licences from files that are
deliberately not committed).

Defect numbering is continuous across both owners: **D-01…D-10** are Owner 1's, **D-11…D-15** are
Owner 2's. Only **D-01** is a P0 candidate; **D-13** additionally needs a team decision.

## Two shell traps that produced false results on this ticket

Both cost real time and both are recorded in the results packs. Anything scripted against these
charts should assume them:

1. **zsh does not word-split unquoted string variables.** `helm template ./x $FLAGS` passes one
   malformed argument, helm errors, and `2>&1 | grep` then reports a **false PASS** from the error
   text. Use zsh arrays, and make render helpers fail loudly rather than grepping stderr. Owner 1
   filed this as D-07; Owner 2 reproduced it independently.
2. **`--set key[0]=value` is glob-expanded by zsh** (`no matches found`, install silently skipped).
   Quote the whole `--set` argument or `setopt NO_NOMATCH`.

**Anti-vacuity checks are not optional here.** Every "pass = no output" assertion in both packs is
paired with a baseline proving the grep can fire. That pairing is what caught trap 1.
