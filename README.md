# TT-17018 — QA workstreams (2 owners)

Companion to `TT-17018-test-plan.md`. That document is the authority
on *what* and *why*. This directory splits it into **two packets** that two people can own and run
without blocking each other.

| File | For |
|---|---|
| [`00-shared-setup.md`](00-shared-setup.md) | Both owners. ~15 min read. |
| [`owner-1-kind-and-render.md`](owner-1-kind-and-render.md) | Owner 1 — kind & render. ~5 days. |
| [`owner-2-openshift.md`](owner-2-openshift.md) | Owner 2 — OpenShift. ~5 days. |

Each owner file is self-contained: setup steps, every command, and per step a **Validates / Pass /
Evidence** triplet so what sign-off requires is explicit rather than inferred. Neither owner needs
the 818-line master plan open to work.

---

## The split

Drawn on **environment**, because setup cost dominates everything else here. The result:
**Owner 1 never touches OpenShift, Owner 2 never touches kind.** One environment each, no
duplicated setup tax.

| | **Owner 1 — kind & render** | **Owner 2 — OpenShift** |
|---|---|---|
| **Test cases** | TC-04 Steps 1–3, TC-09, TC-10, TC-01, TC-02, TC-06 Steps 1–5, TC-11, TC-12 | TC-03, TC-04 Steps 4–10, TC-05, TC-07, TC-08, TC-06 Step 6 |
| **Clusters** | kind 1.26 + 1.30, local | Dev Sandbox + one admin-capable cluster |
| **Effort** | ~4 days | ~5 days |
| **P0 work** | TC-01, TC-11 (+ TC-02 as a documented outcome) | TC-03, TC-04 |
| **Owns** | the upgrade risk — the largest untested surface on the ticket | gaps #2, #3, #4, #6 — everything CI never installed |
| **Skills** | Helm, kind, `crane`, `yq`, helm-unittest | OpenShift/`oc`, SCC, ArgoCD, private registry |
| **Also owns** | TC-12 customer liaison, the 5.4.0 release note | the Redis-on-OpenShift scope question (§8 Q2) |

**Total ≈ 9 person-days over ~5 calendar days**, after the scope trims below. The master plan's "4–5 working days for one QA
engineer" (§5) excludes environment setup and assumes every install works first time. Treat it as
best case.

### Why two test cases are split down the middle

Neither TC-04 nor TC-06 is a single unit of work, and treating them as one would wreck the balance:

- **TC-04 Steps 1–3 are desk work; Steps 4–10 need a live cluster.** Steps 1–3 *produce* the three
  missing `ci/no-securitycontext-values.yaml` files; Steps 4–10 *consume* them. Kept together, all
  OpenShift work would sit behind one person's morning at a text editor.
- **TC-06 Steps 1–3 and 5 are renders, Step 4 is an upgrade regression, only Step 6 needs a
  cluster.** Step 4 runs fine on kind and belongs with Owner 1's other upgrade work. Without this
  move Owner 2 lands at ~6.5 days and becomes the entire critical path.

---

## Handoffs — both from Owner 1 to Owner 2, both on day 1

Owner 2's TC-04 is **blocked** until these land. They are Owner 1's first task of day 1, time-boxed
to the morning.

| # | What | Why Owner 2 needs it |
|---|---|---|
| 1 | Three `ci/no-securitycontext-values.yaml` files (`tyk-control-plane`, `tyk-stack`, `tyk-data-plane`) | TC-04 Steps 4–10 install with these. They don't exist in the repo yet — only `tyk-oss` has one. |
| 2 | The **gap #9** operator verdict | All umbrellas expose only `tyk-operator.podSecurityContext`, but the template reads `.Values.managerPodSecurityContext`. If confirmed broken, Owner 2 can't opt the operator out through the documented surface and must set the other key directly. |

Soft handoffs, useful but not blocking:

- **Owner 1 → Owner 2:** the per-component image-`USER` table from TC-02 Step 1 (the real non-root
  tag boundary), and the TC-06 secret name/key so Owner 2's live check matches the renders.
- **Owner 2 → Owner 1:** the OpenShift docs gaps for the §6 row 14 doc work, and the
  Redis/PostgreSQL workaround for §8 Q2.

---

## Calendar

| Day | Owner 1 — kind & render | Owner 2 — OpenShift |
|---|---|---|
| **0** | Shared actions below (30 min, together) | Shared actions + **request private registry access** |
| **1 AM** | Setup · **TC-04 Steps 1–3 → hand to Owner 2** · send TC-12 | Kick off the SNO install · provision Sandbox |
| **1 PM** | TC-09 (incl. anti-vacuity check), TC-10 | TC-05 Steps 1–5 (renders, no cluster) · **TC-03 on Sandbox** |
| **2** | TC-01 on kind 1.26 — `tyk-oss`, `tyk-data-plane` | Redis/PostgreSQL on OpenShift (S6) · TC-04 Steps 4–9 on `tyk-control-plane` |
| **3** | TC-01 on kind 1.30 + `tyk-stack` · TC-02 | TC-04 Step 10 (`tyk-stack`, `tyk-data-plane`) · TC-05 Steps 6–7 (real ArgoCD) |
| **4** | TC-11 on kind 1.26 and 1.30 · TC-06 Steps 1–5 | TC-07 (bootstrap executing, self-hosted registry) |
| **5** | Write-up · defects · release note · chase TC-12 | TC-08 · TC-06 Step 6 · write-up · defects |

Owner 2's day 1 is deliberately cluster-free work — the cluster install (~1 hour unattended) and the
Sandbox provisioning run in the background while the TC-05 renders and TC-03 get done.

---

## Day-0 actions — 30 minutes, both owners together

Shared inputs. Without them, several tests produce results that can't be aggregated or trusted.

- [ ] **Pin the SHA.** One person clones `main` and records `git rev-parse HEAD` on TT-17018.
      Both owners test *that* SHA. Master plan §3.8 — `main` has moved since merge `61e5cf1`
      (`462900f`, then reverted by `4e0f1be`). Results against different trees don't aggregate.
- [ ] **Request the Red Hat OpenShift Partner Lab — it's free, and it has lead time.** Purpose-built
      for "testing and certification of containers and operators or **Helm charts**", reservable 1 day
      to 1 month. Tyk ships a certified operator, so eligibility is likely. Confirm two things when
      requesting: it runs **Mon–Fri 08:00–18:00** only, and that you get **cluster-admin**. If there's
      no answer in a day or two, fall through to the next item rather than waiting.
- [ ] **Otherwise, provision Owner 2's cluster: Single Node OpenShift on one x86_64 cloud VM.**
      8 vCPU / 32 GB / 120 GB+, ~$84/week continuous or ~$40/week stopped overnight and at weekends.
      **Neither laptop can host this** — both are 16 GB Apple Silicon, and CRC-on-a-cloud-VM is not a
      workaround because CRC's own docs state it doesn't support nested virtualisation. Details and
      the free local-CRC stopgap: [`owner-2-openshift.md` S4](owner-2-openshift.md#s4--your-admin-capable-cluster--half-a-day-to-a-day).
- [ ] **Resolve licences.** Dashboard licence for TC-01's `tyk-stack` leg, TC-02, TC-04, TC-05,
      TC-07, TC-08; MDCB for TC-06. Check how many **concurrent** dashboard installs it allows —
      both owners may want one on days 2–3. **This is the only genuine long-lead item.**
- [ ] **Send TC-12 on day 1.** It's elapsed-time-bound and the last customer round-trip took roughly
      a month (asked June, replied 20 July). Set the response deadline that triggers the ROSA
      contingency, and note it on the ticket. This is §8 Q5.
- [ ] **Agree the P0 rule now.** Master plan §8 Q3: the change is already on `main`, so if QA finds
      a P0 — revert, or fix forward before the 5.4.0 cut? Decide before you're under pressure on
      day 4. Either owner hitting a P0 escalates the **same day**; do not batch to the write-up.

---

## Sign-off tracker

The master plan's §6 checklist with an owner against every row. Release into Charts 5.4.0 when each
row is green **and** its owner has attached evidence against the day-0 SHA.

| # | Sign-off item | Owner | P0 | Status |
|---|---|---|:--:|:--:|
| 1 | TC-01 passes on k8s 1.26 and 1.30 for `tyk-oss`, `tyk-data-plane`, `tyk-stack`, with and without `--reuse-values` | 1 | ● | ☐ |
| 2 | TC-02 outcome documented, pinned-old-tag decision explicitly made | 1 → team | ● | ☐ |
| 3 | TC-03 reproduced by QA on a real, unprivileged OpenShift cluster | 2 | ● | ☐ |
| 4 | TC-04 all four umbrellas; three values files **authored and TC-04 passing with them**; gap #9 resolved — see note | 1 + 2 | ● | ☐ |
| 5 | TC-05 passes through a real ArgoCD instance, not just `helm template` | 2 | | ☐ |
| 6 | TC-06 incl. the `useSecretName` + literal `connectionString` upgrade regression | 1 + 2 | | ☐ |
| 7 | TC-07 bootstrap verified **executing**, incl. an auth-requiring registry with a negative control | 2 | | ☐ |
| 8 | TC-08 dev portal verified **running** with all three new config paths | 2 | | ☐ |
| 9 | TC-09 green on merged `main`, **with the anti-vacuity revert check done** | 1 | | ☐ |
| 10 | TC-10 zero field leaks under **server-side** dry-run | 1 | | ☐ |
| 11 | TC-11 green on k8s **1.26 and 1.30** (the ends; middle versions only if they disagree) | 1 | ● | ☐ |
| 12 | TC-12 customer confirms on the merged state; remaining patch list agreed in writing | 1 | | ☐ |
| 13 | Upgrade release note reviewed and published in the 5.4.0 changelog | 1 | | ☐ |
| 14 | OpenShift docs cover the `enabled: false` opt-out (and why `{}` doesn't work), the Redis/PostgreSQL caveat, and the per-component image-tag boundary | 1 + 2 | | ☐ |

Rows 4, 6 and 14 are the shared ones — neither owner can close them alone.

> **Row 4 — no PR is required to validate this.** The master plan's §6 row 4 asks for the three
> `ci/no-securitycontext-values.yaml` files to be **merged**. They are *inputs* to TC-04, and
> `helm install -f <path>` behaves identically from a working copy — so the gate is *"authored,
> attached to TT-17018, TC-04 passes with them"*.
>
> Merging wouldn't close the CI gap anyway: CI never runs `ct install` (only `ct lint --all`), and the
> `smoke-tests-no-securitycontext` job hardcodes `./tyk-oss/ci/no-securitycontext-values.yaml`
> against `tyk-oss` alone — so extra files add **no install coverage** without also editing
> `run-tests.yaml`. Both belong in §7 beside §7.4. Gating release sign-off on someone else's code
> review would import a dependency QA doesn't control, on a ticket already flagged for merging before
> QA ran.
>
> **Rows 13 and 14 are release deliverables, not validation** — a changelog entry and docs. They gate
> the release, not the evidence. Do them after the testing, and don't let them displace it.

---

## Already found: three defects in the master plan's own commands

All surfaced before day 1, and all would have produced misleading results wherever the tests ran.
Fixed in the owner packets; flagged here because the Thursday review should see them. **The good news
first: the ticket's central premise was checked and it holds — see defect 2.**

**1 — TC-02 Step 1's image loop names two repositories that don't exist.** It iterates
`tyk-gateway tyk-dashboard tyk-pump tyk-sink portal`, but there is no `tykio/tyk-pump` (it's
`tykio/tyk-pump-docker-pub`) and no `tykio/tyk-sink` (it's `tykio/tyk-mdcb-docker`). As written it
silently reports nothing for pump and MDCB — on the one step whose purpose is proving *every* default
image has a numeric non-root USER. The corrected loop also adds the operator and the three bootstrap
images, which the master plan omitted entirely.

Worse, the loop also targets the wrong **registry**: the gateway and pump are pulled from
**`docker.tyk.io`**, not Docker Hub, so `crane config docker.io/tykio/…` could never have resolved
them. The replacement command reads whatever the chart actually renders, at whatever registry, so it
can't drift.

**2 — the gateway's image USER is not monotonic. Checked against `main`, and the premise holds.**
The change rests on "removing container-level `runAsUser` is safe because default image tags were
bumped". The non-root change was backported into the 5.8.x LTS line at **v5.8.13** but reached
mainline only at **v5.13.0** — so **v5.9.0 through v5.12.0 all still declare `USER 0`**, a trap for
anyone re-pinning tags later.

**✅ Verified 2026-08-20 on `main`: the gateway default is `v5.13.1` → `USER 65532`, in the safe
band.** Dashboard v5.13.1, pump v1.16.0, MDCB v2.12.0, portal v1.18.0, operator v1.4.2 and all three
bootstrap images at v2.2.0 are likewise numeric `65532`. So this is **not** a P0 — but it is a
standing re-pin hazard, and Owner 1 re-confirms it against the pinned SHA as a two-minute desk check
(TC-02 Step 1b).

**3 — two helper images are not numeric, and the audit had never covered them.** Both are init/helper
images TC-02 never looked at:

- **`busybox:1.32`** (gateway `setupDirectories` init container) has **no USER at all**. Safe as
  shipped, because the chart pins `runAsUser: 65532` on that container precisely for this reason —
  but disabling *only* the init container's own `securityContext` makes the template fall back to
  `gateway.containerSecurityContext`, which asserts `runAsNonRoot: true` with no UID. On OpenShift
  the SCC rescues that; on **vanilla Kubernetes it is an admission failure**. The opt-out values
  files must disable **all three** blocks, which is why they're written that way.
- **`curlimages/curl:8.8.0`** (portal `bootstrapJob`) has a **symbolic** USER, `curl_user`. Inert
  today because the bootstrap job renders no securityContext — but TC-08 Step 5 is exactly where
  someone starts setting those fields, so Owner 2 probes it deliberately.

Also confirmed while checking: `tyk-oss/Chart.yaml` on `main` reads **`version: 5.3.0`** against a
fix version of 5.4.0, so §8 Q4 is a real open question; and every Tyk component publishes both amd64
and arm64. One image remains unchecked — `gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0`, the operator
sidecar.

## Open questions for the Thursday review

Master plan §8, with who brings the evidence:

| # | Question | Evidence from |
|---|---|---|
| 1 | Pinned-old-tag upgrades: release note only, or a `semverCompare` guard / `NOTES.txt` warning? Most likely support-ticket generator in 5.4.0. | Owner 1, TC-02 |
| 2 | Scope of "no Kustomize patches" — Tyk components only? Redis/PostgreSQL will still need patches. Needs stating in the AC and docs, and agreeing with the customer. | Owner 2, S6 |
| 3 | The change is already on `main`. If QA finds a P0 — revert, or fix forward before the 5.4.0 cut? | either |
| 4 | `main` reads chart version `5.3.0` while the fix version is Charts 5.4.0. Confirm the release-prep bump is tracked separately. | Owner 1 |
| 5 | TC-12 ownership and the deadline that triggers the ROSA contingency. | Owner 1 |
| 6 | Gap #9 — expose `managerPodSecurityContext` in the umbrella values? Remove or document the dead `podSecurityContext` key? | Owner 1 (verdict) + Owner 2 (impact) |
| 7 | **New** — confirm the scope trims: no PR for row 4, self-hosted registry for row 7, TC-11 at the matrix ends, rows 13–14 as release deliverables. Each is listed under "Deliberately not doing" in the owner packets. | either |

---

## Reporting

Both owners report the same way so results aggregate rather than needing translation on day 5.
Format, defect conventions and the two **known-expected failures**:
[`00-shared-setup.md`](00-shared-setup.md#reporting-results).
