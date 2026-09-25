# Karma Score — Full Analysis & Implementation Report

**Date:** 2026-09-25
**Branch:** `user/bhatturu/karma-time-limit-min` on `bhatturu/spur`
**Requested by:** Shrey Ajmera
**Original design doc:** `device-metrics-exporter/docs/karma-score-design.md`

---

## 1. Original Proposal

The design doc proposed **10 new Prometheus counters** in Spur's Rust code (9 counters + 1 gauge) to support 6 karma sub-scores:

| # | Proposed Metric | Type | Karma Dimension |
|---|---|---|---|
| 1 | `spur_user_jobs_submitted_total` | counter | Reliability denominator |
| 2 | `spur_user_jobs_completed_total` | counter | Reliability numerator |
| 3 | `spur_user_jobs_failed_total` | counter | Reliability |
| 4 | `spur_user_jobs_timeout_total` | counter | Reliability |
| 5 | `spur_user_jobs_node_fail_total` | counter | Reliability (excluded) |
| 6 | `spur_user_jobs_cancelled_total` | counter | Cancellation rate |
| 7 | `spur_user_gpus_requested_total` | counter | Resource accuracy |
| 8 | `spur_user_overflow_borrows_total` | counter | Citizenship |
| 9 | `spur_user_walltime_requested_seconds_total` | counter | Wall time accuracy |
| 10 | `spur_user_walltime_actual_seconds_total` | counter | Wall time accuracy |
| 11 | `spur_job_gpu_assignment` | gauge | GPU utilization join key |

The design doc's reasoning: existing per-user metrics (`spur_user_jobs_completed{username}` etc.) are **gauges**, not counters. Gauges snapshot current in-memory state and drop when jobs are evicted (default 1 hour). PromQL `rate()` on a gauge over 30 days produces garbage.

---

## 2. Key Finding: The Accounting Database

**The design doc overlooked Spur's PostgreSQL accounting database.** When `[accounting].database_url` is configured, `spurctld` writes every job to a `jobs` table — permanently. This data survives restarts, eviction, and Raft leader changes.

### What the accounting DB already stored

| Data | DB Column | Populated? |
|---|---|---|
| Job ID | `job_id` | Yes |
| Username | `user_name` | Yes |
| Account | `account` | Yes |
| QOS | `qos` | Yes |
| Final state (COMPLETED, FAILED, CANCELLED, TIMEOUT, NODE_FAIL, etc.) | `state` | Yes |
| Exit code | `exit_code` | Yes |
| Submit time | `submit_time` | Yes |
| Start time | `start_time` | Yes |
| End time | `end_time` | Yes |
| Nodes allocated | `num_nodes` | Yes |
| Tasks | `num_tasks` | Yes |
| CPUs per task | `cpus_per_task` | Yes |
| Memory (MB) | `memory_mb` | Yes |
| Overflow/borrowed run | `idle_fill` | Yes |
| Preemption info | `preempted_by`, `preempt_mode`, `preempt_qos` | Yes |
| **Wall time requested** | `time_limit_min` | **Column existed, NEVER written (always NULL)** |
| **GPUs requested** | — | **Column DID NOT EXIST** |

### Mapping: 10 proposed counters → existing DB data

| # | Proposed Counter | Can be derived from DB? | How |
|---|---|---|---|
| 1 | `spur_user_jobs_submitted_total` | **Yes** | `COUNT(*) FROM jobs WHERE submit_time > NOW()-30d GROUP BY user_name` |
| 2 | `spur_user_jobs_completed_total` | **Yes** | `COUNT(*) FROM jobs WHERE state='COMPLETED' GROUP BY user_name` |
| 3 | `spur_user_jobs_failed_total` | **Yes** | `COUNT(*) FROM jobs WHERE state='FAILED' GROUP BY user_name` |
| 4 | `spur_user_jobs_timeout_total` | **Yes** | `COUNT(*) FROM jobs WHERE state='TIMEOUT' GROUP BY user_name` |
| 5 | `spur_user_jobs_node_fail_total` | **Yes** | `COUNT(*) FROM jobs WHERE state='NODE_FAIL' GROUP BY user_name` |
| 6 | `spur_user_jobs_cancelled_total` | **Yes** | `COUNT(*) FROM jobs WHERE state='CANCELLED' GROUP BY user_name` |
| 7 | `spur_user_gpus_requested_total` | **No** — column missing | Needed `total_gpus` column (code change) |
| 8 | `spur_user_overflow_borrows_total` | **Yes** | `COUNT(*) FILTER (WHERE idle_fill) FROM jobs GROUP BY user_name` |
| 9 | `spur_user_walltime_requested_seconds_total` | **No** — column never written | Needed `time_limit_min` populated (code change) |
| 10 | `spur_user_walltime_actual_seconds_total` | **Yes** | `SUM(end_time - start_time) FROM jobs GROUP BY user_name` |

**Result: 8 of 10 metrics already existed in the DB. Only 2 required Spur code changes.**

---

## 3. Why Existing Prometheus Metrics Cannot Work

### The gauge eviction problem

Spur's per-user metrics endpoint (`/metrics/jobs-users-accts`, gated by `metrics.high_cardinality`) produces gauges from the in-memory job map:

```
spur_user_jobs_completed{username="alice"} 3    ← at time T
spur_user_jobs_completed{username="alice"} 0    ← at time T+1h (jobs evicted)
```

Configuration: `terminal_job_retention_secs = 3600` (default). Jobs are evicted from memory after 1 hour.

- `increase()` on this gauge sees: 3 → 0 = negative rate → Prometheus treats as counter reset → incorrect count
- Even setting retention to max (1 year), the gauge still drops eventually → still unreliable for 30-day windows

### The cluster-wide counter problem

Spur does have counters in `/metrics/scheduler`:

- `spur_scheduler_jobs_submitted` (counter)
- `spur_scheduler_jobs_started` (counter)
- `spur_scheduler_jobs_finalized` (counter)

But these are **cluster-wide** — no `username` label. You can't compute per-user reliability from them.

### Conclusion

Neither gauges nor existing counters can support karma. New data sources are required.

---

## 4. Architecture: The Lighter Alternative

Instead of 10 new Spur counters, we use the accounting DB via `postgres_exporter`:

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐     ┌────────────┐     ┌─────────┐
│  Spur        │────▶│  PostgreSQL       │────▶│  postgres_       │────▶│ Prometheus │────▶│ Grafana │
│  spurctld    │     │  (accounting DB)  │     │  exporter        │     │            │     │         │
│              │     │                   │     │  queries.yaml    │     │ rules.yaml │     │         │
│  writes jobs │     │  permanent store  │     │  SQL → metrics   │     │ sub-scores │     │ dashboards│
│  on state    │     │  38+ columns      │     │  every 30s       │     │ composite  │     │ alerts  │
│  transitions │     │                   │     │                  │     │            │     │         │
└──────────────┘     └──────────────────┘     └──────────────────┘     └────────────┘     └─────────┘

                     ┌──────────────────┐                                     │
                     │  DME GPU Exporter │─────────────────────────────────────┘
                     │  :5000/metrics    │     (GPU utilization per device,
                     │  amd_gpu_gfx_    │      with job_user label when
                     │  activity{...}   │      Spur prolog hook is deployed)
                     └──────────────────┘
```

### Advantages over the 10-counter approach

| Aspect | 10 New Counters (design doc) | SQL Exporter (our approach) |
|---|---|---|
| Spur code changes | 10 new metrics in Rust | 2 column fixes (total_gpus + time_limit_min) |
| Data durability | Counters reset on Spur restart | DB survives restarts |
| Weight tuning | Requires Spur release | Edit queries.yaml/rules.yaml (config only) |
| Historical queries | Only forward from deployment | Retroactive (queries existing DB data) |
| Operational overhead | None (built into Spur) | Deploy postgres_exporter sidecar |
| HA failover | Counter resets on leader change | DB is independent of leader |

---

## 5. Spur Code Changes (2 commits)

### Commit 1: `feat(accounting): populate time_limit_min in job accounting records`

**Problem:** The `jobs` table had a `time_limit_min INTEGER` column that `record_job_start` never bound. It was always NULL.

**Fix:** Added `time_limit_min: Option<i32>` to `JobStartRecord`, populated from `spec.time_limit.map(|d| d.num_minutes() as i32)` at 3 write sites:

| Site | File | Line | Source |
|---|---|---|---|
| Notifier (normal path) | `cluster.rs` | 1926 | `spec_for_notify.time_limit` |
| Reconciler (backfill path) | `reconcile.rs` | 242 | `spec.time_limit` |
| gRPC (external accounting) | `grpc.rs` | 286 | `None` (external RPC has no time limit) |

Also updated `GetJobHistory` gRPC response to return `time_limit` from the DB, so `sacct --format=TimeLimit` now works.

**Files changed:** 4 files, +21/-4 lines

### Commit 2: `feat(accounting): add total_gpus column + karma scoring stack`

**Problem:** The `jobs` table had no `total_gpus` column. Resource accuracy scoring needs to know how many GPUs each user requested.

**Fix:** Added `ALTER TABLE jobs ADD COLUMN IF NOT EXISTS total_gpus INTEGER NOT NULL DEFAULT 0` and populated from `effective_gpus(&spec, spec.num_nodes)` at the same 3 write sites.

Also added the full `deploy/karma/` scoring stack (see Section 6).

**Files changed:** 9 files, +368/-10 lines

### Test results

| Test | Result |
|---|---|
| `cargo build` | Pass |
| `cargo test --workspace` (non-DB) | 656 passed, 5 pre-existing failures (cgroup/permission on dev host) |
| `accounting::db::job_history_tests` (DB-dependent, 72 tests) | All pass |
| `time_limit_min_round_trips_through_db` (new integration test) | Pass — writes `Some(30)` and `None`, reads back correctly |

---

## 6. Karma Scoring Stack

All files in `deploy/karma/`:

### 6.1 `queries.yaml` — postgres_exporter SQL queries

5 queries covering all 6 DB-derivable karma dimensions:

| Query | Prometheus Metric | Used for |
|---|---|---|
| Jobs by state (30d) | `spur_karma_jobs_by_state_job_count{user_name, state}` | Reliability, cancellation |
| Jobs submitted (30d) | `spur_karma_jobs_submitted_total_submitted{user_name}` | Denominators |
| GPUs requested (30d) | `spur_karma_gpus_requested_gpus_requested{user_name}` | Resource accuracy |
| Wall time (30d) | `spur_karma_walltime_{requested,actual}_seconds{user_name}` | Wall time accuracy |
| Idle fill (30d) | `spur_karma_idle_fill_{overflow,total}_count{user_name}` | Citizenship |

### 6.2 `rules.yaml` — Prometheus recording rules

8 recording rules in 2 groups:

**Group: `karma_subscores`**

| Rule | Formula | Weight |
|---|---|---|
| `karma:reliability` | `completed / (completed + failed + timeout + deadline + oom)` | 25% |
| `karma:gpu_utilization` | `avg(amd_gpu_gfx_activity{job_user}) / 100` | 25% |
| `karma:resource_accuracy` | `clamp_max(avg(amd_gpu_gfx_activity{job_user}) / 100, 1)` | 20% |
| `karma:walltime_accuracy` | `clamp(actual_seconds / requested_seconds, 0, 1)` | 10% |
| `karma:citizenship` | `1 - (overflow_count / total_count)` | 15% |
| `karma:cancellation_rate` | `cancelled / submitted` | — |
| `karma:cancellation_score` | `1 - cancellation_rate` | 5% |

**Group: `karma_composite`**

```
karma:score = 0.25 × reliability
            + 0.25 × gpu_utilization (or 0.5 when no DME)
            + 0.20 × resource_accuracy (or 0.5 when no DME)
            + 0.15 × citizenship
            + 0.10 × walltime_accuracy
            + 0.05 × cancellation_score
```

### 6.3 `seed.sql` — Test data

3 user profiles, 38 jobs total:

| User | Profile | Jobs | Key Characteristics |
|---|---|---|---|
| **alice** | Good citizen | 10 | 80% success rate, good wall-time estimates (ran ~45min on 60min limit), no overflow, no cancellations |
| **bob** | Bad citizen | 18 | 46% success rate, 5 cancellations, 3 overflow borrows, terrible wall-time (requested 120min, avg ran ~20min), 1 OOM, 1 timeout |
| **carol** | Moderate | 10 | 78% success rate, no cancellations, no overflow, but terrible wall-time accuracy (requested 24h, ran ~10min) |

### 6.4 `docker-compose.yaml` — Test stack

```yaml
postgres:          # Spur accounting DB with seed data, port 15432
postgres-exporter: # Runs queries.yaml, port 9187
prometheus:        # Scrapes exporter + evaluates rules, port 9090
```

### 6.5 `prometheus.yaml` — Scrape config

Scrapes `postgres-exporter:9187` every 30s, loads `karma-rules.yaml`.

---

## 7. End-to-End Test Results

### 7.1 Raw data from postgres_exporter (`:9187/metrics`)

```
spur_karma_jobs_by_state_job_count{state="COMPLETED",user_name="alice"} 8
spur_karma_jobs_by_state_job_count{state="FAILED",user_name="alice"} 2
spur_karma_jobs_by_state_job_count{state="COMPLETED",user_name="bob"} 6
spur_karma_jobs_by_state_job_count{state="FAILED",user_name="bob"} 5
spur_karma_jobs_by_state_job_count{state="CANCELLED",user_name="bob"} 5
spur_karma_jobs_by_state_job_count{state="OUT_OF_MEMORY",user_name="bob"} 1
spur_karma_jobs_by_state_job_count{state="TIMEOUT",user_name="bob"} 1
spur_karma_jobs_submitted_total_submitted{user_name="alice"} 10
spur_karma_jobs_submitted_total_submitted{user_name="bob"} 18
spur_karma_jobs_submitted_total_submitted{user_name="carol"} 10
spur_karma_walltime_requested_seconds{user_name="alice"} 36000
spur_karma_walltime_actual_seconds{user_name="alice"} 23880
spur_karma_walltime_requested_seconds{user_name="carol"} 864000
spur_karma_walltime_actual_seconds{user_name="carol"} 4860
spur_karma_idle_fill_overflow_count{user_name="bob"} 3
spur_karma_gpus_requested_gpus_requested{user_name="alice"} 80
```

### 7.2 Computed sub-scores (from Prometheus recording rules)

| Sub-score | alice | bob | carol | Interpretation |
|---|---|---|---|---|
| `karma:reliability` | **0.800** | **0.462** | **0.778** | alice: 8/10 completed. bob: 6/13 (5 failed, 1 OOM, 1 timeout). carol: 7/9 (node_fail excluded) |
| `karma:gpu_utilization` | 0.500 | 0.500 | 0.500 | Default — no DME GPU data in test stack |
| `karma:resource_accuracy` | 0.500 | 0.500 | 0.500 | Default — no DME GPU data in test stack |
| `karma:walltime_accuracy` | **0.663** | **0.283** | **0.006** | alice: ran 75% of requested. bob: ran 28%. carol: ran 0.6% (requested 24h, ran 10min) |
| `karma:citizenship` | **1.000** | **0.833** | **1.000** | bob: 3/18 jobs used borrowed capacity |
| `karma:cancellation_score` | **1.000** | **0.722** | **1.000** | bob: cancelled 5/18 = 28% |

### 7.3 Composite karma scores

| User | Score | Assessment |
|---|---|---|
| **alice** | **0.691** | Good citizen. Moderate reliability drag (2 failures). Good wall-time planning. |
| **bob** | **0.530** | Bad citizen. Low reliability (46%), overflow borrows, cancellations, bad wall-time. Diagnosable: every sub-score tells part of the story. |
| **carol** | **0.620** | Moderate. Good reliability and citizenship, but terrible wall-time accuracy is the single clear outlier (0.006). Fix: profile job runtimes before setting time limits. |

### 7.4 Worked example: bob's composite

```
0.25 × 0.462 (reliability)        = 0.116
0.25 × 0.500 (gpu_util, default)  = 0.125
0.20 × 0.500 (resource, default)  = 0.100
0.15 × 0.833 (citizenship)        = 0.125
0.10 × 0.283 (walltime)           = 0.028
0.05 × 0.722 (cancellation)       = 0.036
                                     ─────
                            TOTAL  = 0.530
```

---

## 8. The 6th Dimension: GPU Utilization

GPU utilization and resource accuracy (dimensions 2 & 3, 45% weight combined) require data from the Device Metrics Exporter (DME), not from Spur's accounting DB. The DME exports:

```
amd_gpu_gfx_activity{hostname="node01", gpu_id="0", job_user="alice", job_id="12345"} 85.2
```

### How job_user gets populated

The DME doesn't scan processes or cgroups. It watches `/var/run/exporter/<gpu_id>` for JSON files written by a **Slurm prolog script**:

```
Slurm/Spur prolog → writes /var/run/exporter/0 with {"SLURM_JOB_USER":"alice",...}
DME exporter      → reads JSON via fsnotify → populates job_user label on GPU metrics
Slurm/Spur epilog → removes /var/run/exporter/0 on job exit
```

### What's needed for Spur

Spur needs a prolog hook that writes the same JSON format. Spur already has prolog/epilog hook support — the hook would be ~30 lines of shell:

```bash
#!/bin/bash
# spur-karma-prolog.sh — writes GPU assignment for DME exporter
for gpu in ${SPUR_JOB_GPUS//,/ }; do
  cat > /var/run/exporter/$gpu <<EOF
{"SLURM_JOB_ID":"$SPUR_JOB_ID","SLURM_JOB_USER":"$SPUR_JOB_USER",
 "SLURM_JOB_PARTITION":"$SPUR_JOB_PARTITION","CUDA_VISIBLE_DEVICES":"$gpu"}
EOF
done
```

**Status:** Not implemented. The prolog hook is the remaining piece for GPU-aware karma scoring. Without it, GPU utilization and resource accuracy default to 0.5 (neutral) in the composite.

### Alternative: `spur_job_gpu_assignment` gauge

The design doc proposed a Prometheus gauge `spur_job_gpu_assignment{username, node, gpu_id} = 1` as a PromQL join key. This works but:
- Requires PromQL `group_left` joins between Spur and DME metrics
- Label mismatch: DME uses `hostname`, Spur would use `node` — needs `label_replace()`
- More fragile than the prolog hook approach

**Recommendation:** The prolog hook is simpler and more robust.

---

## 9. Production Deployment

### Prerequisites

1. Spur with accounting enabled (`[accounting].database_url` set)
2. Spur built from `user/bhatturu/karma-time-limit-min` branch (for `time_limit_min` + `total_gpus`)
3. `postgres_exporter` deployed with access to Spur's accounting DB
4. (Optional) DME exporter with Spur prolog hook for GPU utilization

### Steps

1. **Deploy postgres_exporter** pointed at Spur's accounting Postgres:
   ```bash
   docker run -d --name karma-exporter \
     -e DATA_SOURCE_NAME="postgresql://spur:spur@<postgres-host>:5432/spur?sslmode=disable" \
     -p 9187:9187 \
     -v /etc/spur/karma-queries.yaml:/queries.yaml \
     quay.io/prometheuscommunity/postgres-exporter:v0.16.0 \
     --extend.query-path=/queries.yaml
   ```

2. **Copy config files:**
   - `queries.yaml` → `/etc/spur/karma-queries.yaml`
   - `rules.yaml` → `/etc/prometheus/karma-rules.yaml`

3. **Add to Prometheus config:**
   ```yaml
   scrape_configs:
     - job_name: 'spur-karma'
       scrape_interval: 5m
       static_configs:
         - targets: ['<exporter-host>:9187']

   rule_files:
     - /etc/prometheus/karma-rules.yaml
   ```

4. **Build Grafana dashboard** querying:
   - `karma:score{user_name=~".+"}` — composite per user
   - `karma:reliability`, `karma:citizenship`, etc. — sub-score breakdown
   - `spur_karma_jobs_by_state_job_count` — raw job counts

---

## 10. Verification Commands

```bash
# Start the test stack
cd ~/src/spur/deploy/karma
docker compose up -d

# Wait 60s for scrape + eval cycle, then:

# 1. Check Postgres seed data
docker exec karma-postgres-1 psql -U spur -c \
  "SELECT user_name, state, count(*) FROM jobs GROUP BY 1,2 ORDER BY 1,2"

# 2. Check postgres_exporter raw metrics
curl -s http://localhost:9187/metrics | grep "^spur_karma"

# 3. Check Prometheus scrape target health
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import sys,json
for t in json.load(sys.stdin)['data']['activeTargets']:
    print(f\"{t['labels']['job']}: {t['health']}\")"

# 4. Check recording rules evaluation
curl -s http://localhost:9090/api/v1/rules | python3 -c "
import sys,json
for g in json.load(sys.stdin)['data']['groups']:
    print(f'Group: {g[\"name\"]}')
    for r in g['rules']:
        print(f'  {r[\"name\"]}: health={r[\"health\"]}')"

# 5. Query all sub-scores
for m in karma:reliability karma:citizenship karma:walltime_accuracy \
         karma:cancellation_score karma:score; do
  echo "=== $m ==="
  curl -s "http://localhost:9090/api/v1/query?query=$m" | python3 -c "
import sys,json
for r in json.load(sys.stdin)['data']['result']:
    print(f\"  {r['metric'].get('user_name','?')}: {float(r['value'][1]):.3f}\")"
done

# 6. Prometheus UI (browser)
# Open http://localhost:9090, Graph tab, type: karma:score

# Tear down
docker compose down
```

---

## 11. Summary

| Question | Answer |
|---|---|
| Are new Spur metrics needed? | **No** — 8 of 10 data points already existed in the accounting DB |
| What Spur code changes were needed? | 2 column fixes: `time_limit_min` (1-line bind) + `total_gpus` (new column) |
| How does the data reach Prometheus? | `postgres_exporter` runs SQL queries against the accounting DB every 30s |
| How are sub-scores computed? | Prometheus recording rules (PromQL formulas in `rules.yaml`) |
| How does the composite work? | Weighted sum of 6 sub-scores (weights from design doc) |
| What about GPU utilization? | Needs DME exporter + Spur prolog hook (not yet implemented, defaults to 0.5) |
| Can weights be tuned? | Yes — edit `rules.yaml`, no Spur code change needed |
| Is it retroactive? | Yes — queries existing historical data, not just forward from deployment |
| Where are the files? | `/home/AMD/bhatturu/src/spur/deploy/karma/` |
| Where is the branch? | `user/bhatturu/karma-time-limit-min` on `bhatturu/spur` (3 commits) |
