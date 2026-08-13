-- 03_shop_performance_summary.sql

-- creates an aggregate view for export
-- Shop-level rollup (one row per shop) for a headline scorecard/map view
-- also serves as shop dimension table, containing shop name, region, format
-- this view is therefore to be used as the base table in the Tableau data pane


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