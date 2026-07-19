-- 02_training_flags.sql
-- creates a 'training flags' table based on user behaviour / history
-- Depends on 01_create_tables.sql having already been run.


-- Signal 1: check-rate outlier (very low OR very high id_check_complete rate)
-- Uses estate-wide 5th/85th percentiles and hardcoded cutoffs in config
-- users with < 10 transactions are not scored

CREATE OR REPLACE VIEW user_check_rate_stats AS
SELECT
    store_number,
    user_id,
    COUNT(*) AS total_transactions,
    AVG(id_check_complete::INTEGER) AS check_complete_rate
FROM transactions
GROUP BY store_number, user_id;


CREATE OR REPLACE VIEW user_check_rate_flags AS
-- hardcoded values set below:
WITH config AS (
    SELECT 
        0.05 AS low_floor,
        0.50 AS high_ceiling,
        10 AS min_tx -- sample size protection
),
bounds AS (
    SELECT
        GREATEST(quantile_cont(s.check_complete_rate, 0.05), c.low_floor) AS low_cutoff,
        LEAST(quantile_cont(s.check_complete_rate, 0.85), c.high_ceiling) AS high_cutoff
    FROM user_check_rate_stats s
    CROSS JOIN config c
    WHERE s.total_transactions >= c.min_tx
    GROUP BY c.low_floor, c.high_ceiling
)
SELECT
    s.store_number,
    s.user_id,
    s.total_transactions,
    s.check_complete_rate,
    b.low_cutoff,
    b.high_cutoff,
    CASE
        WHEN s.total_transactions < c.min_tx THEN 'Unscored - low volume'
        WHEN s.check_complete_rate <= b.low_cutoff THEN 'Very low - rarely checking ID'
        WHEN s.check_complete_rate >= b.high_cutoff THEN 'Very high - checking almost everyone'
        ELSE 'Normal'
    END AS check_rate_flag
FROM user_check_rate_stats s
CROSS JOIN bounds b
CROSS JOIN config c;


-- Signal 2: pass-rate outlier (low or very high pass rates)
-- uses hardcoded thresholds only (no estate impact)
-- dynamic sample size protection added for low vs. high pass rate

CREATE OR REPLACE VIEW user_pass_rate_flags AS
-- hardcoded values set below:
WITH config AS (
    SELECT 0.8 AS low_pass_rate, 0.95 AS high_pass_rate, 5 AS min_tx, 30 AS min_tx_high_pass
),
raw_stats AS (
    SELECT
        t.store_number,
        t.user_id,
        COUNT(*) FILTER (WHERE t.id_check_complete) AS checks_completed,
        AVG(t.id_check_passed::INTEGER) FILTER (WHERE t.id_check_complete) AS check_pass_rate
    FROM transactions t
    GROUP BY t.store_number, t.user_id
    HAVING COUNT(*) FILTER (WHERE t.id_check_complete) > 0
)
SELECT
    s.*,
    c.low_pass_rate,
    c.high_pass_rate,
    CASE
        WHEN s.checks_completed <= c.min_tx THEN 'Unscored - low volume'
        WHEN s.check_pass_rate < c.low_pass_rate THEN 'Low pass rate - possible mislogging'
        WHEN s.check_pass_rate >= c.high_pass_rate AND s.checks_completed >= c.min_tx_high_pass THEN 'High pass rate'
        ELSE 'Normal'
    END AS pass_rate_flag
FROM raw_stats s
CROSS JOIN config c;


-- Signal 3: recent test-purchase fail 
-- within the last 90 days of most recent transaction date
-- logic can be updated in WHERE clause

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
    date_diff('day', tp.test_purchase_date::DATE, r.today::DATE) AS days_since_fail
FROM test_purchases tp
CROSS JOIN reference_date r
WHERE tp.test_purchase_pass = FALSE
  AND tp.test_purchase_date >= r.today - INTERVAL 90 DAY; -- time window set here


-- Signal 4: category-level check-rate 

CREATE OR REPLACE VIEW user_category_check_rate_stats AS
SELECT
    t.store_number,
    t.user_id,
    t.category,
    COUNT(*) AS category_transactions,
    AVG(t.id_check_complete::INTEGER) AS category_check_rate,
    s.check_complete_rate AS baseline_check_rate
FROM transactions t
JOIN user_check_rate_stats s USING (store_number, user_id)
GROUP BY t.store_number, t.user_id, t.category, s.check_complete_rate;


CREATE OR REPLACE VIEW user_category_check_rate_flags AS
-- hardcoded values set below:
WITH config AS (
    SELECT 5 AS min_tx, 0.15 AS gap_threshold -- 15 percentage points vs own baseline
)
SELECT
    s.store_number,
    s.user_id,
    s.category,
    s.category_transactions,
    s.category_check_rate,
    s.baseline_check_rate,
    ROUND(s.baseline_check_rate - s.category_check_rate, 4) AS gap_vs_baseline,
    CASE
        WHEN s.category_transactions < c.min_tx THEN 'Unscored - low volume'
        WHEN (s.baseline_check_rate - s.category_check_rate) >= c.gap_threshold THEN 'Low - below own baseline'
        WHEN (s.category_check_rate - s.baseline_check_rate) >= c.gap_threshold THEN 'High - above own baseline'
        ELSE 'Normal'
    END AS category_check_rate_flag
FROM user_category_check_rate_stats s
CROSS JOIN config c;


-- Consolidated view: one row per user, all signals side by side.
-- the resulting output is Tableau-ready
CREATE OR REPLACE VIEW training_flags AS
SELECT
    COALESCE(c.store_number, p.store_number) AS store_number,
    COALESCE(c.user_id, p.user_id) AS user_id,
    c.total_transactions,
    ROUND(c.check_complete_rate, 4) AS check_complete_rate,
    c.check_rate_flag,
    COALESCE(p.checks_completed, 0) AS checks_completed,
    ROUND(p.check_pass_rate, 4)     AS check_pass_rate,
    COALESCE(p.pass_rate_flag, 'Unscored - low volume') AS pass_rate_flag,
    EXISTS (
        SELECT 1 FROM recent_test_purchase_fails f
        WHERE f.user_id = COALESCE(c.user_id, p.user_id)
    ) AS has_recent_test_purchase_fail,
    -- Signal 4 rollup -- restricted to the "Low" direction
    EXISTS (
        SELECT 1 FROM user_category_check_rate_flags g
        WHERE g.user_id = COALESCE(c.user_id, p.user_id)
          AND g.category_check_rate_flag = 'Low - below own baseline'
    ) AS has_category_check_issue,
    (
        SELECT string_agg(g.category, ', ')
        FROM user_category_check_rate_flags g
        WHERE g.user_id = COALESCE(c.user_id, p.user_id)
          AND g.category_check_rate_flag = 'Low - below own baseline'
    ) AS flagged_categories
FROM user_check_rate_flags c
FULL OUTER JOIN user_pass_rate_flags p USING (store_number, user_id);


-- Sanity check counts:
SELECT
    COUNT(*) FILTER (WHERE check_rate_flag IN('Very low - rarely checking ID', 'Very high - checking almost everyone')) AS check_rate_flags,
    COUNT(*) FILTER (WHERE pass_rate_flag IN('Low pass rate - possible mislogging', 'High pass rate'))  AS pass_rate_flags,
    COUNT(*) FILTER (WHERE has_recent_test_purchase_fail) AS recent_fail_flags,
    COUNT(*) FILTER (WHERE has_category_check_issue) AS category_check_flags,
    COUNT(*) AS total_users
FROM training_flags;