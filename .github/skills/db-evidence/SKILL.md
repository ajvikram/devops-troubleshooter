---
name: db-evidence
description: >
  Gather database evidence for DevOps troubleshooting using read-only queries.
  Supports Postgres, MySQL, Oracle, SQL Server, SQLite, ClickHouse, Elasticsearch,
  Neo4j, Snowflake, and MongoDB. Never runs writes (SQL DML/DDL, Mongo insert/update,
  index mutations). Use when an incident may involve the data layer.
---

# Database Evidence Gathering

This skill collects evidence from databases to support incident investigation.
It operates under strict read-only constraints.

## Non-Negotiable Rules

1. **Read only.** Never execute `INSERT`, `UPDATE`, `DELETE`, `DROP`, `ALTER`,
   `TRUNCATE`, `CREATE`, `GRANT`, `REVOKE`, Mongo `insert`/`update`/`delete`,
   Elasticsearch index writes, or Neo4j mutating Cypher (`CREATE`, `MERGE`, `DELETE`, `SET`).
2. **No PII without consent.** Do not query collections/tables likely to contain
   personally identifiable information unless the user explicitly directs you to.
3. **No secrets.** Never select from credential stores or password fields. Redact immediately.
4. **Limit result sets.** Default to 20 documents/rows. Use `LIMIT` / `FETCH FIRST` /
   Mongo `.limit(20)` / ES `size: 20`.
5. **Explain before querying.** Tell the user what you plan to run and why.

## When to Use This Skill

Use when Kubernetes investigation shows connection refused/timeouts, missing or
stale data, schema/collection mismatches, or pool exhaustion.

## 1. Identify the database

From the app spec (env, ConfigMaps, Helm values), identify type, host, and name.
Confirm which MCP server to start — **only one at a time** (Copilot 128-tool cap):

| Server | Detect in `mcp.env` | Engine |
|--------|---------------------|--------|
| `db-postgres` | `POSTGRES_HOST` | PostgreSQL |
| `db-mysql` | `MYSQL_HOST` | MySQL / MariaDB |
| `db-oracle` | `ORACLE_CONNECTION_STRING` | Oracle |
| `db-mssql` | `MSSQL_HOST` | SQL Server |
| `db-sqlite` | `SQLITE_DATABASE` | SQLite file |
| `db-clickhouse` | `CLICKHOUSE_HOST` | ClickHouse |
| `db-elasticsearch` | `ELASTICSEARCH_HOST` | Elasticsearch |
| `db-neo4j` | `NEO4J_URI` | Neo4j |
| `db-snowflake` | `SNOWFLAKE_ACCOUNT` | Snowflake |
| `db-mongodb` | `MDB_MCP_CONNECTION_STRING` | MongoDB (`--readOnly`) |

If the MCP server is not started, say so. That is a gap, not a cause.

## 2. Schema / catalog inspection

**Postgres / MySQL / SQLite / SQL Server / Snowflake / ClickHouse / Oracle** — list tables, then columns (information_schema or vendor catalog). Limit 200 columns.

**MongoDB** — list databases and collections; sample one document with projection that omits secrets. Do not dump entire collections.

**Elasticsearch** — list indices and mappings for the index named in logs.

**Neo4j** — `CALL db.labels()` / `CALL db.relationshipTypes()` only.

## 3. Session / health diagnostics (SQL engines)

**Postgres:** `pg_stat_activity` (non-idle, LIMIT 20).

**MySQL:** `information_schema.processlist` (non-Sleep, LIMIT 20).

**Oracle:** `v$session` ACTIVE (FETCH FIRST 20).

**SQL Server:**
```sql
SELECT TOP 20 session_id, login_name, status, wait_type, cpu_time, total_elapsed_time
FROM sys.dm_exec_requests
WHERE session_id > 50
ORDER BY total_elapsed_time DESC;
```

**MongoDB** — server status / current ops **read** tools only. Never `drop` or `kill`.

## 4. Table / collection health

Row/document counts and a recent-timestamp column if one exists. Adapt names from step 2.

## 5. Correlate with Kubernetes

Pool exhaustion ↔ replica count and connection limits. Slow queries ↔ CPU/memory limits.
Wrong schema ↔ migration Job. Mongo auth/TLS errors ↔ Secret/URI in the chart vs live env.

## 6. Report in the RCA

- **Database state:** healthy / degraded / unreachable
- **Key metrics:** connections, locks, lag, index health
- **Data issues:** missing collection/table, stale data, schema mismatch
- **Correlation:** how this explains the user symptom

Database findings are hypotheses until they explain the symptom.
