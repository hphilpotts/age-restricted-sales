#!/usr/bin/env bash
# Runs the full DuckDB pipeline end-to-end: loads raw CSVs, builds the
# training-flag and performance views, then exports modeled CSVs for Tableau.
#
# Usage (from repo root):  bash scripts/run_pipeline.sh

set -e

cd "$(dirname "$0")/.."

command -v duckdb >/dev/null 2>&1 || {
    echo "Error: duckdb CLI not found. Install it with: pip install duckdb-cli" >&2
    exit 1
}

DB="age_restricted_sales.duckdb"

echo "Loading raw tables..."
duckdb "$DB" -c ".read sql/01_create_tables.sql"

echo "Building training-flag views..."
duckdb "$DB" -c ".read sql/02_training_flags.sql"

echo "Building shop performance view..."
duckdb "$DB" -c ".read sql/03_shop_performance_summary.sql"

echo "Processing test purchase datetimes..."
duckdb "$DB" -c ".read sql/04_test_purchases_processed.sql"

echo "Exporting modeled CSVs for Tableau..."
duckdb "$DB" -c ".read sql/05_export_for_tableau.sql"

echo "Done. Modeled CSVs are in data/modeled/ - ready for export/ingestion to Tableau."