---
name: helm-drift
description: >
  Detect drift between workspace Helm charts and live cluster state.
  Compares chart templates, values files, and deployed Helm releases
  to find mismatches in image tags, config, replicas, and resources.
  Use when a deployment doesn't match what's in the repo.
---

# Helm Drift Detection

This skill compares what the workspace Helm chart *would* deploy against what is
*actually running* in the cluster. It identifies configuration drift that causes
unexpected behavior.

## Prerequisites

- The workspace must contain a Helm chart (a directory with `Chart.yaml`).
- The `kubernetes-inspect` MCP server must be running with the `helm` toolset enabled.

## Procedure

### 1. Inventory workspace charts

Search the workspace for all `Chart.yaml` files. For each chart, note:

- Chart name and version (`Chart.yaml` → `name`, `version`, `appVersion`)
- Available values files (`values.yaml`, `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`, etc.)
- Key templates: deployment, service, ingress, configmap, secrets

### 2. List live Helm releases

```
Tool: helm_list
Args: all_namespaces=true
```

Match each workspace chart to its deployed release by chart name. Record:

- Release name, namespace, status, revision, chart version
- Whether the deployed chart version matches the workspace `Chart.yaml` version

`helm_list` shows the current revision only. Full `helm history` / `helm get values --revision N` are Helm CLI commands via the troubleshooter’s allowlisted `execute` (`change-correlation`). Do not roll back.

### 3. Compare image tags

From the workspace `values.yaml` (or environment-specific values file), extract the
image repository and tag. Then fetch the live deployment:

```
Tool: resources_get
Args: apiVersion=apps/v1, kind=Deployment, name=<release-name>, namespace=<ns>
```

Compare `spec.template.spec.containers[*].image` against the chart values.

### 4. Compare resource limits and requests

Extract `resources.requests` and `resources.limits` from the workspace values and
compare to the live deployment spec. Flag any mismatch.

### 5. Compare replica count

Workspace values `replicaCount` vs live deployment `spec.replicas`.

### 6. Compare environment variables and config

Check live ConfigMaps and Secrets referenced by the deployment:

```
Tool: resources_get
Args: apiVersion=v1, kind=ConfigMap, name=<name>, namespace=<ns>
```

Compare keys (not values of Secrets) against what the chart templates would produce.

### 7. Compare probes

Check readiness and liveness probe configuration (path, port, timeouts) between
the chart template and the live spec.

### 8. Check for extra or missing resources

List all resources in the release namespace that match the release labels:

```
Tool: resources_list
Args: apiVersion=v1, kind=Service, labelSelector="app.kubernetes.io/instance=<release>"
```

Repeat for Ingress, NetworkPolicy, PDB, HPA, ServiceAccount. Flag any resource
that exists live but not in the chart, or vice versa.

### 9. Report drift

Present findings as a table:

| Resource | Field | Workspace Value | Live Value | Severity |
|----------|-------|----------------|------------|----------|
| Deployment/api | image tag | v2.3.1 | v2.2.0 | High |
| Deployment/api | memory limit | 512Mi | 256Mi | Medium |
| Deployment/api | replicas | 3 | 2 | Medium |

Severity levels:
- **High** — likely causing the current incident (wrong image, missing config)
- **Medium** — could cause issues under load or during failover
- **Low** — cosmetic or non-functional difference

### 10. Suggest resolution

For each drift item, recommend one of:
- **Redeploy from chart** — the workspace is correct, the cluster is stale
- **Update chart** — the live value is intentional, update the chart to match
- **Helm rollback** — a recent release introduced the drift; roll back to a known-good revision
- **Investigate** — the drift is unexpected and needs further analysis

Do **not** execute any changes. Treat confirmed drift as input to the **`rca`**
skill. Use **`change-correlation`** (`helm history`, values by revision) to see
which release introduced the drift. Do not roll back — identification only.
