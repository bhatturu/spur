-- Seed data for karma score testing.
-- Creates 3 users with distinct karma profiles over the last 30 days.

CREATE TABLE IF NOT EXISTS jobs (
    job_id          BIGINT PRIMARY KEY,
    name            TEXT NOT NULL DEFAULT '',
    user_name       TEXT NOT NULL,
    uid             INTEGER NOT NULL DEFAULT 0,
    account         TEXT NOT NULL DEFAULT '',
    partition_name  TEXT NOT NULL DEFAULT '',
    qos             TEXT NOT NULL DEFAULT '',
    state           TEXT NOT NULL DEFAULT 'PENDING',
    exit_code       INTEGER NOT NULL DEFAULT 0,
    exit_signal     INTEGER NOT NULL DEFAULT 0,
    derived_exit_code INTEGER NOT NULL DEFAULT 0,
    num_nodes       INTEGER NOT NULL DEFAULT 1,
    num_tasks       INTEGER NOT NULL DEFAULT 1,
    cpus_per_task   INTEGER NOT NULL DEFAULT 1,
    memory_mb       BIGINT NOT NULL DEFAULT 0,
    nodelist        TEXT NOT NULL DEFAULT '',
    submit_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    start_time      TIMESTAMPTZ,
    end_time        TIMESTAMPTZ,
    time_limit_min  INTEGER,
    work_dir        TEXT NOT NULL DEFAULT '',
    script_hash     TEXT NOT NULL DEFAULT '',
    reservation     TEXT NOT NULL DEFAULT '',
    preempted_by    BIGINT,
    preempt_mode    TEXT NOT NULL DEFAULT '',
    preempt_qos     TEXT NOT NULL DEFAULT '',
    idle_fill       BOOLEAN NOT NULL DEFAULT FALSE,
    total_gpus      INTEGER NOT NULL DEFAULT 0
);

-- ============================================================
-- alice: Good citizen — high reliability, good wall-time accuracy, no overflow
-- Expected karma ~0.85+
-- ============================================================
INSERT INTO jobs (job_id, user_name, account, qos, state, total_gpus, time_limit_min, idle_fill,
                  submit_time, start_time, end_time) VALUES
-- 18 completed jobs, 8 GPUs each, 60-min limit, ran ~45min
(1001, 'alice', 'research', 'normal', 'COMPLETED', 8, 60, false,
 NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days' + INTERVAL '45 minutes'),
(1002, 'alice', 'research', 'normal', 'COMPLETED', 8, 60, false,
 NOW() - INTERVAL '9 days', NOW() - INTERVAL '9 days', NOW() - INTERVAL '9 days' + INTERVAL '50 minutes'),
(1003, 'alice', 'research', 'normal', 'COMPLETED', 8, 60, false,
 NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days' + INTERVAL '42 minutes'),
(1004, 'alice', 'research', 'normal', 'COMPLETED', 8, 60, false,
 NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days' + INTERVAL '55 minutes'),
(1005, 'alice', 'research', 'normal', 'COMPLETED', 8, 60, false,
 NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days' + INTERVAL '48 minutes'),
(1006, 'alice', 'research', 'normal', 'COMPLETED', 8, 60, false,
 NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days' + INTERVAL '52 minutes'),
(1007, 'alice', 'research', 'normal', 'COMPLETED', 8, 60, false,
 NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days' + INTERVAL '47 minutes'),
(1008, 'alice', 'research', 'normal', 'COMPLETED', 8, 60, false,
 NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days' + INTERVAL '51 minutes'),
-- 2 failed (10% failure rate)
(1009, 'alice', 'research', 'normal', 'FAILED', 8, 60, false,
 NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days' + INTERVAL '5 minutes'),
(1010, 'alice', 'research', 'normal', 'FAILED', 8, 60, false,
 NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '3 minutes');

-- ============================================================
-- bob: Bad citizen — high failure rate, many cancellations, overflow borrower
-- Expected karma ~0.35
-- ============================================================
INSERT INTO jobs (job_id, user_name, account, qos, state, total_gpus, time_limit_min, idle_fill,
                  submit_time, start_time, end_time) VALUES
-- 3 completed
(2001, 'bob', 'training', 'normal', 'COMPLETED', 4, 120, false,
 NOW() - INTERVAL '15 days', NOW() - INTERVAL '15 days', NOW() - INTERVAL '15 days' + INTERVAL '90 minutes'),
(2002, 'bob', 'training', 'normal', 'COMPLETED', 4, 120, false,
 NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days' + INTERVAL '80 minutes'),
(2003, 'bob', 'training', 'normal', 'COMPLETED', 4, 120, false,
 NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days' + INTERVAL '100 minutes'),
-- 7 failed (70% failure rate!)
(2004, 'bob', 'training', 'normal', 'FAILED', 4, 120, false,
 NOW() - INTERVAL '9 days', NOW() - INTERVAL '9 days', NOW() - INTERVAL '9 days' + INTERVAL '2 minutes'),
(2005, 'bob', 'training', 'normal', 'FAILED', 4, 120, false,
 NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days' + INTERVAL '1 minute'),
(2006, 'bob', 'training', 'normal', 'FAILED', 4, 120, false,
 NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days' + INTERVAL '3 minutes'),
(2007, 'bob', 'training', 'normal', 'OUT_OF_MEMORY', 4, 120, false,
 NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days' + INTERVAL '10 minutes'),
(2008, 'bob', 'training', 'normal', 'TIMEOUT', 4, 120, false,
 NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days' + INTERVAL '120 minutes'),
(2009, 'bob', 'training', 'normal', 'FAILED', 4, 120, false,
 NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days' + INTERVAL '5 minutes'),
(2010, 'bob', 'training', 'normal', 'FAILED', 4, 120, false,
 NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days' + INTERVAL '4 minutes'),
-- 5 cancelled (speculative submission)
(2011, 'bob', 'training', 'normal', 'CANCELLED', 4, 120, false,
 NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days' + INTERVAL '1 minute'),
(2012, 'bob', 'training', 'normal', 'CANCELLED', 4, 120, false,
 NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days' + INTERVAL '0 minutes'),
(2013, 'bob', 'training', 'normal', 'CANCELLED', 4, 120, false,
 NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '0 minutes'),
(2014, 'bob', 'training', 'normal', 'CANCELLED', 4, 120, false,
 NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '0 minutes'),
(2015, 'bob', 'training', 'normal', 'CANCELLED', 4, 120, false,
 NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '0 minutes'),
-- 3 overflow borrows (idle_fill=true)
(2016, 'bob', 'training', 'normal', 'COMPLETED', 4, 120, true,
 NOW() - INTERVAL '14 days', NOW() - INTERVAL '14 days', NOW() - INTERVAL '14 days' + INTERVAL '60 minutes'),
(2017, 'bob', 'training', 'normal', 'COMPLETED', 4, 120, true,
 NOW() - INTERVAL '11 days', NOW() - INTERVAL '11 days', NOW() - INTERVAL '11 days' + INTERVAL '70 minutes'),
(2018, 'bob', 'training', 'normal', 'COMPLETED', 4, 120, true,
 NOW() - INTERVAL '13 days', NOW() - INTERVAL '13 days', NOW() - INTERVAL '13 days' + INTERVAL '65 minutes');

-- ============================================================
-- carol: Moderate — decent reliability but bad wall-time estimates
-- Expected karma ~0.55
-- ============================================================
INSERT INTO jobs (job_id, user_name, account, qos, state, total_gpus, time_limit_min, idle_fill,
                  submit_time, start_time, end_time) VALUES
-- 7 completed, but wall time way off (requested 24h, ran 10min)
(3001, 'carol', 'inference', 'normal', 'COMPLETED', 2, 1440, false,
 NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days' + INTERVAL '10 minutes'),
(3002, 'carol', 'inference', 'normal', 'COMPLETED', 2, 1440, false,
 NOW() - INTERVAL '9 days', NOW() - INTERVAL '9 days', NOW() - INTERVAL '9 days' + INTERVAL '12 minutes'),
(3003, 'carol', 'inference', 'normal', 'COMPLETED', 2, 1440, false,
 NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days' + INTERVAL '8 minutes'),
(3004, 'carol', 'inference', 'normal', 'COMPLETED', 2, 1440, false,
 NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days' + INTERVAL '15 minutes'),
(3005, 'carol', 'inference', 'normal', 'COMPLETED', 2, 1440, false,
 NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days' + INTERVAL '11 minutes'),
(3006, 'carol', 'inference', 'normal', 'COMPLETED', 2, 1440, false,
 NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days' + INTERVAL '9 minutes'),
(3007, 'carol', 'inference', 'normal', 'COMPLETED', 2, 1440, false,
 NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days' + INTERVAL '13 minutes'),
-- 2 failed, 1 node_fail (excluded from reliability)
(3008, 'carol', 'inference', 'normal', 'FAILED', 2, 1440, false,
 NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days' + INTERVAL '2 minutes'),
(3009, 'carol', 'inference', 'normal', 'FAILED', 2, 1440, false,
 NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days' + INTERVAL '1 minute'),
(3010, 'carol', 'inference', 'normal', 'NODE_FAIL', 2, 1440, false,
 NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '0 minutes');
