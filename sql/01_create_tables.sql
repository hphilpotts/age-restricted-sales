-- 01_create_tables.sql
-- Loads the three raw CSVs (data/raw/) into typed DuckDB tables.
--
-- Run with:  duckdb age_restricted_sales.duckdb -c ".read sql/01_create_tables.sql"
-- (paths are relative to the repo root)

CREATE OR REPLACE TABLE shop_dimensions AS
SELECT
    store_number::VARCHAR AS store_number, -- cast to preserve leading 0s & 3 character format
    shop_name,
    region,
    format
FROM read_csv('data/raw/shop_dimensions.csv', header = true, all_varchar = true);


CREATE OR REPLACE TABLE transactions AS
SELECT
    transaction_id,
    store_number::VARCHAR AS store_number,
    transaction_date::DATE AS transaction_date,
    transaction_time AS transaction_time,
    (transaction_date || ' ' || transaction_time)::TIMESTAMP AS transaction_datetime,
    user_id,
    category,
    id_check_complete::BOOLEAN AS id_check_complete,
    CASE
        WHEN id_check_passed IS NULL OR id_check_passed = '' THEN NULL
        ELSE id_check_passed::BOOLEAN
    END AS id_check_passed
FROM read_csv('data/raw/transactions.csv', header = true, all_varchar = true);


CREATE OR REPLACE TABLE test_purchases AS
SELECT
    test_purchase_id,
    store_number::VARCHAR AS store_number,
    test_purchase_date::DATE AS test_purchase_date,
    test_purchase_time AS test_purchase_time,
    (test_purchase_date || ' ' || test_purchase_time)::TIMESTAMP AS test_purchase_datetime,
    user_id,
    category,
    test_purchase_pass::BOOLEAN AS test_purchase_pass
FROM read_csv('data/raw/test_purchases.csv', header = true, all_varchar = true);

-- sanity check after loading: row counts (should match the source CSVs)
-- with a count of Age Restricted Sales (ARS) transaction rows
SELECT 'shop_dimensions' AS table_name, COUNT(*) AS row_count FROM shop_dimensions
UNION ALL
SELECT 'transactions', COUNT(*) FROM transactions
UNION ALL
SELECT '  -> ARS rows', COUNT(*) FROM transactions WHERE id_check_complete
UNION ALL
SELECT 'test_purchases', COUNT(*) FROM test_purchases;