"""
Synthetic data generator for the Age-Restricted Sales / Training Radar portfolio project.

Produces three CSVs:
  - shop_dimensions.csv   (30 fictitious shops)
  - transactions.csv      (organic till transactions, realistic skew)
  - test_purchases.csv    (mystery-shopper style audit sample, even by design)

All figures are fictitious. No real employer data is used or referenced.
"""

import numpy as np
import pandas as pd
from datetime import date, timedelta
from pathlib import Path

rng = np.random.default_rng(42)

# Always write into <repo_root>/data/raw/, regardless of the current working
# directory the script happens to be run from (so `python3 generate_data.py`
# from inside scripts/, or `python3 scripts/generate_data.py` from the repo
# root, both land in the same place).
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# 1. SHOP DIMENSIONS
# ---------------------------------------------------------------------------

shops_raw = [
    ("001", "Camden",      "London",      "Local"),
    ("002", "Clapham",     "London",      "Local"),
    ("003", "Islington",   "London",      "Supermarket"),
    ("004", "Greenwich",   "London",      "Supermarket"),
    ("005", "Richmond",    "London",      "Local"),
    ("006", "Ealing",      "London",      "Supermarket"),
    ("007", "Guildford",   "South East",  "Supermarket"),
    ("008", "Reading",     "South East",  "Superstore"),
    ("009", "Brighton",    "South East",  "Supermarket"),
    ("010", "Oxford",      "South East",  "Local"),
    ("011", "Canterbury",  "South East",  "Supermarket"),
    ("012", "Bristol",     "South West",  "Superstore"),
    ("013", "Bath",        "South West",  "Local"),
    ("014", "Exeter",      "South West",  "Supermarket"),
    ("015", "Plymouth",    "South West",  "Supermarket"),
    ("016", "Birmingham",  "Midlands",    "Superstore"),
    ("017", "Nottingham",  "Midlands",    "Supermarket"),
    ("018", "Leicester",   "Midlands",    "Supermarket"),
    ("019", "Coventry",    "Midlands",    "Local"),
    ("020", "Manchester",  "North West",  "Superstore"),
    ("021", "Liverpool",   "North West",  "Supermarket"),
    ("022", "Preston",     "North West",  "Local"),
    ("023", "Chester",     "North West",  "Supermarket"),
    ("024", "Newcastle",   "North East",  "Supermarket"),
    ("025", "Durham",      "North East",  "Local"),
    ("026", "York",        "North East",  "Supermarket"),
    ("027", "Edinburgh",   "Scotland",    "Superstore"),
    ("028", "Glasgow",     "Scotland",    "Supermarket"),
    ("029", "Aberdeen",    "Scotland",    "Local"),
    ("030", "Cardiff",     "Wales",       "Supermarket"),
]

CHAIN = "Ashgrove"
shops = pd.DataFrame(shops_raw, columns=["store_number", "location", "region", "format"])
shops["shop_name"] = CHAIN + " " + shops["location"]
shops = shops[["store_number", "shop_name", "region", "format"]]
# NOTE ON LOADING: store_number is a zero-padded 3-digit string ("001"-"030") in
# every CSV here. Default type inference (pandas, BigQuery autodetect, Excel,
# Tableau) will read a pure-digit column as an integer and silently drop the
# leading zero. This won't break joins as long as all three tables get cast
# the same way, but for a clean "023"-style display, set store_number to
# STRING explicitly in the BigQuery schema (and as a string/text field in
# Tableau) rather than relying on autodetect.

# Assign each shop a compliance "tier" that drives BOTH its test-purchase pass
# rate and its general training-quality baseline. Roughly: 4 excellent, 22 good,
# 4 at-risk -- matches the "some 100%, majority 85-95%, some outliers <80%" spec.
# Force a clean distribution: 4 excellent, 4 at_risk, rest good
# NOTE: must use dtype=object here -- a plain np.array(["good"]*n) locks in a
# fixed-width '<U4' string dtype (width of "good"), which silently truncates
# "excellent" -> "exce" and "at_risk" -> "at_r" on assignment below.
tier = np.array(["good"] * len(shops), dtype=object)
excellent_idx = rng.choice(len(shops), size=4, replace=False)
remaining = [i for i in range(len(shops)) if i not in excellent_idx]
at_risk_idx = rng.choice(remaining, size=4, replace=False)
tier[excellent_idx] = "excellent"
tier[at_risk_idx] = "at_risk"
shops["_compliance_tier"] = tier  # internal use only, dropped before export

shops.to_csv(OUTPUT_DIR / "shop_dimensions_full.csv", index=False)  # keep tier for generation (not committed -- see .gitignore)
shops.drop(columns="_compliance_tier").to_csv(OUTPUT_DIR / "shop_dimensions.csv", index=False)

CATEGORIES = ["alcohol", "tobacco", "energy drinks", "analgesics", "fireworks", "lottery"]

DATE_START = date(2025, 7, 18)
DATE_END = date(2026, 7, 17)   # "today" for the dashboard's frame of reference
ALL_DATES = pd.date_range(DATE_START, DATE_END, freq="D")

EASTER_2026 = date(2026, 4, 5)

# ---------------------------------------------------------------------------
# Helpers: weighted date/time sampling
# ---------------------------------------------------------------------------

def _compute_date_weights(category):
    """Return an array of weights (same length as ALL_DATES), one per calendar day."""
    w = np.ones(len(ALL_DATES))
    for i, d in enumerate(ALL_DATES):
        dt = d.date()
        wd = dt.weekday()  # 0=Mon ... 4=Fri, 5=Sat, 6=Sun
        if wd == 4:
            w[i] *= 1.35   # Friday
        elif wd == 5:
            w[i] *= 1.5    # Saturday
        elif wd == 6:
            w[i] *= 0.9    # Sunday

        # Christmas run-up
        if (dt.month == 12 and 15 <= dt.day <= 24):
            w[i] *= 1.6
        # Easter run-up
        if abs((dt - EASTER_2026).days) <= 4:
            w[i] *= 1.4

        # Fireworks-specific seasonal spikes
        if category == "fireworks":
            if dt.month == 11 and dt.day <= 5:
                w[i] *= 8.0
            elif (dt.month == 12 and dt.day >= 28) or (dt.month == 1 and dt.day <= 1):
                w[i] *= 6.0
            else:
                w[i] *= 0.15  # fireworks are rare outside these windows
    return w / w.sum()


def _compute_hour_weights(category):
    hours = np.arange(8, 22)  # 8..21 inclusive start-hour buckets
    w = np.ones(len(hours))
    for i, h in enumerate(hours):
        if 12 <= h <= 13:
            w[i] *= 1.8   # lunch peak
        if 17 <= h <= 19:
            w[i] *= 2.0   # evening peak
        if category == "alcohol" and h >= 17:
            w[i] *= 1.6   # extra evening skew for alcohol
        if category == "energy drinks" and 8 <= h <= 10:
            w[i] *= 1.5   # morning skew
    return w / w.sum()


# Pre-cache per category (dates/hours don't depend on user, only category)
CATEGORY_DATE_WEIGHTS = {c: _compute_date_weights(c) for c in CATEGORIES}
CATEGORY_HOUR_WEIGHTS = {c: _compute_hour_weights(c) for c in CATEGORIES}
HOURS = np.arange(8, 22)


def sample_dates(category, n):
    idx = rng.choice(len(ALL_DATES), size=n, p=CATEGORY_DATE_WEIGHTS[category])
    return ALL_DATES[idx]


def sample_times(category, n):
    chosen_hours = rng.choice(HOURS, size=n, p=CATEGORY_HOUR_WEIGHTS[category])
    minutes = rng.integers(0, 60, size=n)
    return [f"{h:02d}:{m:02d}" for h, m in zip(chosen_hours, minutes)]


# ---------------------------------------------------------------------------
# 2. USER POOL (internal - drives both fact tables, not exported separately)
# ---------------------------------------------------------------------------

# Scales every user's transaction count up by this factor, keeping the same
# min/shape (just more of it). Higher volume directly reduces sampling noise
# on any per-user or per-user-per-category rate -- standard error shrinks by
# 1/sqrt(multiplier), so 4x the transactions roughly halves it. This matters
# most for Signal 4 (category-level check rate) in 02_training_flags.sql,
# where category volumes per user were thin (fireworks: median 2/year) and
# only ~15% of user-category pairs cleared the 5-transaction scoring minimum.
# Set back to 1 to reproduce the original volumes.
TRANSACTIONS_PER_USER_MULTIPLIER = 4

user_records = []   # (user_id, store_number, check_complete_base, check_pass_base, n_transactions)
uid_counter = 1

for _, row in shops.iterrows():
    store_number = row["store_number"]
    n_users = rng.integers(12, 27)  # 12-26 users per store -> within the 10-30 spec
    for _ in range(n_users):
        user_id = f"U{uid_counter:04d}"
        uid_counter += 1

        # id_check_complete base rate: majority 10-20%, ~12% of users are outliers
        if rng.random() < 0.12:
            check_complete_base = rng.choice([rng.uniform(0.0, 0.03), rng.uniform(0.92, 1.0)])
        else:
            check_complete_base = np.clip(rng.beta(6, 34), 0.02, 0.35)  # mean ~0.15

        # id_check_passed base rate: centered ~90%, ~13% of users are low outliers (mislogging)
        if rng.random() < 0.13:
            check_pass_base = rng.uniform(0.55, 0.78)
        else:
            check_pass_base = np.clip(rng.beta(27, 3), 0.75, 1.0)

        n_transactions = TRANSACTIONS_PER_USER_MULTIPLIER * (30 + int(rng.exponential(45)))  # min 30, long tail of "a lot more" (scaled by the multiplier above)

        user_records.append((user_id, store_number, check_complete_base, check_pass_base, n_transactions))

users_df = pd.DataFrame(
    user_records,
    columns=["user_id", "store_number", "_check_complete_base", "_check_pass_base", "_n_transactions"],
)
print(f"Total users generated: {len(users_df)}")
print(users_df["_n_transactions"].describe())

# ---------------------------------------------------------------------------
# 3. TRANSACTIONS FACT TABLE
# ---------------------------------------------------------------------------

CATEGORY_WEIGHTS = {
    "alcohol": 0.35,
    "tobacco": 0.25,
    "lottery": 0.20,
    "energy drinks": 0.10,
    "analgesics": 0.07,
    "fireworks": 0.03,
}
cat_list = list(CATEGORY_WEIGHTS.keys())
cat_probs = np.array(list(CATEGORY_WEIGHTS.values()))
cat_probs = cat_probs / cat_probs.sum()

CHECK_COMPLETE_NOISE_SIGMA = {
    "alcohol": 0.02, "tobacco": 0.02, "fireworks": 0.02,          # low-variance categories
    "analgesics": 0.09, "energy drinks": 0.09, "lottery": 0.09,   # high-variance categories
}

txn_rows = []

for u_id, u_store, u_check_complete_base, u_check_pass_base, u_n_transactions in users_df.itertuples(index=False, name=None):
    cat_counts = rng.multinomial(u_n_transactions, cat_probs)
    for cat, count in zip(cat_list, cat_counts):
        if count == 0:
            continue
        dates = sample_dates(cat, count)
        times = sample_times(cat, count)

        noise = rng.normal(0, CHECK_COMPLETE_NOISE_SIGMA[cat], size=count)
        complete_probs = np.clip(u_check_complete_base + noise, 0.0, 1.0)
        id_check_complete = rng.random(count) < complete_probs

        n_checked = id_check_complete.sum()
        # Generate passes only for the subset of transactions where ID was requested
        passed_array = rng.random(n_checked) < u_check_pass_base if n_checked > 0 else []
        pass_idx = 0

        for i in range(count):
            is_checked = bool(id_check_complete[i])
            if is_checked:
                is_passed = bool(passed_array[pass_idx])
                pass_idx += 1
            else:
                is_passed = None  # Exports cleanly as an empty CSV cell without NaN casting

            txn_rows.append((
                u_store,
                pd.Timestamp(dates[i]).strftime("%Y-%m-%d"),
                times[i],
                u_id,
                cat,
                is_checked,
                is_passed,
            ))

# Build DataFrame without ID first
transactions = pd.DataFrame(txn_rows, columns=[
    "store_number", "transaction_date", "transaction_time",
    "user_id", "category", "id_check_complete", "id_check_passed",
])

# Sort chronologically using ISO 8601 string ordering
transactions = transactions.sort_values(by=["transaction_date", "transaction_time"]).reset_index(drop=True)

# Assign sequentially padded transaction IDs post-sort
transactions.insert(0, "transaction_id", [f"TXN{i:06d}" for i in range(1, len(transactions) + 1)])

print(f"Total transactions: {len(transactions)}")
print("Overall id_check_complete rate:", transactions["id_check_complete"].mean().round(3))
checked = transactions[transactions["id_check_complete"] == True]
print("Overall id_check_passed rate (of checked):", (checked["id_check_passed"] == True).mean().round(3))

transactions.to_csv(OUTPUT_DIR / "transactions.csv", index=False)

# ---------------------------------------------------------------------------
# 4. TEST PURCHASES FACT TABLE
# ---------------------------------------------------------------------------

# "good" and "at_risk" tiers get a per-shop fixed baseline drawn once
# (the "excellent" tier is handled separately below with a fixed prob=1.0)
CATEGORY_PASS_MODIFIER = {
    "alcohol": 0.05, "tobacco": 0.05,
    "energy drinks": -0.12, "analgesics": -0.12,
    "fireworks": 0.0, "lottery": 0.0,
}

TEST_PURCHASES_PER_SHOP_CATEGORY = 5  # ~5/year per shop/category -> 900 rows total

shop_baseline = {}
for _, row in shops.iterrows():
    tier = row["_compliance_tier"]
    if tier == "excellent":
        shop_baseline[row["store_number"]] = 1.00
    elif tier == "at_risk":
        shop_baseline[row["store_number"]] = rng.uniform(0.65, 0.80)
    else:
        shop_baseline[row["store_number"]] = rng.uniform(0.85, 0.95)

# Build a lookup of users per store so test-purchase user_ids match real till staff
users_by_store = users_df.groupby("store_number")["user_id"].apply(list).to_dict()

tp_rows = []

for _, row in shops.iterrows():
    store_number = row["store_number"]
    tier = row["_compliance_tier"]
    baseline = shop_baseline[store_number]
    store_users = users_by_store[store_number]

    for cat in CATEGORIES:
        n = TEST_PURCHASES_PER_SHOP_CATEGORY
        dates = sample_dates(cat, n)
        times = sample_times(cat, n)
        chosen_users = rng.choice(store_users, size=n, replace=True)

        if tier == "excellent":
            prob = 1.0
        else:
            prob = np.clip(baseline + CATEGORY_PASS_MODIFIER[cat] + rng.normal(0, 0.03), 0.0, 1.0)

        passed = rng.random(n) < prob

        for i in range(n):
            tp_rows.append((
                pd.Timestamp(dates[i]).strftime("%Y-%m-%d"),
                times[i],
                store_number,
                chosen_users[i],
                cat,
                bool(passed[i]),
            ))

# Build DataFrame without ID first
test_purchases = pd.DataFrame(tp_rows, columns=[
    "test_purchase_date", "test_purchase_time",
    "store_number", "user_id", "category", "test_purchase_pass",
])

# Sort chronologically
test_purchases = test_purchases.sort_values(by=["test_purchase_date", "test_purchase_time"]).reset_index(drop=True)

# Assign sequentially padded test purchase IDs post-sort
test_purchases.insert(0, "test_purchase_id", [f"TP{i:05d}" for i in range(1, len(test_purchases) + 1)])

print(f"Total test purchases: {len(test_purchases)}")
print("Overall pass rate:", test_purchases["test_purchase_pass"].mean().round(3))

by_shop = test_purchases.groupby("store_number")["test_purchase_pass"].mean()
print("Shops at 100%:", (by_shop == 1.0).sum())
print("Shops 85-95%:", ((by_shop >= 0.85) & (by_shop <= 0.95)).sum())
print("Shops below 80%:", (by_shop < 0.80).sum())

test_purchases.to_csv(OUTPUT_DIR / "test_purchases.csv", index=False)