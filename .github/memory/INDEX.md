# Incident Memory Index

This index is maintained by the DevOps Troubleshooter agent. Each entry links to
a detailed incident record stored as a Markdown file in a subdirectory named after
the application.

## How This Index Works

- **By Application**: incidents grouped under the app that was affected.
- **By Issue Type**: the same incidents cross-referenced by failure category.
- Entries are added when the troubleshooter completes an RCA and the user confirms.
- File naming: `<app>/<issue-type>--<YYYY-MM-DD>.md`
- Kit **example** records below are from the e2e fixtures. Treat them as hypotheses
  to test, not as the current cluster’s RCA.

---

## By Application

### crashloop
- [CrashLoopBackOff (2026-08-10)](crashloop/crashloop--2026-08-10.md) — exit 1, `CONFIG_ERROR: missing PAYMENTS_DSN` (e2e example)

### mismatch
- [Unreachable (2026-08-12)](mismatch/unreachable--2026-08-12.md) — Service selector `app=payments` vs pods `app=payments-api` (e2e example)

---

## By Issue Type

### CrashLoopBackOff
- [crashloop (2026-08-10)](crashloop/crashloop--2026-08-10.md) — missing PAYMENTS_DSN (e2e example)

### Unreachable
- [mismatch (2026-08-12)](mismatch/unreachable--2026-08-12.md) — selector mismatch (e2e example)
