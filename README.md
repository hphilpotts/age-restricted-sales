# Training Radar — Age-Restricted Sales Compliance Dashboard

A portfolio project mirroring real-world retail age-verification compliance
reporting: historical test-purchase performance at shop level, and a
"training needs" signal layer that flags till staff who may need refresher
training, based on how consistently and accurately they check ID.

**All data in this repository is synthetic.** It is generated from
scratch by `scripts/generate_data.py` to plausible, realistic distributions
(see that file's comments for the exact assumptions) — no real employer
data, real shop names, or real staff data is used anywhere in this project.

## What this shows

- **Historical performance insights** (shop level): test-purchase pass
  rate by category, day of week, and time of day.
- **Training needs flags** (staff level): three signals combined —
  1. Unusually low or high ID-check completion rate (self-adjusting
     estate-wide percentile bands, not a fixed cutoff)
  2. ID-check pass rate below 80% (of checks completed) — a likely sign
     of mislogging rather than genuine refusals
  3. A failed test purchase within the last 90 days

## Tech stack

- **Python** (numpy/pandas) — synthetic data generation with realistic,
  documented distributions (category mix, day-of-week/seasonal weighting,
  per-user behavioural outliers)
- **DuckDB** (SQL) — data modeling: typing/cleaning, the training-flag
  logic, and the shop performance rollups
- **Tableau Public** — the dashboard itself, built from the modeled CSVs

## Repo structure

```
.
├── data/
│   ├── raw/            # generated source CSVs (shop dims, transactions, test purchases)
│   └── modeled/         # SQL output, ready for Tableau (generated -- not hand-edited)
├── sql/
│   ├── 01_create_tables.sql          # load + type the raw CSVs
│   ├── 02_training_flags.sql         # the three training-flag signals
│   ├── 03_shop_performance_summary.sql  # shop/category/day/time-of-day rollups
│   └── 04_export_for_tableau.sql     # exports modeled views to data/modeled/
├── scripts/
│   ├── generate_data.py              # synthetic data generator
│   └── run_pipeline.sh               # runs all 4 SQL scripts in order
└── README.md
```

## Reproducing this from scratch

```bash
# 1. Generate the raw synthetic data
python3 scripts/generate_data.py   # writes into data/raw/

# 2. Run the full DuckDB pipeline (load -> model -> export)
bash scripts/run_pipeline.sh       # run from the repo root

# 3. Open Tableau, connect to the CSVs in data/modeled/, build/refresh the extract
```

Re-run steps 1–2 any time the source assumptions change; the dashboard
extract only needs a refresh, not a rebuild.

## Design notes / known simplifications

- `store_number` is a zero-padded 3-digit string throughout. Most tools'
  default type inference (pandas, DuckDB CSV autodetect, Tableau) will read
  a pure-digit column as an integer and drop the padding — the SQL scripts
  cast it explicitly to avoid this.
- Test purchases are an even audit sample across shops/categories (by
  design); transactions are realistically skewed (more alcohol than
  fireworks, weighted toward evenings/weekends/seasonal peaks).
- The random seed in `generate_data.py` is fixed for reproducibility --
  note the comment in that file about not removing "dead-looking" code
  near the top without expecting the whole dataset to regenerate.