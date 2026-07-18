-- 02_training_flags.sql
-- Builds the three "potential training issue" signals from the project
-- brief, all keyed on user_id (+ store_number so they can be grouped or
-- filtered by shop in Tableau). Depends on 01_create_tables.sql having
-- already been run.

-- Signal 1: check-rate outlier (very low OR very high id_check_complete rate)
-- Uses estate-wide 5th/85th percentiles rather than a hardcoded cutoff, so
-- the threshold self-adjusts if the data is regenerated.
CREATE OR REPLACE VIEW user_check_rate_stats AS
SELECT
    store_number,
    user_id,
    COUNT(*) AS total_transactions,
    AVG(CASE WHEN id_check_complete THEN 1.0 ELSE 0.0 END) AS check_complete_rate
FROM transactions
GROUP BY store_number, user_id;

CREATE OR REPLACE VIEW user_check_rate_flags AS
WITH bounds AS (
    SELECT
        quantile_cont(check_complete_rate, 0.05) AS low_cutoff,
        quantile_cont(check_complete_rate, 0.85) AS high_cutoff
    FROM user_check_rate_stats
)
SELECT
    s.store_number,
    s.user_id,
    s.total_transactions,
    s.check_complete_rate,
    b.low_cutoff,
    b.high_cutoff,
    CASE
        WHEN s.check_complete_rate <= b.low_cutoff  THEN 'Very low - rarely checking ID'
        WHEN s.check_complete_rate >= b.high_cutoff THEN 'Very high - checking almost everyone'
        ELSE NULL
    END AS check_rate_flag
FROM user_check_rate_stats s
CROSS JOIN bounds b;

-- Signal 2: pass-rate concern (of checks completed, <80% pass -> possible
-- mislogging rather than genuine refusals -- see project background notes)
CREATE OR REPLACE VIEW user_pass_rate_flags AS
SELECT
    store_number,
    user_id,
    COUNT(*) FILTER (WHERE id_check_complete) AS checks_completed,
    AVG(CASE WHEN id_check_passed THEN 1.0 ELSE 0.0 END)
        FILTER (WHERE id_check_complete) AS check_pass_rate,
    CASE
        WHEN AVG(CASE WHEN id_check_passed THEN 1.0 ELSE 0.0 END)
             FILTER (WHERE id_check_complete) < 0.80
        THEN 'Low pass rate - possible mislogging'
        ELSE NULL
    END AS pass_rate_flag
FROM transactions
GROUP BY store_number, user_id
HAVING COUNT(*) FILTER (WHERE id_check_complete) > 0;

-- Signal 3: recent test-purchase fail (failed within the last 90 days of
-- the dataset's most recent transaction date)
CREATE OR REPLACE VIEW recent_test_purchase_fails AS
WITH reference_date AS (
    SELECT MAX(transaction_date) AS today FROM transactions
)
SELECT
    tp.store_number,
    tp.user_id,
    tp.test_purchase_id,
    tp.test_purchase_date,
    tp.category,
    r.today - tp.test_purchase_date AS days_since_fail
FROM test_purchases tp
CROSS JOIN reference_date r
WHERE tp.test_purchase_pass = FALSE
  AND tp.test_purchase_date >= r.today - INTERVAL 90 DAY;

-- Consolidated view: one row per user, all three signals side by side.
-- This is the table the Tableau "Training Needs" worksheet should read from.
CREATE OR REPLACE VIEW training_flags AS
SELECT
    COALESCE(c.store_number, p.store_number) AS store_number,
    COALESCE(c.user_id, p.user_id)           AS user_id,
    c.total_transactions,
    c.check_complete_rate,
    c.check_rate_flag,
    p.checks_completed,
    p.check_pass_rate,
    p.pass_rate_flag,
    EXISTS (
        SELECT 1 FROM recent_test_purchase_fails f
        WHERE f.user_id = COALESCE(c.user_id, p.user_id)
    ) AS has_recent_test_purchase_fail
FROM user_check_rate_flags c
FULL OUTER JOIN user_pass_rate_flags p USING (store_number, user_id);

-- Sanity check counts -- see the README for expected ballpark figures
SELECT
    COUNT(*) FILTER (WHERE check_rate_flag IS NOT NULL) AS check_rate_flags,
    COUNT(*) FILTER (WHERE pass_rate_flag IS NOT NULL)  AS pass_rate_flags,
    COUNT(*) FILTER (WHERE has_recent_test_purchase_fail) AS recent_fail_flags,
    COUNT(*) AS total_users
FROM training_flags;