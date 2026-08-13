-- 01_create_tables.sql
-- Loads the three raw CSVs (data/raw/) into typed DuckDB tables.

-- Run with:  duckdb age_restricted_sales.duckdb -c ".read sql/01_create_tables.sql"
-- (paths are relative to the repo root)

CREATE OR REPLACE TABLE shop_dimensions AS
SELECT
    LPAD(store_number, 3, '0') AS store_number, -- enforce (rather than just preserve) leading 0s/3 character format
        -- note: 4-digit store nums will break (trunc from right) - ok as existing format is used consistently
    shop_name,
    region,
    format
FROM read_csv('data/raw/shop_dimensions.csv', header = true, all_varchar = true, nullstr = ['']);


CREATE OR REPLACE TABLE transactions AS
SELECT
    transaction_id,
    -- CAST used throughout rather than shorter `::` syntax to ensure universal portability
    LPAD(store_number, 3, '0') AS store_number,
    CAST(transaction_date AS DATE) AS transaction_date,
    CAST(transaction_time AS TIME) AS transaction_time,
    CAST((transaction_date || ' ' || transaction_time) AS TIMESTAMP) AS transaction_datetime,
    user_id,
    category,
    CAST(id_check_complete AS BOOLEAN) AS id_check_complete,
    CAST(id_check_passed AS BOOLEAN) AS id_check_passed -- nullstr param (.read_csv() function below) handles empty strings
FROM read_csv('data/raw/transactions.csv', header = true, all_varchar = true, nullstr = ['']);


CREATE OR REPLACE TABLE test_purchases AS
SELECT
    test_purchase_id,
    LPAD(store_number, 3, '0') AS store_number,
    CAST(test_purchase_date AS DATE) AS test_purchase_date,
    CAST(test_purchase_time AS TIME) AS test_purchase_time,
    CAST((test_purchase_date || ' ' || test_purchase_time) AS TIMESTAMP) AS test_purchase_datetime,
    user_id,
    category,
    CAST(test_purchase_pass AS BOOLEAN) AS test_purchase_pass
FROM read_csv('data/raw/test_purchases.csv', header = true, all_varchar = true, nullstr = ['']);


-- sanity check after loading: row counts (should match the source CSVs)
-- with a count of checks completed count, orphaned stores
SELECT 'shop_dimensions' AS table_name, COUNT(*) AS row_count FROM shop_dimensions
UNION ALL
SELECT 'transactions', COUNT(*) FROM transactions
UNION ALL
SELECT '  -> check rows', COUNT(*) FROM transactions WHERE id_check_complete
UNION ALL
SELECT '  -> orphaned stores', COUNT(*) 
FROM transactions t 
WHERE NOT EXISTS (SELECT 1 FROM shop_dimensions s WHERE s.store_number = t.store_number)
UNION ALL
SELECT 'test_purchases', COUNT(*) FROM test_purchases;