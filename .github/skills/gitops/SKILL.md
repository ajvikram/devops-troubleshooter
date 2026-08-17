---
name: gitops
description: >
  Identify drift between GitOps desired state (Argo CD Application, Flux
  Kustomization/HelmRelease) and live cluster objects. Read-only. Use when the
  cluster is synced from git, not only from a Helm chart in this workspace.
---

# GitOps (desired git vs live)

Identification only. Never `argocd app sync`, `flux reconcile`, or patch Applications.

Many clusters are not “Helm chart in this repo.” If Argo or Flux is in play, the
desired spec lives in git and a controller. This skill finds **OutOfSync**,
**unknown source**, or **live objects that do not match Application destination**.

## 1. Detect the controller

List (namespace or cluster) without inventing CRDs:

| Kind | apiVersion |
|------|------------|
| Application | `argoproj.io/v1alpha1` |
| ApplicationSet | `argoproj.io/v1alpha1` |
| Kustomization | `kustomize.toolkit.fluxcd.io/v1` (or v1beta2) |
| HelmRelease | `helm.toolkit.fluxcd.io/v2` (or v2beta*) |
| GitRepository | `source.toolkit.fluxcd.io/v1` |

If these kinds are unknown to the API (`no matches for kind`), GitOps is **not
installed**. Say so, use `helm-drift` + `change-correlation`, and stop this skill.

## 2. Argo CD Application

`resources_get` the Application. Record:

- `spec.source.repoURL`, `path` or `chart`, `targetRevision` (branch/tag/SHA)
- `spec.destination.namespace` and `server`
- `status.sync.status` — Synced vs OutOfSync
- `status.health.status`
- `status.operationState` / last sync time
- `status.resources` where status is OutOfSync

Compare `targetRevision` and last sync time to the incident timeline
(`change-correlation`). An OutOfSync app after a git push that never synced is
a **trigger**: live cluster is behind git, or git is behind a manual change.

Search this workspace for the same `path` / chart. If the repo is not this
workspace, say **desired state is in another repo** and quote repoURL only.

## 3. Flux

`resources_get` Kustomization / HelmRelease:

- `spec.sourceRef` + `spec.path` / chart
- `spec.interval`, `suspend`
- `status.conditions` (Ready=False, Reconciling, Stalled)
- `status.lastAppliedRevision` vs `status.lastAttemptedRevision`

Suspended (`spec.suspend: true`) means git changes will **not** land — high
confidence explanation for “we merged but cluster did not change.”

## 4. Live vs desired (without applying)

Do **not** `kubectl diff` against generated YAML unless the user has the
rendered manifests in the workspace. Prefer:

- Application/HelmRelease status fields (controller already computed drift)
- `helm-drift` when the destination is a Helm chart also in this repo
- Image tag on the live Deployment vs `targetRevision` / values in git

## 5. Feed the RCA

Examples:

- Application `payments` OutOfSync; live image `v2.3.0`, git `main` wants `v2.3.1`
- HelmRelease Ready=False, `status.conditions` message Helm install failed
- Flux Kustomization suspended since 14:00 — merge did not roll out

Restarting pods will not sync GitOps. Do not sync. Name the drift.
