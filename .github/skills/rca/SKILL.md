---
name: rca
description: >
  Structured root-cause analysis for incidents. Use on every troubleshooting
  session: frame the user symptom, build a timeline, list competing hypotheses,
  confirm one with evidence, and state what was ruled out and what remains unknown.
---

# Root-Cause Analysis

Finding the issue is the product. Do not jump to a single cause from the first
red log line. Do not recommend actions until the RCA cause is written. Never apply
changes — **recommendations** only.

This skill is mandatory for the DevOps Troubleshooter. Other skills (`k8s-incident`,
`saturation`, `service-path`, `ingress-tls`, `change-correlation`, `gitops`,
`helm-drift`, `db-evidence`, `observability`) are how you gather evidence. This
skill is how you turn evidence into a cause.

## 1. Frame the symptom (user, not object)

Write one sentence the user would recognize:

- Bad: "Pod `payments-api-7f9` is CrashLoopBackOff."
- Good: "Checkout payments fail; the API pods keep restarting in `staging`."

If the user gave only a pod name, still restate impact: who is broken, which
env, since when (if known).

## 2. Classify the failure mode

Pick **one primary class** before deep-diving. Reclassify if evidence contradicts.

| Class | Cluster looks like | Use |
|-------|-------------------|-----|
| **Crash** | Restarts, BackOff, OOMKilled, non-zero exit | `k8s-incident` |
| **Not Ready** | Phase Running, Ready=False, probe Unhealthy | `k8s-incident` probes + `service-path` |
| **Unreachable** | Pods Ready, but 502/timeout/no endpoints | `service-path` |
| **Edge / TLS** | URL/HTTPS fails; backend or cert wrong | `ingress-tls` after `service-path` |
| **Wrong version / drift** | Healthy but behavior changed after deploy | `helm-drift` + `change-correlation` |
| **Data layer** | App logs show DB/timeouts/schema | `db-evidence` |
| **Saturation** | Pending, quota, HPA at max, PVC, node pressure | `saturation` |

You may use more than one skill. You must name the class in the RCA.

## 3. Timeline

Build a short sequence from evidence only (events, pod startTime, **Helm history**,
git SHA, image tag, log timestamps, Grafana window). Follow `change-correlation`.
If you cannot name a revision or commit, write **unknown change**.

1. `14:02` Helm revision 12 deployed (image `v2.3.1`)
2. `14:03` New ReplicaSet scaled up
3. `14:04` Liveness probe Unhealthy on all new pods
4. `14:05` Users report 502s

If you cannot build a timeline, say **unknown start** and ask the user when it
began. A cause without a "when" is usually a guess.

## 4. Competing hypotheses (before the conclusion)

List **2–4 hypotheses** that could explain the symptom. For each:

| Hypothesis | Evidence for | Evidence against | Next check |
|------------|--------------|------------------|------------|
| … | tool + fact | tool + fact | what you will inspect |

Rules:

- Generate hypotheses **after** context + first pod/event scan, **before** declaring a root cause.
- At least one hypothesis must be something other than "the app is buggy."
- A hypothesis with no disconfirming check is not done.
- Prefer causes you can prove from cluster + chart + logs (image tag, missing Secret, empty Endpoints, OOM lastState, probe path mismatch).

## 5. Confirm or reject

A root cause is ready when:

1. **Confirming evidence** exists (specific log, event reason, spec field, query).
2. **Likely alternatives are ruled out** (or marked still-open with why you stopped).
3. You can point at the **trigger** (deploy, config change, traffic, node pressure, dependency) when the data supports it.

If two causes remain plausible, say so. Split **contributing factors** from **root cause**
(e.g. root cause = memory limit 256Mi; contributing = traffic spike).

Confidence:

- **High** — lastState + events + spec (or chart) all agree.
- **Medium** — strong logs/events, but a dependency was not inspected.
- **Low** — symptoms only; say what evidence is missing (no previous logs, Grafana down, no Helm history).

Never invent cluster state. If MCP failed, that is a gap, not a cause.

## 6. RCA output (required format)

Present exactly these sections:

### Symptom
User-facing impact + environment (context / namespace).

### Timeline
Bullet timestamps. Or "start time unknown."

### What we checked
Short list of objects (pods, events, deployment, service/endpoints, helm, chart, DB, metrics). Include **what we did not check** and why.

### Hypotheses
Table or bullets: kept / rejected, with evidence.

### Root cause
One paragraph. Name the class. Confidence high/medium/low.
If unknown, say **undetermined** and list the single best next check.

### Blast radius
Which replicas, namespaces, and user flows are affected. What is still healthy.

### Recommendations
Required. What a human should do to address the **root cause**. Do **not** execute.

For each item:

| # | Recommendation | Addresses | Owner | Notes |
|---|----------------|-----------|-------|-------|
| 1 | … | the named cause | chart / app / platform / certs | why this works; what it will not fix |

Rules:

- Tie each recommendation to the confirmed cause (or to a remaining gap).
- Prefer durable fixes (values.yaml selector, probe path, DSN, quota, Ingress backend, TLS secret) over “restart the pod.”
- If you mention restart, label it **mitigation** and say what will still be broken.
- Order by how directly they remove the cause, then by blast radius (smallest first).
- No `kubectl apply`, Helm rollback, or secret writes from this agent.

## 7. What you must never do

- Declare a root cause from a single log line with no timeline or ruled-out alternatives.
- Confuse **symptom** (CrashLoopBackOff) with **cause** (OOM at 256Mi limit after v2.3.1).
- Recommend restart as the RCA. Restart is a mitigation, not a cause, and usually not the recommendation that removes the cause.
- Skip Service/Endpoints because pods are `Running` (Running ≠ Ready ≠ reachable).
- Dump raw tool output as the RCA. Quote the few lines that prove the cause.
