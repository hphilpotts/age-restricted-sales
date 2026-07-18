-- 03_shop_performance_summary.sql
-- Powers the "historical performance insights" side of the dashboard:
-- pass rate by shop, category, day of week, and time-of-day band, sourced
-- from the test-purchase (audit) data. Depends on 01_create_tables.sql.

CREATE OR REPLACE VIEW shop_category_performance AS
SELECT
    sd.store_number,
    sd.shop_name,
    sd.region,
    sd.format,
    tp.category,
    dayname(tp.test_purchase_date) AS day_of_week,
    CASE
        WHEN EXTRACT(HOUR FROM tp.test_purchase_datetime) BETWEEN 8 AND 11  THEN 'Morning (08-12)'
        WHEN EXTRACT(HOUR FROM tp.test_purchase_datetime) BETWEEN 12 AND 16 THEN 'Afternoon (12-17)'
        WHEN EXTRACT(HOUR FROM tp.test_purchase_datetime) BETWEEN 17 AND 19 THEN 'Early evening (17-20)'
        ELSE 'Late evening (20-22)'
    END AS time_of_day_band,
    COUNT(*) AS test_purchases,
    AVG(CASE WHEN tp.test_purchase_pass THEN 1.0 ELSE 0.0 END) AS pass_rate
FROM test_purchases tp
JOIN shop_dimensions sd USING (store_number)
GROUP BY sd.store_number, sd.shop_name, sd.region, sd.format,
         tp.category, day_of_week, time_of_day_band;

-- Shop-level rollup (one row per shop) for a headline scorecard/map view
CREATE OR REPLACE VIEW shop_overall_performance AS
SELECT
    sd.store_number,
    sd.shop_name,
    sd.region,
    sd.format,
    COUNT(*) AS test_purchases,
    AVG(CASE WHEN tp.test_purchase_pass THEN 1.0 ELSE 0.0 END) AS pass_rate
FROM test_purchases tp
JOIN shop_dimensions sd USING (store_number)
GROUP BY sd.store_number, sd.shop_name, sd.region, sd.format;