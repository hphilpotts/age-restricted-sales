-- 04_export_for_tableau.sql
-- Exports the modeled views as plain CSVs into data/modeled/, so Tableau
-- (including Tableau Public) can connect via a simple, reliable text-file
-- connection rather than a live DuckDB/JDBC connection. Depends on
-- 01_create_tables.sql, 02_training_flags.sql and
-- 03_shop_performance_summary.sql having already been run.
--
-- Note: these are one-off snapshots. Re-run this whenever the upstream
-- data or logic changes, then refresh the Tableau extract.

COPY (SELECT * FROM shop_category_performance)
    TO 'data/modeled/shop_category_performance.csv' (HEADER, DELIMITER ',');

COPY (SELECT * FROM shop_overall_performance)
    TO 'data/modeled/shop_overall_performance.csv' (HEADER, DELIMITER ',');

COPY (SELECT * FROM training_flags)
    TO 'data/modeled/training_flags.csv' (HEADER, DELIMITER ',');

COPY (SELECT * FROM recent_test_purchase_fails)
    TO 'data/modeled/recent_test_purchase_fails.csv' (HEADER, DELIMITER ',');

-- Category-level detail:
-- Not exported for now
-- Can uncomment to add a per-user, per-category drill-down chart later
-- COPY (SELECT * FROM user_category_check_rate_flags)
--     TO 'data/modeled/user_category_check_rate_flags.csv' (HEADER, DELIMITER ',');