# Owner 2 — OpenShift

**Effort:** ~5 days · **Clusters:** Red Hat Developer Sandbox + one admin-capable cluster (S4) · **You never touch kind.**
**Test cases:** TC-03, TC-04 Steps 4–11, TC-05, TC-06 Step 6, TC-07, TC-08

Read [`00-shared-setup.md`](00-shared-setup.md) first (~15 min). Master plan for background:
[`TT-17018-test-plan.md`](TT-17018-test-plan.md).

---

## What you own

You own **four of the nine documented coverage gaps** — the entire surface that neither the two
engineering reviews nor CI ever touched:

- **Gap #2 — but narrower than the master plan says.** It claims `tyk-stack` and
  `tyk-control-plane` are "never installed end-to-end anywhere". Checked against `run-tests.yaml`,
  that is **half right**, and the correction changes where your effort goes:
  - **`tyk-control-plane` is not mentioned anywhere in `run-tests.yaml`.** Never installed, never
    linted with values, nothing. This is the genuinely uncovered umbrella — and it's the one that
    carries bootstrap and MDCB. **Do it first.**
  - **`tyk-stack` and `tyk-data-plane` *are* installed** in the `integration-tests` job, with
    `helm test` run against both. So the install path itself has coverage. What they lack is
    **opt-out** coverage — no job installs them with securityContext disabled.

  Net: for `tyk-control-plane` you are proving the install works at all; for `tyk-stack` and
  `tyk-data-plane` you are proving specifically that the *opt-out* path works. The PR added +133
  lines to `tyk-stack/values.yaml` and +124 to `tyk-control-plane/values.yaml`, and control-plane +
  data-plane is the customer's actual topology.
- **Gap #3** — the SCC opt-out has only ever been e2e-installed on `tyk-oss`. **Dashboard,
  dev-portal, MDCB, operator and bootstrap opt-outs have never been installed**, only rendered.
- **Gap #4** — **bootstrap jobs have never actually executed** in any automated test.
  `disableHelmHooks`, `backoffLimit`, `imagePullSecrets`, `preDelete.command` and `rbacAnnotations`
  are render-verified only.
- **Gap #6** — the Dev Portal is installed by **no smoke job at all**.

Engineering-side validation on this ticket is genuinely strong — the customer tested on real ROSA,
Sedky validated on CRC 4.22.1 unprivileged, Leonid ran two reviews plus a live `restricted-v2`
admission probe. **You are not redoing that work.** TC-03 is a 30-minute confirmation run so QA owns
the evidence independently. Everything else is new ground.

### Sign-off gates you hold

| §6 row | Item | Yours |
|---|---|---|
| 3 | TC-03 reproduced on a real, **unprivileged** OpenShift cluster | ✅ sole |
| 4 | TC-04 passes for all four umbrellas | ✅ shared — Owner 1 supplies the values files and the gap #9 verdict. **No PR required** |
| 5 | TC-05 passes through a **real ArgoCD instance**, not just `helm template` | ✅ sole |
| 6 | TC-06 live check | ✅ shared — Owner 1 owns the render steps and the upgrade regression |
| 7 | TC-07 bootstrap verified **executing**, incl. an auth-requiring registry with a negative control | ✅ sole — self-hosted registry is fine (S7) |
| 8 | TC-08 dev portal running with all three new config paths | ✅ sole |
| 12 | **Replaces TC-12** — headline AC proven directly: four umbrellas installed with zero Kustomize patches on Tyk components | ✅ sole (TC-04 Step 11) |
| 14 | OpenShift docs cover the opt-out, the Redis caveat, the tag boundary | ✅ shared — Owner 1 supplies the tag boundary |

### Entry criteria — you are blocked on Owner 1 for two things

1. **The three `ci/no-securitycontext-values.yaml` files** (`tyk-control-plane`, `tyk-stack`,
   `tyk-data-plane`). Due day 1 AM. TC-04 Steps 4–10 cannot start without them.
2. **The gap #9 operator verdict.** All three umbrellas expose only
   `tyk-operator.podSecurityContext`, but `components/tyk-operator/templates/all.yaml:395` reads
   `.Values.managerPodSecurityContext`. If the verdict is "confirmed broken", your control-plane
   install must set `managerPodSecurityContext` directly and you file a defect against the umbrella
   values.

**Day 1 is not blocked** — spend it on setup plus the render-only prefixes below, which need no
cluster at all.

---

## Setup

### S1 — Code under test

```bash
git clone https://github.com/TykTechnologies/tyk-charts.git && cd tyk-charts
git rev-parse HEAD    # must equal the SHA pinned on TT-17018
for u in tyk-oss tyk-stack tyk-control-plane tyk-data-plane; do helm dependency update ./$u; done
```
**Validates:** that you are testing the shipping artefact. `main` has moved since merge `61e5cf1`.
**Pass:** SHA matches the pinned one. If not, `git checkout <pinned-sha>` before continuing.
**Evidence:** the SHA, on every result you file.

### S2 — Tooling

```bash
helm version          # 3.18.4
oc version
yq --version
```

### S3 — Developer Sandbox (TC-03 only) · ~1 hour

**Step 1 — Provision.** <https://developers.redhat.com/developer-sandbox> → "Start your sandbox for
free". You get an unprivileged project automatically.

The sandbox is active for **30 days** and pods are **auto-deleted after 12 consecutive hours**, so
**plan TC-03 as a single short session.** Don't provision it on day 1 and run the test on day 4.

**Step 2 — Log in from the CLI.** Console → top-right user menu → "Copy login command" → Display
Token → run the `oc login --token=… --server=…` locally. Tokens are short-lived; re-copying when
they expire is normal, not a fault.

**Step 3 — Run the privilege gate** (S5). On the Sandbox it should pass by construction — that is
precisely why TC-03 runs here rather than on your admin cluster.

### S4 — Your admin-capable cluster · ~half a day to a day

You need one cluster that gives you **all three** of: real `restricted-v2` enforcement,
`cluster-admin` (for the GitOps operator and the tyk-operator CRDs), and an **unprivileged user** to
test as. The Developer Sandbox gives the first and third but not the second, which is why this
second cluster exists at all.

> **Why not CRC on your laptop, and why not CRC on a cloud VM.** The original plan said CRC
> (OpenShift Local — Red Hat's single-node OpenShift in a local VM). Neither laptop can spare the
> memory, and renting a VM for it does **not** work around that: `crc.dev/docs/installing` states
> **"CRC does not support nested virtualization"**, and CRC runs OpenShift inside its own hypervisor.
> There's an open bug of exactly this failing on GCE (crc-org/crc#4638) and a Red Hat KB confirming
> the same under VMware. "Might work, unsupported" is the wrong foundation for evidence that gates a
> release — so use one of the options below instead.

**Step 1 — Ask for the Red Hat OpenShift Partner Lab. Do this on day 0; it is free.**

Available to Red Hat technology partners at no charge, explicitly intended for *"final development,
testing, and certification of containers and operators or **Helm charts**"* — which is precisely this
work. Reservable from 1 day to 1 month. Tyk ships a certified operator, so eligibility is likely.
Request it through a Red Hat sponsor or `partner-lab@redhat.com`.

**Validates:** nothing in the chart — but it is the only option that costs nothing *and* gives real
cluster-admin.
**Pass:** a cluster reserved for your test week.
**Two things to confirm when you request it:** the environment runs **Mon–Fri 08:00–18:00** in your
chosen timezone (so no overnight `--wait` runs), and confirm you get **cluster-admin**, which the
public docs don't state.
**Evidence:** the reservation and the confirmed admin level. **Lead time is the risk** — if there's
no answer within a day or two, fall through to Step 2 rather than waiting.

**Step 2 — Default path: Single Node OpenShift on one cloud VM.**

SNO is a supported install target on AWS, GCP and Azure IPI (`platform=aws|gcp|azure`) — no nested
virtualisation involved, real cluster-admin, real OLM with the Red Hat operator catalogues, so the
**GitOps operator path in TC-05 survives intact**.

- **Architecture: x86_64.** Not arm64 — match the customer's ROSA. (Tyk does publish arm64 for every
  component, so arm64 would work, but there's no reason to introduce a variable.)
- **Size: 8 vCPU / 32 GB / 120 GB+.** The docs' 8 vCPU / 16 GB floor is for SNO *itself*, before four
  umbrellas plus Redis, PostgreSQL and ArgoCD.
- **Licence:** free via the 60-day OpenShift trial, which explicitly includes full cluster-admin. Or
  use **OKD** — its `restricted-v2` definition is word-for-word the OpenShift one, making it a
  faithful stand-in for everything in this packet.
- **Cost:** roughly $84/week running continuously, or ~$40/week if you stop it overnight and at
  weekends (estimates). **Stopping is possible precisely because this is self-hosted** — you cannot
  pause a managed ROSA/ARO cluster.

**Validates:** nothing functional — but under-sizing produces `Pending` pods that look exactly like
chart bugs and aren't.
**Pass:** install completes; `oc get nodes` reports the single node `Ready`; `oc get clusterversion`
shows the cluster available.
**Evidence:** node size, `oc version`, and `oc get clusterversion`, recorded once. If you later file
a `Pending`-pod defect, this is what proves it wasn't resource starvation.
**The advantage over a laptop:** if pods do go `Pending`, resize the VM. On a laptop that was a dead
end; here it's a five-minute stop/change-type/start.

**Step 3 — Free stopgap while Step 1 or 2 is being arranged: local CRC, correctly sized.**

CRC's *real* documented minimum is **4 physical cores / 10.5 GB free RAM / 35 GB disk** — the
8-core/24 GB figure was for holding the entire stack at once, not the floor. A 16 GB Apple Silicon
Mac clears the real minimum, and every Tyk component publishes `linux/arm64` (verified: gateway,
dashboard, pump, MDCB, portal, operator, all three bootstrap images).

So you can start **TC-03** and **TC-04 one umbrella at a time** locally at zero cost:
```bash
crc setup
crc config set memory 11264      # MB — just above the 10.5 GB minimum
crc config set cpus 4
crc config set disk-size 60      # GB
crc start
```
**Use for:** TC-03, and a single umbrella per session with `helm uninstall` between.
**Do not use for:** TC-05 (ArgoCD plus a full stack will not fit) or any multi-umbrella comparison.
⚠️ **If Redis or PostgreSQL fails to pull or start here, suspect arm64 before suspecting the chart** —
bitnami's arm64 coverage was not verified, and it is the first place to look.

**Step 4 — Install the OpenShift GitOps operator as cluster-admin** (needed for TC-05).
```bash
# log in as your cluster-admin user for whichever cluster you provisioned
oc apply -f - <<'YAML'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata: {name: openshift-gitops-operator, namespace: openshift-operators}
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
YAML
oc get csv -n openshift-operators -w   # wait for Succeeded
```
**Validates:** nothing in the chart. This is the **only** step that legitimately needs cluster-admin —
which is exactly why the Sandbox cannot run TC-05.
**Pass:** CSV reaches `Succeeded`.
**Evidence:** the `oc get csv` output. Record it — TC-05 Step 6's claim to be "a real ArgoCD instance"
rests on this operator actually being installed.
**Fallback, agreed in advance:** if the catalogue is unavailable on your cluster, install ArgoCD from
its own Helm chart or plain manifests instead. TC-05 still proves what it's there to prove — sync-wave
ordering, null-key rejection, hook-free bootstrap. **Record the downgrade as a documented delta at
sign-off**, since the customer runs the operator.

### S4b — Create the unprivileged test user ⚠️ new, and load-bearing

CRC shipped a built-in `developer` user. **SNO, OKD and the Partner Lab do not** — you must create
one, and `oc login -u developer` appears throughout this packet.

As cluster-admin, add an htpasswd identity provider:
```bash
htpasswd -c -B -b users.htpasswd developer 'developer'
oc create secret generic htpass-secret --from-file=htpasswd=users.htpasswd -n openshift-config
oc apply -f - <<'YAML'
apiVersion: config.openshift.io/v1
kind: OAuth
metadata: {name: cluster}
spec:
  identityProviders:
  - name: htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData: {name: htpass-secret}
YAML
oc get pods -n openshift-authentication -w   # wait for the operator to roll out the new config
```

Then switch to that user and **stay there**:
```bash
oc login -u developer -p developer <your-api-url>
oc new-project tyk-qa
```

**Validates:** that you have a genuinely unprivileged identity. Every SCC result in this packet is
void without one.
**Pass:** `oc login -u developer` succeeds and the S5 privilege gate returns three `no` results.
**Evidence:** the gate output (S5).
⚠️ **Every subsequent chart test must run as `developer`.** Testing as `kubeadmin` or
`system:admin` grants `anyuid` and **everything passes falsely.** Rollout of the OAuth config takes
a minute or two — if `oc login` rejects the new user, wait for the authentication pods rather than
assuming you mistyped.

**Step 5 — Run the privilege gate** (S5). This is the step that catches the mistake above.

### S5 — The privilege gate ⚠️ run at the start of every session

Not once at setup. **Every session**, and again after any break where you may have re-logged in.

```bash
oc whoami
oc auth can-i use scc/anyuid        # MUST be: no
oc auth can-i use scc/privileged    # MUST be: no
oc auth can-i '*' '*'               # MUST be: no  (not cluster-admin)
oc get ns "$(oc project -q)" -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}{"\n"}'
# e.g. 1004340000/10000  ->  allowed UIDs 1004340000-1004349999
```

**Validates:** that the SCC results you are about to collect mean anything at all. Skipping this is
the single most common way to produce a worthless pass on this ticket.
**Pass:** three `no` results, plus a recorded UID range.
**If `can-i use scc/anyuid` returns `yes`, STOP.** A cluster-admin bypasses `restricted-v2` entirely
and every SCC test will pass regardless of what the chart does. Re-login as `developer`.

**The admin-cluster trap:** unlike the Sandbox, cluster-admin is right there and trivially easy to fall back
into. Assume you are privileged until this gate says otherwise.

**Evidence:** `oc whoami` and the UID range on **every** OpenShift result you file. A result without
proof you were unprivileged is not evidence.

### S6 — Redis and PostgreSQL ⚠️ this will block you, and it isn't in the master plan

Gap #8 notes Redis and PostgreSQL are **separate releases**, not chart dependencies. The master
plan states the consequence for the acceptance criterion but never tells you how to get them running
— and on OpenShift this is a hard blocker, not an omission:

**`bitnami/redis` pins `fsGroup`/`runAsUser`/`runAsGroup` to `1001`, which is outside your namespace
UID range. Redis is therefore rejected by `restricted-v2` before you ever exercise a Tyk chart.**

And note: setting `master.podSecurityContext.enabled=false` in **Tyk's** values is a **no-op** —
it's a different Helm release. You must disable the contexts on the Redis release itself:

```bash
helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n tyk-qa \
  --set auth.enabled=false --set architecture=standalone \
  --set master.podSecurityContext.enabled=false \
  --set master.containerSecurityContext.enabled=false --wait

# tyk-stack / tyk-control-plane also need PostgreSQL, same treatment:
helm install postgres oci://registry-1.docker.io/bitnamicharts/postgresql -n tyk-qa \
  --set auth.postgresPassword=topsecretpassword --set auth.database=tyk_analytics \
  --set primary.podSecurityContext.enabled=false \
  --set primary.containerSecurityContext.enabled=false --wait
```

**Budget half a day** and **write down exactly what you had to do.** That record is the evidence for
two open items you must bring to the Thursday review:

- **§8 Q2** — does "deploys on OpenShift without Kustomize patches" mean **Tyk components only**?
  Whatever you needed here is a patch the customer will also need. This is not a chart defect; it is
  a **scope question on the acceptance criterion**, and it needs stating in the AC, in the docs, and
  agreed with the customer.
- **§7.7** — document the Redis/PostgreSQL OpenShift story as a follow-up.

### S7 — Prerequisites

- **Licences** — dashboard (TC-04, TC-05, TC-07, TC-08) and MDCB (TC-06 Step 6). Check with Owner 1
  how many concurrent dashboard installs the licence allows; you may both want one on day 2–3.
  **This is the only genuine long-lead item.**

- **A private registry** for TC-07 Step 2 — but **you do not need corporate ECR/GCR/ACR access.**
  What the test needs is *a registry that requires authentication*, so that installing without the
  pull secret fails and with it succeeds. Run one yourself in ten minutes:

  ```bash
  htpasswd -cBb reg.htpasswd tester 'testpw'
  oc create secret generic reg-auth --from-file=htpasswd=reg.htpasswd -n tyk-qa
  oc new-app --name=registry --image=registry:2 -n tyk-qa \
    -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=Registry \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd
  # mount reg-auth at /auth, expose a Route, then push the bootstrap image into it:
  #   skopeo copy docker://tykio/tyk-k8s-bootstrap-pre-install:v2.2.0 docker://<route>/bootstrap:v2.2.0
  #   oc create secret docker-registry regcred --docker-server=<route> \
  #     --docker-username=tester --docker-password=testpw
  ```
  A self-hosted `registry:2` with htpasswd satisfies the acceptance criterion as well as a cloud
  registry — the chart cannot tell the difference, and what's actually being proven is the negative
  control (`ImagePullBackOff` without the secret, success with it). If corporate access happens to be
  easy, use it; **don't let an access request become the critical path.**

---

## Day 1 — Setup, plus everything that needs no cluster

While the cluster installs — the SNO IPI install takes roughly an hour unattended, and the Partner
Lab request may still be in flight — do the render-only work. All of it is `helm template` against
your local clone, so none of it waits on S4.

### TC-05 Steps 1–5 · GitOps render verification

These five steps need no cluster. Steps 6–7 (the real ArgoCD deployment) come on day 3.

**Step 1 — Render with hooks disabled and sweep for null keys.**
```bash
helm template t ./tyk-control-plane --set tyk-bootstrap.bootstrap.disableHelmHooks=true \
  | grep -nE ':[[:space:]]*null[[:space:]]*$'
```
**Validates:** the exact defect the customer reported — `annotations: null` / `labels: null` on the
bootstrap pod templates — plus the three neighbouring resources Leonid found afterwards (the
bootstrap ServiceAccount, Role and RoleBinding).
**Pass:** no output. **ArgoCD rejects null annotations/labels outright**, so a single null key breaks
the flagship use case.
**Evidence:** the empty output, per umbrella (run it for all four).

**Step 2 — Confirm hook annotations are actually gone.**
```bash
helm template t ./tyk-control-plane --set tyk-bootstrap.bootstrap.disableHelmHooks=true \
  | grep -n 'helm.sh/hook'
```
**Validates:** the feature's core purpose — ArgoCD does not execute Helm hooks, so hook-annotated
resources simply never run.
**Pass:** no output.
**Evidence:** the empty output.

**Step 3 — Confirm the pre-delete Job is not rendered at all.**
```bash
helm template t ./tyk-control-plane --set tyk-bootstrap.bootstrap.disableHelmHooks=true \
  | grep -n 'pre-delete'
```
**Validates:** a deliberate design decision, not an oversight. With hooks off, the pre-delete Job
would otherwise render as a **normal install-time Job** and run its cleanup at sync time — deleting
the operator secret and bricking the install.
**Pass:** no output. **Also check the docs** no longer suggest re-enabling it via an ArgoCD hook
annotation — that advice is unreachable, because the whole template is gated off before any
annotation is evaluated. If the docs still say it, raise a docs defect.
**Evidence:** the empty output plus your docs finding.

**Step 4 — Verify annotation quoting.**
```bash
helm template t ./tyk-control-plane \
  --set tyk-bootstrap.bootstrap.rbacAnnotations."argocd\.argoproj\.io/sync-wave"=-1 \
  --set tyk-bootstrap.bootstrap.jobs.preInstall.annotations."argocd\.argoproj\.io/sync-wave"=-1 \
  | grep -n 'sync-wave'
```
**Validates:** `annotations` is `map[string]string`; an unquoted `-1` renders as an **integer** and
the API server rejects the object with `cannot unmarshal number into … type string`. This broke the
flagship ArgoCD use case, and was fixed at 6 loop sites plus 3 `podLabels` sites.
**Pass:** every value renders **quoted** — `"-1"`, not `-1`.
**Evidence:** the rendered lines, showing the quotes.

**Step 5 — Confirm the API server accepts it.**
```bash
helm template t ./tyk-control-plane --set tyk-bootstrap.bootstrap.disableHelmHooks=true \
  --set tyk-bootstrap.bootstrap.rbacAnnotations."argocd\.argoproj\.io/sync-wave"=-1 \
  | oc apply --dry-run=server -f -
```
**Validates:** that the quoting holds against a **real API server**, not just visually in the render.
**Pass:** no `cannot unmarshal number` error.
**Evidence:** the dry-run output.
⚠️ Needs `--dry-run=server`. Client-side dry-run skips strict decoding and passes regardless.

### TC-03 · SCC admission probe on real OpenShift · **P0** (confirmation run) · ~30 min · **Sandbox**

**What this validates overall:** that the default chart context is genuinely **rejected** by
`restricted-v2`, and the opt-out is genuinely **admitted**. Already proven twice (Leonid on the Dev
Sandbox, Sedky on CRC 4.22.1, two clusters with different UID ranges). QA reproduces it once to own
the evidence independently.

Run this on the **Sandbox**, in one session — its best property is that you *cannot* be privileged,
which makes it the most trustworthy evidence source for the one test where accidentally holding
`anyuid` silently invalidates the result.

**Step 1 — Run the privilege gate** (S5) and record the namespace UID range.
**Validates:** that this whole test case is meaningful. Skipping it is the single most common way to
produce a worthless pass.
**Pass:** all three `can-i` checks return `no`, and the UID range annotation is present and recorded.
**Evidence:** the gate output and the UID range. §6 row 3 says "real, unprivileged" — this output is
what proves the second word.

**Step 2 — Probe the DEFAULT chart context. Must be REJECTED.**
```bash
NS=$(oc project -q)
cat <<'YAML' | oc apply -n "$NS" --dry-run=server -f -
apiVersion: v1
kind: Pod
metadata: {name: scc-probe-default}
spec:
  securityContext: {fsGroup: 2000, runAsNonRoot: true}
  initContainers: [{name: init, image: busybox:1.36, command: ["true"], securityContext: {runAsUser: 65532, runAsNonRoot: true}}]
  containers:     [{name: main, image: busybox:1.36, command: ["sleep","1"]}]
YAML
```
**Validates:** that the chart's stock render is incompatible with `restricted-v2` for **two
independent reasons**. This is the problem statement of the entire ticket.
**Pass:** rejected citing **both** `fsGroup: Invalid value: [2000]: 2000 is not an allowed group`
**and** `initContainers[0].runAsUser: Invalid value: 65532: must be in the ranges: [<your range>]`.
**Evidence:** the verbatim rejection message.
**Note:** a **bare Pod** is required. SCC is evaluated at **Pod admission** — rendering or applying
a Deployment proves nothing, because the Deployment is admitted and only its Pods are rejected.

**Step 3 — Isolate each cause.** Apply the same Pod twice more: once with only `fsGroup: 2000`, once
with only the init `runAsUser: 65532`.
**Validates:** that both fields fail **independently**, so the fix has to address both. This confirms
the diagnosis rather than assuming it — a single combined rejection could have had one cause.
**Pass:** each is rejected on its own, citing **only its own field**.
**Evidence:** both rejection messages.

**Step 4 — Probe the OPT-OUT context. Must be ADMITTED.**
```bash
cat <<'YAML' | oc apply -n "$NS" -f -
apiVersion: v1
kind: Pod
metadata: {name: scc-probe-optout}
spec:
  containers: [{name: main, image: busybox:1.36, command: ["sleep","30"]}]
YAML
oc get pod scc-probe-optout -n "$NS" \
  -o jsonpath='scc={.metadata.annotations.openshift\.io/scc} fsGroup={.spec.securityContext.fsGroup}{"\n"}'
oc delete pod scc-probe-optout -n "$NS"
```
**Validates:** that omitting the block entirely — which is what `securityContext.enabled: false`
produces — lets the SCC do its job.
**Pass:** pod admitted, `scc=restricted-v2`, and OpenShift has **injected** an `fsGroup` inside your
namespace range from Step 1. Pod reaches `Running`.
**Evidence:** the jsonpath output, with the injected `fsGroup` shown to fall inside the recorded
range. **This is the end-to-end proof: rejected default → admitted opt-out → SCC fills a valid
UID/GID.** §6 row 3 is satisfied by this one output plus the Step 1 gate.

---

## Days 2–3 — TC-04: full install with the opt-out, per umbrella · **P0** · ~1.5 days

☑ Privilege gate (S5) before you start. ☑ Redis/PostgreSQL admitted (S6).

**What this validates overall:** that the opt-out works **for real**, on the components that have
only ever been rendered — dashboard, dev-portal, MDCB, operator and bootstrap. Gap #3, the largest
single hole in the coverage.

Owner 1 supplies the values files (Steps 1–3 of the master plan's TC-04). You run Steps 4–10.

⚠️ Owner 1's files use `enabled: false`, never `securityContext: {}`. If you hand-edit them, keep
that: Helm deep-merges the component defaults back in, so `{}` is a silent no-op producing a **false
pass**. If an install passes unexpectedly, check this first.

**Step 4 — Install each umbrella on your admin cluster as `developer`.**
```bash
oc project tyk-qa
helm install tyk ./tyk-control-plane -n tyk-qa --wait --timeout 15m \
  -f ./tyk-control-plane/ci/no-securitycontext-values.yaml
```
**Validates:** the actual acceptance criterion — charts deploy on OpenShift **without Kustomize
patches**.
**Pass:** `helm install` completes; no pod stuck `Pending` or in `CreateContainerConfigError`.
**Evidence:** `oc get pods -n tyk-qa` and the `helm install` output. If a pod is `Pending`, check it
against your S4 Step 2 sizing before filing anything.
**If gap #9 was confirmed:** add `--set tyk-operator.managerPodSecurityContext.enabled=false`, and
note in your evidence that the **documented** umbrella key did not work.

**Step 5 — Confirm every pod is genuinely under `restricted-v2`.**
```bash
oc get pods -n tyk-qa -o custom-columns=\
'NAME:.metadata.name,SCC:.metadata.annotations.openshift\.io/scc,UID:.spec.securityContext.fsGroup'
```
**Validates:** that the **SCC assigned** the context rather than the chart pinning it — the entire
point of the change.
**Pass:** every pod reads `restricted-v2`, and every injected `fsGroup` falls inside the namespace
UID range from S5.
**Fail:** any pod on `anyuid` means **you are privileged and the whole result is void** — go back to
S5 and re-run from Step 4.
**Evidence:** the full table, alongside the recorded UID range.

**Step 6 — Check for SCC denials in events.**
```bash
oc get events -n tyk-qa --field-selector reason=FailedCreate
oc get events -n tyk-qa | grep -i 'forbidden\|scc\|securityContext'
```
**Validates:** denials that **don't surface as pod failures**. A ReplicaSet can retry silently while
the Deployment merely looks slow — Step 4 passing does not rule this out.
**Pass:** no output.
**Evidence:** the empty output.

**Step 7 — Confirm bootstrap jobs completed, not just rendered.**
```bash
oc get jobs -n tyk-qa
oc logs -n tyk-qa job/bootstrap-post-install-tyk-tyk-bootstrap
```
**Validates:** gap #4 — bootstrap belongs to `tyk-stack`/`tyk-control-plane`, which CI never
installs, so **bootstrap has never actually run in any automated test**.
**Pass:** jobs show `Completions 1/1`; logs show **real bootstrap work**, not an early exit.
**Evidence:** the job status and the log tail. "Completed" with an empty log is a fail — check that
it did something.

**Step 8 — Sweep live objects for null keys.**
```bash
oc get all,sa,role,rolebinding,cm,secret -n tyk-qa -o yaml \
  | grep -nE ':[[:space:]]*null[[:space:]]*$'
```
**Validates:** the customer's original reported bug, verified against **live API objects** rather
than rendered YAML — the API server can normalise things `helm template` won't show, so Owner 1's
render sweep and TC-05 Step 1 do not substitute for this.
**Pass:** no output.
**Evidence:** the empty output.

**Step 9 — Functional smoke.** Dashboard loads; gateway serves a request against a created API;
portal starts and reaches Ready.
**Validates:** that "admitted by the SCC" also means "actually works". A pod can be admitted with an
SCC-assigned UID and still **fail to write to its volumes** — admission and function are different
claims.
**Pass:** all three.
**Evidence:** the dashboard HTTP response, the proxied API response, portal pod Ready.

**Step 10 — Repeat Steps 4–9 for `tyk-stack` and `tyk-data-plane`** (and `tyk-oss` for completeness,
which has the pre-existing values file and is already covered by the
`smoke-tests-no-securitycontext` CI job — so it's the lowest-value of the four).

**Order matters here.** Per the corrected gap #2 above: `tyk-control-plane` first (Steps 4–9, no CI
coverage of any kind), then `tyk-stack` and `tyk-data-plane` where the install path is already
covered by `integration-tests` and what's new is the **opt-out** path, then `tyk-oss` last if time
allows. If you run out of week, dropping `tyk-oss` costs least.

**Step 11 — Prove the headline acceptance criterion yourself. This replaces TC-12.**

The master plan delegated this to the customer: send them the chart, ask how many of their 24
Kustomize patches remain. **That's removed** — nothing in this pass depends on the customer. You
produce the evidence, and it's better evidence, because it comes with commands and output rather
than a number in an email.

The AC is *"deploys on OpenShift without Kustomize patches."* The customer's patch categories are on
the ticket, so check each one against the install you just did:

| Patch the customer needed | Still needed? | How you know |
|---|---|---|
| `fsGroup` patch (removing the pinned `fsGroup: 2000`) | | Step 5 — every pod shows an **SCC-injected** `fsGroup` inside the namespace range, with none pinned by the chart |
| Init-container UID patch (removing `runAsUser: 65532`) | | Step 2's render shows no `runAsUser` anywhere; Step 4 admitted the pods |
| `op: remove` workaround for null `labels`/`annotations` | | Step 8 — zero null keys on **live API objects**, and TC-05 Step 1 on the render |
| Anything else you needed to make it install | | Your own notes — **this is the important row** |

**Validates:** the ticket's headline AC, measured rather than asserted, and owned by QA.
**Pass:** all four umbrellas installed with **zero Kustomize patches against Tyk components**, and
the first three rows above answered "no longer needed" with evidence.
**Evidence:** the completed table, plus an explicit list of everything you *did* have to patch or
work around. Expect that list to contain **Redis and PostgreSQL** (S6) and nothing else — that's
gap #8, and it feeds §8 Q2.
**Fail:** any Tyk component needing a Kustomize patch to install. That's the AC not being met, and
it's a P0.

⚠️ **State the limit of this evidence.** You are on a single-node cluster, so this proves the chart
needs no patches on OpenShift — it does **not** prove anything about the customer's multi-AZ ROSA or
their specific ArgoCD/Kustomize pipeline. Say so in your write-up; see the residual-risk note in
[`README.md`](README.md#residual-risk-accepted-knowingly).
**Validates:** gap #2 — two of the four umbrellas have **never been installed anywhere**, and
control-plane + data-plane is the customer's actual topology.
**Pass:** every Step 4–9 criterion holds for each umbrella independently. §6 row 4 names **all
four** — a pass on `tyk-control-plane` alone does not satisfy it, and a dropped umbrella is a
residual risk the sign-off meeting must accept explicitly rather than a silent omission.
**Evidence:** a per-umbrella result grid covering Steps 4–9. That grid *is* §6 row 4.
**Note:** `tyk-control-plane` has no `tests:` block (no helm-test template), unlike the other three —
don't file that as a missing-coverage defect.

---

## Day 3 — TC-05 Steps 6–7: the real ArgoCD path · P1

☑ Privilege gate (S5). Steps 1–5 were done on day 1.

**Step 6 — Deploy through the real ArgoCD instance.**

Create an ArgoCD Application pointing at the chart with `disableHelmHooks: true` and sync-wave
annotations, then sync.

**Validates:** everything from Steps 1–5 in combination, **plus ordering** — which render checks
structurally cannot prove. Nothing in a `helm template` shows that bootstrap actually runs *before*
the components that depend on it once sync waves replace Helm hooks.
**Pass:** Application reports `Synced` / `Healthy`; bootstrap completes **before** dependent pods
start; **zero manual Kustomize patches required** (Tyk components — Redis/PostgreSQL per S6 are the
known, separate exception).
**Evidence:** the Application status, the sync-wave ordering from the ArgoCD event timeline, and an
explicit statement of any patch you needed. §6 row 5 says "a real ArgoCD instance, not just
`helm template`" — Steps 1–5 alone do not satisfy it.

**Step 7 — Delete the Application and observe cleanup.**
**Validates:** the documented **consequence** of disabling hooks — no pre-delete Job exists, so
cleanup becomes the user's responsibility. This is intended behaviour that must match the docs, not
a bug to fix.
**Pass:** behaviour matches the docs; no cleanup Job fires at install/sync time; no orphaned
bootstrap resources beyond what's documented.
**Evidence:** what remained after deletion, checked against the documented list. A mismatch is a
docs defect.

---

## Day 4 — TC-07: bootstrap job configurability, executed not rendered · P1 · ~1 day

☑ Privilege gate (S5).

**What this validates overall:** gap #4 — five new bootstrap settings that have **never actually run
anywhere**. Install `tyk-control-plane` and exercise each in turn.

**Step 1 — `backoffLimit`.** Set `tyk-bootstrap.bootstrap.jobs.preInstall.backoffLimit=0`, then
`=3`, forcing a job failure each time (e.g. point at an unreachable dashboard).
**Validates:** that the value is honoured. It was previously **hardcoded to `1`**, and ArgoCD users
need `0` to avoid retry storms.
**Pass:** `oc get job -o jsonpath='{.spec.backoffLimit}'` matches; with `0` the job does **not**
retry; with `3` it retries **exactly three times**.
**Evidence:** the jsonpath value and the observed retry count for both settings. Reading the field
back is not enough — you must observe the retry behaviour.

**Step 2 — `imagePullSecrets` against an auth-requiring registry.** Push the bootstrap image to the
registry you stood up in S7, point the chart at it, install **without** the pull secret first, then
**with** it.
**Validates:** an **explicit acceptance criterion that has never been tested** (gap #7). Installing
only the working case proves nothing — you need the negative control to know the secret is what's
doing the work.
**Pass:** without the secret → `ImagePullBackOff`; with it → the job pulls and completes.
**Evidence:** both pod states, plus which registry you used.
**A self-hosted `registry:2` is sufficient** — the chart cannot distinguish it from ECR/GCR/ACR, and
what's being proven is that `imagePullSecrets` is wired through. Don't wait on a cloud-registry
access request for this.

**Step 3 — `preDelete.command` override.**
```bash
helm upgrade tyk ./tyk-control-plane -n tyk-qa \
  --set-json 'tyk-bootstrap.bootstrap.jobs.preDelete.command=["/bin/sh","-c","echo no-op"]'
helm uninstall tyk -n tyk-qa
```
**Validates:** the GitOps escape hatch — users who don't want Tyk deleting resources when ArgoCD
removes the app.
**Pass:** the override runs on uninstall; Tyk resources are **not** deleted.
**Evidence:** the pre-delete job log showing `no-op`, plus proof the resources survived.

**Step 4 — `rbacAnnotations`.** Set sync-wave annotations and inspect the live objects.
```bash
oc get sa,role,rolebinding -n tyk-qa -o yaml | grep -B2 -A2 sync-wave
```
**Validates:** that annotations reach **all three** RBAC resources. The ServiceAccount, Role and
RoleBinding were the exact three that rendered `annotations: null` in Leonid's first review — so
checking one is not checking the fix.
**Pass:** present on all three, **quoted**, and accepted by the API server.
**Evidence:** all three objects' annotation blocks.

**Step 5 — `disableHelmHooks` on a live install.** Install with it `true`.
**Validates:** combination behaviour against live cluster objects — hooks off, jobs still complete,
no null keys, pre-delete absent. TC-05 Steps 1–3 proved this in the render; this proves it in the
API.
**Pass:** as TC-05 Steps 1–3, but verified against live objects.
**Evidence:** the live-object equivalents of those three checks.

---

## Day 5 — TC-08 and TC-06 Step 6

☑ Privilege gate (S5).

### TC-08 · Dev Portal configurability · P1 · ~half a day

**What this validates overall:** gap #6 — the portal has **null-key unit tests only** and is
installed by **no smoke job**.

**Step 1 — `extraEnvs` with `valueFrom`.** Set both a `secretKeyRef` and a `configMapKeyRef`.
**Validates:** the rendering change from a plain `value:` field to `tplvalues.render`.
**Pass:** both render correctly, **and** `oc exec <portal-pod> -- env` shows the resolved values at
runtime.
**Evidence:** the render plus the `env` output. Render alone doesn't prove resolution.

**Step 2 — `extraEnvs` with plain `value:` still works.**
**Validates:** backwards compatibility. The rendering change to `tplvalues.render` is exactly where
a regression would hide.
**Pass:** existing-style entries render unchanged.
**Evidence:** the rendered env block.

**Step 3 — `storage.s3.secretRef` with custom key names.** Set `secretRef.name`, `accessKeyIdKey`,
`secretAccessKeyKey`.
**Validates:** the Crossplane case — externally-managed secrets whose key names aren't the chart
defaults (`DevPortalAwsAccessKeyId` / `DevPortalAwsSecretAccessKey`).
**Pass:** the custom keys are used, **and** `secretRef` takes precedence over `useSecretName`.
**Evidence:** the rendered secret references, showing precedence.

**Step 4 — Fallback chain with `secretRef.name` empty.**
**Validates:** that existing users who never set `secretRef` are unaffected — the documented
fallback to `useSecretName`.
**Pass:** falls back cleanly; no null keys, no empty `secretKeyRef`.
**Evidence:** the rendered references.

**Step 5 — `bootstrapJob` configuration.** Override the image (previously **hardcoded**
`curlimages/curl:8.8.0`), set `imagePullSecrets`, set `securityContext.enabled: false`.
**Validates:** the hardcoded image **blocked air-gapped and private-registry users entirely** —
this is a real customer-facing limitation, not a nicety.
**Pass:** the job runs on OpenShift under `restricted-v2` with the overridden image.
**Evidence:** the job completing, plus the SCC annotation on its pod.

⚠️ **Specific thing to probe here, from Owner 1's image audit.** `curlimages/curl:8.8.0` declares a
**symbolic** USER — `curl_user`, not a number. Right now that's harmless: `bootstrapJob.securityContext`
and `.containerSecurityContext` both render **empty** by default (`enabled: true` with no fields), so
nothing asserts `runAsNonRoot` over it.

But this step is where that changes. **Add `runAsNonRoot: true` to
`bootstrapJob.containerSecurityContext` without a numeric `runAsUser` and check what happens** —
kubelet cannot verify a non-numeric user, so the expected result is admission failure with
`container has runAsNonRoot and image will run as root`. Two reasons to test it deliberately:

- On **OpenShift** the SCC injects a numeric UID, which may mask the problem entirely — so a pass here
  does **not** mean a vanilla-Kubernetes user is safe. Say so in your evidence.
- The whole point of making `bootstrapJob` configurable is that users will now set these fields. If a
  plausible combination fails, it needs documenting rather than discovering.

**Pass for this sub-check:** either it's admitted with an SCC-injected UID (record that the SCC is
what saved it), or it fails and you've confirmed the failure mode is understood and documented.

**Step 6 — PVC write permissions under the opt-out.**
**Validates:** the portal is the **only component with a real PVC**. With `fsGroup` omitted the SCC
assigns the GID — if that plumbing is wrong, the portal **starts but cannot write**, which no
admission check catches.
**Pass:** portal writes to its storage; no permission errors in logs.
**Evidence:** a successful write plus a clean log. §6 row 8 needs the portal *running*, not admitted.

### TC-06 Step 6 · Data-plane connection-string live check · P1 · ~30 min

Owner 1 ran Steps 1–5 (renders plus the `useSecretName` upgrade regression) and will send you the
secret name and key they used.

**Step 6 — Live check on your admin cluster.** With a real secret and a reachable MDCB, confirm the data-plane
gateway connects.
**Validates:** that the env var is not just **rendered** but **readable at runtime** — a
`secretKeyRef` pointing at a missing key fails at **pod start**, not at render, so no amount of
`helm template` catches it.
**Pass:** gateway logs show a successful MDCB connection.
**Evidence:** the gateway log line, plus the secret name/key you used.

---

## Close out

- [ ] Consolidate every result against the pinned SHA, in the format in
      [`00-shared-setup.md`](00-shared-setup.md#reporting-results) — **every OpenShift result must
      carry `oc whoami` and the UID range**
- [ ] File defects — prefix `[TT-17018 QA]`, with explicit **blocks 5.4.0: yes/no**
- [ ] Write up the Redis/PostgreSQL workaround from S6 for §8 Q2 and follow-up §7.7
- [ ] Send Owner 1 the OpenShift docs gaps for §6 row 14: the `enabled: false` opt-out (**and why
      `{}` doesn't work**), the Redis/PostgreSQL caveat, and anything TC-05 Step 3 found still
      recommending the unreachable ArgoCD hook annotation
- [ ] If gap #9 was confirmed, file the umbrella-values defect and flag follow-up §7.6 (expose
      `managerPodSecurityContext`; remove or document the dead `podSecurityContext` key)
- [ ] Bring to the Thursday review: §8 Q2 (scope of "no Kustomize patches") — you are the only
      person with the evidence for it
- [ ] **State the single-node delta.** If you ran on SNO or local CRC, the cluster had one node, so
      nothing here covers multi-AZ or multi-node scheduling. It doesn't affect TC-04's installs or
      TC-05's sync-wave ordering, and CRC wouldn't have covered it either — but record it as a known
      limit of the evidence rather than letting someone assume it was tested. **Nothing else covers
      it** — TC-12 was removed, so multi-AZ ROSA is an accepted residual risk, not a delegated task.

Any **P0** — TC-03 not reproducing, or a TC-04 umbrella failing to install — escalates the **same
day** and forces §8 Q3: revert `main`, or fix forward before the 5.4.0 cut.

---
## Deliberately not doing — and why

Recorded so the sign-off meeting accepts the scope knowingly rather than someone finding a gap on
day 5. All of these appear in the master plan; none of them validate the change.

| Dropped | Why it isn't required |
|---|---|
| **Any PR to `tyk-charts`** | Nothing in your packet requires one. The opt-out values files are *inputs* — `helm install -f <path>` behaves identically from Owner 1's working copy. |
| **Corporate private-registry access** | TC-07 Step 2 needs *a* registry requiring auth, not a specific one. Self-host `registry:2` with htpasswd (S7) and the negative control is just as real. |
| **A cloud-registry access request as a day-0 blocker** | Removed entirely by the above. |
| **Building an OLM catalogue if the GitOps operator is unavailable** | Fall back to community ArgoCD manifests and record the delta (S4 Step 4). TC-05 tests sync-wave ordering and hook-free bootstrap, not the operator's packaging. |
| **Multi-AZ / multi-node coverage** | Your cluster is single-node, and TC-12 is removed — so this is an **accepted residual risk**, recorded at sign-off. Modest for the changes in scope: SCC, annotations and bootstrap are all node-count-independent. |
| **Asking the customer to validate anything** | TC-12 is removed entirely. Its acceptance criterion is now proven directly in TC-04 Step 11. |

## The one follow-up worth arguing for afterwards

Not work for this pass — but you'll finish knowing the CI gap better than anyone, so it's worth
five minutes at the review. Master plan §7.1: **a real-SCC CI gate on MicroShift.** Everything in
your packet that CI structurally cannot cover reduces to "kind has no SCC controller."

The evidence is stronger than the master plan knew. MicroShift's SCC stack was checked against source
for this pass and is faithful, not approximate: the same SCC objects including `restricted-v2` bound
to `system:authenticated`, the same four kube-apiserver SCC admission plugins, and
`cluster-policy-controller` running the namespace-security-allocation-controller that produces
`openshift.io/sa.scc.uid-range`. **So TC-03's probe would behave on MicroShift exactly as on real
OpenShift** — which is the whole argument. Two caveats to include so nobody is surprised: MicroShift
has no OAuth server (a CI harness uses a ServiceAccount token or
`oc --as=system:serviceaccount:<ns>:probe --as-group=system:authenticated`), and its PodSecurity
admission defaults to `enforce: restricted` where full OpenShift is effectively `privileged`.

Supporting quote you already have: `tyk-oss/ci/no-securitycontext-values.yaml` says in its own
comments that *"Real SCC coverage needs a cluster that has one (e.g. MicroShift)."* Whoever wrote it
reached the same conclusion.
