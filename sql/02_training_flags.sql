-- 02_training_flags.sql
-- creates a 'training flags' table based on user behaviour / history
-- Depends on 01_create_tables.sql having already been run.


-- overall file strucure is to assemble a view capturing each signal
-- config CTEs (where used) set threshold / sample size values per signal
-- final view training_flags knits together the 4 signals into one view
-- ensures 1 row per user seen in the raw transactions data

-- Signals captured are:
-- 1 Check-rate Outlier (high/low, vs. estate with floor & ceiling values)
-- 2 Pass-rate Outlier (hard values, with dynamic low/high flag sample size filters)
-- 3 Recent Test Purchase Fail (interval threshold set in WHERE clause)
-- 4 Category-level check-rate Outlier (high/low by category, vs. user's baseline & absolute floor)



-- Signal 1: check-rate outlier (very low OR very high id_check_complete rate)
-- Uses estate-wide 5th/85th percentiles, with hardcoded cutoffs in config CTE
-- users with < 10 transactions are not scored

-- build average check rate view:
CREATE OR REPLACE VIEW user_check_rate_stats AS
SELECT
    store_number,
    user_id,
    COUNT(*) AS total_transactions,
    AVG(id_check_complete::INTEGER) AS check_complete_rate
FROM transactions
GROUP BY store_number, user_id;

-- assign overall check rate training flags:
CREATE OR REPLACE VIEW user_check_rate_flags AS
-- hardcoded values set below:
WITH config AS (
    SELECT 
        -- absolute high/low cutoffs (override extreme estate quantiles values)
        0.05 AS low_floor,
        0.50 AS high_ceiling,
        -- sample size protection (smaller than this is too noisy)
        10 AS min_tx
),
-- set cutoffs for high/low flags
bounds AS (
    SELECT
        -- PostgreSQL & Snowflake use PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY s.check_complete_rate)
        GREATEST(quantile_cont(s.check_complete_rate, 0.05), c.low_floor) AS low_cutoff,
        LEAST(quantile_cont(s.check_complete_rate, 0.85), c.high_ceiling) AS high_cutoff
    FROM user_check_rate_stats s
    CROSS JOIN config c
    WHERE s.total_transactions >= c.min_tx
    GROUP BY c.low_floor, c.high_ceiling
)
-- build flags view for Signal 1
SELECT
    s.store_number,
    s.user_id,
    s.total_transactions,
    s.check_complete_rate,
    b.low_cutoff,
    b.high_cutoff,
    CASE
        WHEN s.total_transactions <= c.min_tx THEN 'Unscored - low volume'
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
    SELECT 
        0.8 AS low_pass_rate, 
        0.95 AS high_pass_rate, 
        5 AS min_tx, 
        30 AS min_tx_high_pass -- higher threshold set for high pass rates
            -- lower than this flags too frequently, where user has low number of checks
),
-- get pass rate from TXNs with checks completed
raw_stats AS (
    SELECT
        t.store_number,
        t.user_id,
        COUNT(*) FILTER (WHERE t.id_check_complete) AS checks_completed,
        AVG(CAST(t.id_check_passed AS INTEGER)) FILTER (WHERE t.id_check_complete) AS check_pass_rate
        -- if running in Snowflake, FILTER is not supported, so the above would need:
            -- COUNT(CASE WHEN t.id_check_complete THEN 1 END) AS checks_completed,
            -- AVG(CASE WHEN t.id_check_complete THEN CAST(t.id_check_passed AS INTEGER) END) AS check_pass_rate
    FROM transactions t
    GROUP BY t.store_number, t.user_id
    HAVING COUNT(*) FILTER (WHERE t.id_check_complete) > 0
)
-- build flags view for Signal 2
SELECT
    s.*,
    c.low_pass_rate,
    c.high_pass_rate,
    CASE
        WHEN s.checks_completed <= c.min_tx THEN 'Unscored - low volume'
        WHEN s.check_pass_rate < c.low_pass_rate THEN 'Low pass rate - possible mislogging'
        -- ? possible addition - a second 'Unscored - insufficient volume for High pass rate check'
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
    -- in prod I'd probably just use CURRENT_DATE() in the SELECT
    -- more performant but assumes data is fresh
    SELECT MAX(transaction_date) AS today FROM transactions
)
-- build flags view for Signal 3
SELECT
    tp.store_number,
    tp.user_id,
    tp.test_purchase_id,
    tp.test_purchase_date,
    tp.category,
    date_diff('day', CAST(tp.test_purchase_date AS DATE), CAST(r.today AS DATE)) AS days_since_fail
        -- Snowflake: DATEDIFF(day, [...])
FROM test_purchases tp
CROSS JOIN reference_date r
WHERE tp.test_purchase_pass = FALSE
  AND tp.test_purchase_date >= r.today - INTERVAL 90 DAY; -- time window set here


-- Signal 4: category-level check-rate 
-- compares each category against the user's own baseline check rate
-- intended to target category-specific misunderstanding/issues

-- build category-level check rate view
CREATE OR REPLACE VIEW user_category_check_rate_stats AS
SELECT
    t.store_number,
    t.user_id,
    t.category,
    COUNT(*) AS category_transactions,
    AVG(CAST(t.id_check_complete AS INTEGER)) AS category_check_rate,
    s.check_complete_rate AS baseline_check_rate
FROM transactions t
JOIN user_check_rate_stats s USING (store_number, user_id)
GROUP BY t.store_number, t.user_id, t.category, s.check_complete_rate;

-- assign category check rate training flags:
CREATE OR REPLACE VIEW user_category_check_rate_flags AS
-- hardcoded values set below:
WITH config AS (
    SELECT 
        5 AS min_tx, -- initial scoring filter
        0.15 AS gap_threshold, -- 15 percentage points vs own baseline
        0.0 AS absolute_floor, -- low check rate cutoff, regardless of baselines
        15 AS min_tx_absolute -- filter for scoring against absolute_floor
)
-- build category-level check rate view
SELECT
    s.store_number,
    s.user_id,
    s.category,
    s.category_transactions,
    s.category_check_rate,
    s.baseline_check_rate,
    ROUND(s.baseline_check_rate - s.category_check_rate, 4) AS gap_vs_baseline,
    CASE
        WHEN s.category_transactions <= c.min_tx THEN 'Unscored - low volume'
        WHEN 
            -- compare category pass rate against baseline, flag those with ppts diff at or over threshold
            (s.baseline_check_rate - s.category_check_rate) >= c.gap_threshold 
            OR
            -- compare against absolute floor, flag those at or under absolute threshold, requires larger sample size
            (s.category_check_rate <= c.absolute_floor AND s.category_transactions >= c.min_tx_absolute)
            THEN 'Low - below own baseline'
        WHEN (s.category_check_rate - s.baseline_check_rate) >= c.gap_threshold THEN 'High - above own baseline'
        ELSE 'Normal'
    END AS category_check_rate_flag
FROM user_category_check_rate_stats s
CROSS JOIN config c;


-- Consolidated view: one row per user, all signals side by side.
-- the resulting output is Tableau-ready
CREATE OR REPLACE VIEW training_flags AS
-- reshape Signal 4 (category) into one row per user 
-- input shape: multiple category triggers = multiple rows per user
WITH category_issues AS (
    SELECT
        user_id,
        string_agg(category, ', ') AS flagged_categories -- concatenate multiple categories into one row
        -- Snowflake uses LISTAGG
    FROM user_category_check_rate_flags
    WHERE category_check_rate_flag = 'Low - below own baseline' -- currently limited to Low rate trigger only
    GROUP BY user_id
),
recent_fails AS (
    -- one row per user with a recent fail (Signal 3), same reasoning as above
    SELECT 
        user_id,
        string_agg(category, ', ') AS failed_categories -- concatenate categories
    FROM recent_test_purchase_fails
    GROUP BY user_id
)
-- build flags view for training summary
SELECT
    -- user_check_rate_flags c (Signal 1) has a row for every user with no exclusions
    -- it's therefore a safe anchor for LEFT JOINs
    -- nb: if Signal 1 ever gains its own HAVING/volume-exclusion clause, this assumption breaks...!
    c.store_number,
    c.user_id,
    c.total_transactions,
    -- signal 1
    ROUND(c.check_complete_rate, 4) AS check_complete_rate,
    c.check_rate_flag,
    -- signal 2
    COALESCE(p.checks_completed, 0) AS checks_completed,
    ROUND(p.check_pass_rate, 4) AS check_pass_rate,
    COALESCE(p.pass_rate_flag, 'Unscored - low volume') AS pass_rate_flag, -- in case user is in the TXN dataset but has never checked
    -- signal 3
    rf.user_id IS NOT NULL AS has_recent_test_purchase_fail,
    rf.failed_categories,
    -- signal 4
    ci.flagged_categories IS NOT NULL AS has_category_check_issue,
    ci.flagged_categories
FROM user_check_rate_flags c
LEFT JOIN user_pass_rate_flags p USING (store_number, user_id)
LEFT JOIN category_issues ci USING (user_id)
LEFT JOIN recent_fails rf USING (user_id);


-- Sanity check counts:
SELECT
    COUNT(*) FILTER (WHERE check_rate_flag IN('Very low - rarely checking ID', 'Very high - checking almost everyone')) AS check_rate_flags,
    COUNT(*) FILTER (WHERE pass_rate_flag IN('Low pass rate - possible mislogging', 'High pass rate'))  AS pass_rate_flags,
    COUNT(*) FILTER (WHERE has_recent_test_purchase_fail) AS recent_fail_flags,
    COUNT(*) FILTER (WHERE has_category_check_issue) AS category_check_flags,
    COUNT(*) AS total_users
FROM training_flags;