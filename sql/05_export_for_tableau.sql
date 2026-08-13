-- 05_export_for_tableau.sql

-- Exports the modeled views as plain CSVs into data/modeled/
-- allows Tableau Public connection (as simple text-only files)
-- Depends on earlier-ordered files (01_* through 04_*) having run

COPY (SELECT * FROM training_flags)
    TO 'data/modeled/training_flags.csv' (HEADER, DELIMITER ',');

COPY (SELECT * FROM recent_test_purchase_fails)
    TO 'data/modeled/recent_test_purchase_fails.csv' (HEADER, DELIMITER ',');

COPY (SELECT * FROM shop_overall_performance)
    TO 'data/modeled/shop_overall_performance.csv' (HEADER, DELIMITER ',');

COPY (SELECT * FROM test_purchases_processed)
    TO 'data/modeled/test_purchases_processed.csv' (HEADER, DELIMITER ',');