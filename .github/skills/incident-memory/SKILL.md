---
name: incident-memory
description: >
  Search and save incident records in the team's memory bank. Records are
  stored as Markdown files in .github/memory/, indexed by application name
  and issue type. Use at the start of every investigation to find past
  incidents, and after completing an RCA to save new findings.
---

# Incident Memory

The memory bank lives in `.github/memory/`. Each incident is a Markdown file
inside a subdirectory named after the application. An `INDEX.md` at the root
cross-references all incidents by app and by issue type.

```
.github/memory/
  INDEX.md                                    # Cross-reference index
  _TEMPLATE.md                                # Template for new records
  payments-api/
    crashloop--2026-08-16.md                  # Individual incident
    oom-killed--2026-08-10.md
  auth-service/
    image-pull--2026-08-15.md
```

## When to Use This Skill

### Before investigating (recall)
At the **start** of every troubleshooting session, before diving into MCP
tools, search memory for past incidents involving the same application or
the same issue type. Prior RCAs often reveal recurring patterns, known
workarounds, or environmental quirks that accelerate the current investigation.

### After completing an RCA (save)
After presenting a root-cause analysis to the user, offer to save the
findings to memory. Only save when the user confirms.

---

## Procedure: Recall (Search Memory)

Token-cheap. Follow **`token-thrift`**.

### Step 1 — Read the index only
Read `.github/memory/INDEX.md`. Do not search or open other memory files yet.

### Step 2 — Match one line
Look for the **same application** or **same issue type**. Use the one-line summary.
If nothing matches, say so and continue. Do not open e2e example records unless
the user is investigating `dto-e2e`.

### Step 3 — At most one full record
If a line matches, read **that one** file. Use **Symptom** and **Root Cause** only.
Treat the prior cause as a **hypothesis to test**, not the answer.

### Step 4 — Tell the user (one sentence)
"INDEX has a similar `crashloop` on 2026-08-10 (missing DSN) — I will test that, not assume it."

---

## Procedure: Save (Record New Incident)

Only proceed when the user confirms they want to save the incident to memory.

### Step 1 — Gather metadata
From the completed RCA, extract:
- `app` — the application name (e.g., `payments-api`)
- `issue_type` — the primary failure category. Use one of:
  `CrashLoopBackOff`, `OOMKilled`, `ImagePullBackOff`, `Pending`,
  `NotReady`, `Unreachable`, `ConnectionRefused`, `HelmDrift`,
  `ProbeFailure`, `ConfigError`,   `IngressBackend`, `TLSExpired`, `ResourceQuota`,
  `SchemaMismatch`, `ReplicationLag`, `Other`
- `namespace` and `cluster`
- `date` — today's date in `YYYY-MM-DD` format
- `severity` — `critical`, `high`, `medium`, or `low`
- `resolved` — `true` or `false`
- `resolution_type` — `pod-restart`, `scale-up`, `helm-rollback`,
  `config-fix`, `code-fix`, `infra-fix`, `manual`, or `none`
- `time_to_resolve` — approximate duration

### Step 2 — Generate the filename
Format: `<app>/<issue-type-slug>--<YYYY-MM-DD>.md`

Convert the issue type to a lowercase slug:
- `CrashLoopBackOff` → `crashloop`
- `OOMKilled` → `oom-killed`
- `ImagePullBackOff` → `image-pull`
- `NotReady` → `not-ready`
- `Unreachable` → `unreachable`
- `IngressBackend` → `ingress-backend`
- `TLSExpired` → `tls-expired`
- `ResourceQuota` → `resource-quota`
- `ConnectionRefused` → `connection-refused`
- `HelmDrift` → `helm-drift`
- `ProbeFailure` → `probe-failure`
- `ConfigError` → `config-error`
- `SchemaMismatch` → `schema-mismatch`
- `ReplicationLag` → `replication-lag`
- `Pending` → `pending`
- `Other` → `other`

If a file with that name already exists, append `-2`, `-3`, etc.

### Step 3 — Create the app directory if needed
If `.github/memory/<app>/` doesn't exist, create it.

### Step 4 — Write the incident file
Use the template from `.github/memory/_TEMPLATE.md`. Fill in all sections
from the RCA findings. Include:
- Specific log lines or error messages in the Symptom section
- Timeline and what was checked (including gaps)
- Hypotheses kept vs rejected
- The confirmed or suspected root cause with confidence
- Recommendations (not executed)
- Exact commands or changes applied in Resolution (only if humans already did them)
- Exact commands or changes applied in Resolution
- Actionable prevention steps in Lessons Learned

### Step 5 — Update the index
Read `.github/memory/INDEX.md` and add entries in both sections:

**By Application** — under the app heading (create the heading if it's the
app's first incident). Replace `_No incidents recorded yet._` if present.
Format:
```
### <app>
- [<issue_type> (<date>)](<app>/<filename>) — <one-line summary>
```

**By Issue Type** — under the issue type heading (create the heading if it's
new). Replace `_No incidents recorded yet._` if present.
Format:
```
### <issue_type>
- [<app> (<date>)](<app>/<filename>) — <one-line summary>
```

### Step 6 — Confirm to the user
Tell the user what was saved and where:
- Path to the new incident file
- That the index was updated
- Suggest reviewing the file for accuracy

---

## Rules

- **Never save without user confirmation.**
- **Never modify or delete existing incident records** unless the user
  explicitly asks to update one.
- **Never include secrets, passwords, tokens, or PII** in incident records.
  Redact before saving.
- **Keep summaries concise** — incident files should be scannable (~60 lines), not
  exhaustive transcripts. Quote ≤3 log lines. INDEX remains one line per incident.
