# Demo script

About 35 minutes end to end. Every promotion is manual, and each one takes
about 2.5 minutes to verify. A new version takes up to 1 minute to appear as
Freight (polling); click the Warehouse's refresh button in the Kargo UI to skip
the wait.

## Before you go on stage

```bash
make up          # if the cluster isn't running (~15 min)
make preflight   # must end with "all green, ready to demo"
make passwords
```

Open three browser tabs:

1. **Kargo**: http://localhost:8081, project `kargo-kustomize`
2. **Argo CD**: http://localhost:8080
3. **GitHub**: the repo's branch list (`main` and `env/kz-*`)

Keep a terminal open in the repo with `export KUBECONFIG=$PWD/.kube/config`.

Starting state: all four Stages run the same Freight (image **6.15.0**, chart
**6.15.0**, config *v1*), and every verification is green.

---

## 1. The setup (3 min)

**Show:** the Kargo pipeline view:
`dev → staging → prod-eu / prod-us`.

**Say:**
- "Argo CD answers *how* to deploy: it keeps each namespace in sync with Git.
  Kargo answers *what* goes *where*, and *when*. It moves a release from one
  environment to the next."
- "A release is called *Freight*. Ours bundles three things: the app image, the
  Helm chart that deploys it, and a commit of our shared config. Change any one
  and you get new Freight, which moves through the pipeline as a unit."
- "Every promotion here is a human decision. A Stage only accepts Freight that
  passed verification in the Stage before it. The two prod regions are
  independent."
- "Kargo never touches the cluster. It commits to Git and asks Argo CD to sync,
  so Git stays the single source of truth."

**Show:** `gitops-kustomize/`:
- `base/` renders the chart (Helm inside Kustomize) with shared values, plus a
  ServiceMonitor and a traffic generator. Kargo writes the chart version here.
- `overlays/<env>/` sets the namespace, a small patch (replicas, color) and the
  image tag. Kargo writes the tag here.
- Each environment deploys from its own branch `env/kz-<stage>`, written only by
  Kargo.

## 2. A new image (6 min)

```bash
make release TAG=6.16.0
```

**Say:** "CI just pushed podinfo 6.16.0. The Warehouse polls the registry and
creates Freight. Nothing deploys until someone decides."

**Show, in order:**
1. A new Freight appears (image `6.16.0`, same chart, same config). No Stage
   moves.
2. **Promote it to dev** in the UI (or `make promote STAGE=dev`).
3. **GitHub**: a new commit on `env/kz-dev`,
   `dev: image 6.16.0, chart 6.15.0, config …`. "That's Kargo. It's the
   only way an environment changes."
4. **Argo CD**: `dev` syncs to that commit and turns Healthy.
5. **Kargo, dev → Verifications**: an AnalysisRun is running. Open it.
   "This isn't a health check. It queries Prometheus for the real success rate
   and p95 latency of pods running *this exact version*."
6. Once verified, **promote it to staging** the same way.

## 3. A chart upgrade (4 min)

```bash
make release-chart VERSION=6.17.0
```

**Say:** "Platform changes go through the same gate. The team that owns the
Helm chart just published 6.17.0."

**Show:** new Freight with chart `6.17.0` and the same image. Promote it to
dev, then show the commit: only the chart `version:` line in
`base/kustomization.yaml` changed.

## 4. A config change, through Git (4 min)

```bash
make config MSG="Kustomize config v2"
```

**Say:** "Shared config is promoted too. I changed one line in
`gitops-kustomize/base/values.yaml` on `main` and pushed it. That commit becomes Freight like
any image."

**Show:**
1. New Freight with a new config commit. Promote it to dev.
2. The dev app now says *Kustomize config v2*:
   ```bash
   kubectl -n kz-dev exec deploy/traffic-generator -- curl -s http://podinfo:9898/ | jq .message
   ```
3. staging still says *v1*: "The change only reaches an environment when
   it's promoted there, after passing verification upstream."
4. Promote it to staging.

## 5. Production, region by region (4 min)

**Say:** "Staging verified this Freight, so prod is *allowed* to take it.
Allowed isn't deployed: each region is its own decision."

**Do:** promote **prod-eu** from that Freight.

**Show:** the EU region promotes and verifies, and **prod-us hasn't changed**.
"Two regions, two decisions. I could stop here and watch one for an hour."

**Do:** promote **prod-us** the same way.

```bash
make status        # one line per Stage: Freight, image, chart, config, verification
```

## 6. The failure: a bad image (5 min)

```bash
make break         # publishes image 6.16.1: pods healthy, every request returns HTTP 500
```

**Say:** "Here's a realistic bug. The pods start, liveness and readiness probes
pass, and Argo CD will say Healthy. But every user request fails."

**Show, in order:**
1. New Freight with image `6.16.1`. Promote it to dev.
2. **Argo CD**: `dev` is **Synced and Healthy**. "By every
   infrastructure signal, this deploy succeeded."
3. Optional, to prove the 500s:
   ```bash
   kubectl -n kz-dev exec deploy/traffic-generator -- curl -s -o /dev/null -w '%{http_code}\n' http://podinfo:9898/
   ```
4. **Kargo, dev → Verifications**: the AnalysisRun **fails** after about
   1.5 minutes, with a success rate of 0.
5. Try to promote it to staging. The UI doesn't offer it, and the CLI is
   refused:
   ```bash
   make promote STAGE=staging FREIGHT=6.16.1
   # ... spec.freight: Invalid value: "...": Freight is not available to this Stage
   ```
   "Bad Freight is blocked. It can't leave dev, even by mistake."

## 7. Recovery (4 min)

```bash
make fix           # publishes image 6.17.0, a good release
```

**Say:** "We fix forward. The team ships 6.17.0. We promote it to dev,
verification passes, then staging. Production stayed on the last good
Freight the whole time."

## Wrap-up talking points

- Git is the audit trail. Every environment change is a commit made by Kargo.
- One unit of release: image, chart and config move together and are verified
  together.
- Verification uses real traffic metrics, not "the pod is running".
- Gates are explicit and per environment; prod regions are independent.
- Speed is tunable (`kargo/common/analysis-template.yaml`).

## If something goes wrong on stage

| Symptom | Fix |
|---|---|
| New version doesn't show up | Kargo UI: refresh the Warehouse. Or `kubectl -n kargo-kustomize annotate warehouse podinfo kargo.akuity.io/refresh=$(date +%s) --overwrite` |
| Argo app stuck OutOfSync | Argo CD UI: Refresh, then Sync. Or `kubectl -n argocd annotate application kz-dev argocd.argoproj.io/refresh=hard --overwrite` |
| Verification fails on a good version | Check traffic: `make preflight`. Retry from the Stage's Verifications tab ("Reverify") |
| Anything else | `make down && make up` (~15 min). Do it before the talk, not during |

**Approve vs. Promote:** the Kargo UI also has **Approve**, which marks Freight
as allowed in a Stage *without* verification (the hotfix escape hatch). Don't
click it during the failure demo, or the bad Freight goes through.
