-- 04_test_purchases_processed.sql

-- processes test_purchase data for export
-- time of day bandings added for easier grouping
-- day of week number added for easier sorting


CREATE OR REPLACE VIEW test_purchases_processed AS
SELECT
    store_number,
    test_purchase_id,
    category,
    user_id,
    test_purchase_pass,
    test_purchase_datetime,
    EXTRACT(ISODOW FROM test_purchase_date) AS day_of_week_num, -- easier sorting in Tableau
    dayname(test_purchase_date) AS day_of_week,
    CASE
        WHEN EXTRACT(HOUR FROM test_purchase_datetime) BETWEEN 8 AND 11  THEN 'Morning (08-12)'
        WHEN EXTRACT(HOUR FROM test_purchase_datetime) BETWEEN 12 AND 16 THEN 'Afternoon (12-17)'
        WHEN EXTRACT(HOUR FROM test_purchase_datetime) BETWEEN 17 AND 19 THEN 'Early evening (17-20)'
        WHEN EXTRACT(HOUR FROM test_purchase_datetime) BETWEEN 20 AND 22 THEN 'Late evening (20-22)'
        ELSE 'Outside typical window' -- not in the raw data but a sensible catch-all
    END AS time_of_day_band
FROM test_purchases;