#!/usr/bin/env bash
# Runs the full DuckDB pipeline end-to-end: loads raw CSVs, builds the
# training-flag and performance views, then exports modeled CSVs for Tableau.
#
# Usage (from repo root):  bash scripts/run_pipeline.sh

set -e

DB="age_restricted_sales.duckdb"

echo "Loading raw tables..."
duckdb "$DB" -c ".read sql/01_create_tables.sql"

echo "Building training-flag views..."
duckdb "$DB" -c ".read sql/02_training_flags.sql"

echo "Building shop performance views..."
duckdb "$DB" -c ".read sql/03_shop_performance_summary.sql"

echo "Exporting modeled CSVs for Tableau..."
duckdb "$DB" -c ".read sql/04_export_for_tableau.sql"

echo "Done. Modeled CSVs are in data/modeled/ -- point Tableau at these."