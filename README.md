# Age-Restricted Sales - Compliance Dashboard

A portfolio project mirroring real-world retail age-verification compliance reporting: historical test-purchase performance at shop level, and a "training needs" signal layer that flags till staff who may need refresher training, based on how consistently and accurately they check ID.  

The business problem this is designed to solve is the largely _reactive_ nature seen when addressing training issues relating to Age-Restricted Sales legislation. Issues are often only found following failed test purchases (_or worse, a full legal breach_), with a high possibility of training issues going undetected (as it is not feasible to test all cashiers on a regular basis).  

By introducing a _predictive_ approach based on user patterns in transaction data, management teams can be provided with actionable insights that allow them to check-in with cashiers that may need additional support, providing training and follow-up that prevents legal breaches/test purchase fails before they occur.  

**[View the Tableau Public dashboard](https://public.tableau.com/views/AgeRestrictedSales/ShopOverview?:language=en-GB&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)**

**All data in this repository is synthetic**, generated from scratch to plausible, realistic distributions - no real employer data, real shop names, or real staff data is used anywhere in this project.   

The project currently covers 30 shops, 533 users, 900 test purchases, c. 158k transactions involving age-restricted items (of which 29k involve ID checks).  

## What this shows

- **Historical performance insights** (shop level): test-purchase pass rate by category, day of week, and time of day. This allows users to identify broad opportunity and issue areas based on actual past performance.  
  
- **Training needs flags** (staff level) - four signals are combined:
  1. **Check-rate Outlier** - a cashier shows unusually low or high ID-check completion rate (based on self-adjusting estate-wide percentile bands, not a fixed cutoff). Excessively high/low values often indicate training needs, mislogging on till POS, or cashier confidence issues.  
  2. **Pass-rate Outlier** - a cashier's ID-check pass rate below 80% or above 95% of checks completed: a likely sign of mislogging rather than a single cashier encountering a large number of genuine refusals (unlikely) or a very low number of customers who are underage or without acceptable ID (again, unlikely).  
  3. **Recent Test Purchase Fail**: a cashier has a failed test purchase within the last 90 days, indicating a clear and persistent need for follow-up training and manager check-ins.  
  4. **Category-level check-rate Outlier** - as with Signal 1 (overall checks), however _category-specific_ training issues are targeted, with check rates compared with the cashier's own baseline. This helps identify category-related training issues, e.g. a misunderstanding of the rules relating to Energy Drinks or Lottery tickets, which might otherwise be obscured through a 'normal' check rate across other categories.  

## Tech stack

- **DuckDB** (SQL) - data modeling: typing/cleaning, the training-flag logic, and the shop performance rollups.  
- **Tableau Public** - the dashboard itself, built from the modeled CSVs.  

## Repo structure

```
.
├── data/
│   ├── raw/                              # source CSVs
│   └── modeled/                          # SQL-generated output, ready for Tableau
├── sql/
│   ├── 01_create_tables.sql              # load + type the raw CSVs
│   ├── 02_training_flags.sql             # capture the four training-flag signals
│   ├── 03_shop_performance_summary.sql   # shop performance aggregate
│   ├── 04_test_purchases_processed.sql   # add time-of-day grouping to test purchases
│   └── 05_export_for_tableau.sql         # exports modeled views as CSVs to data/modeled/
├── scripts/
│   └── run_pipeline.sh                   # runs all 5 SQL scripts in order
└── README.md
```

## Running pipeline

```bash
# 1. Install DuckDB
brew install duckdb
  # (Not on Homebrew? See duckdb.org/docs/installation for other platforms.)

# 2. Run the full DuckDB pipeline (load -> model -> export)
bash scripts/run_pipeline.sh

# 3. Open Tableau, connect to the CSVs in data/modeled/, build/refresh the extract
# ...and build a dashboard, if you like
```

Re-run step 2 any time the source assumptions change, replacing the .CSVs in Tableau Public (_note_ - in a 'live' environment, a direct connection would likely just require a Tableau extract refresh).  

## Design notes / known simplifications

- `store_number` is a zero-padded 3-digit string throughout. Most tools' default type inference (pandas, DuckDB CSV autodetect, Tableau) will read a pure-digit column as an integer and drop the padding - the SQL scripts enforce the 0-padded 3-digit string format up to export/ingestion. Typing may need to be changed again in the Tableau data pane.  
- Test purchases are an even audit sample across shops/categories (by design); transactions are realistically skewed (more alcohol than fireworks, weighted toward evenings/weekends/seasonal peaks).  
- Cashiers with under 30 transactions and a pass rate over the lower threshold currently flag as `'Normal'` but are not scored against the upper pass rate threshold. A possible future addition would be to have another `'Unscored - insufficient volume for High pass rate check'` flag which captures this potential blind spot.  