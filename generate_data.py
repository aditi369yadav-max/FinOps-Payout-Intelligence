"""
generate_data.py
FinOps Seller Payout Intelligence System
Generates realistic synthetic data for Amazon Seller Services simulation
"""

import pandas as pd
import numpy as np
import sqlite3
import random
import os
from datetime import datetime, timedelta

random.seed(42)
np.random.seed(42)

# ─── CONFIG ──────────────────────────────────────────────────────────────────
NUM_SELLERS = 120
NUM_TRANSACTIONS = 12000
START_DATE = datetime(2024, 10, 1)
END_DATE = datetime(2024, 12, 31)
DB_PATH = "data/seller_payouts.db"

# ─── SELLER TIERS ─────────────────────────────────────────────────────────────
TIER_CONFIG = {
    "Platinum": {"count": 10, "commission_rate": 0.08, "avg_gmv": 180000, "std_gmv": 40000},
    "Gold":     {"count": 25, "commission_rate": 0.10, "avg_gmv": 80000,  "std_gmv": 20000},
    "Silver":   {"count": 45, "commission_rate": 0.12, "avg_gmv": 35000,  "std_gmv": 10000},
    "Bronze":   {"count": 40, "commission_rate": 0.15, "avg_gmv": 12000,  "std_gmv": 5000},
}

CATEGORIES = ["Electronics", "Fashion", "Home & Kitchen", "Books", "Sports",
              "Beauty", "Toys", "Automotive", "Grocery", "Furniture"]

STATES = ["Karnataka", "Maharashtra", "Delhi", "Tamil Nadu", "Telangana",
          "Gujarat", "West Bengal", "Rajasthan", "Uttar Pradesh", "Kerala"]

# Root cause codes for anomalies
ROOT_CAUSES = [
    "FEE_CALCULATION_ERROR",
    "RETURN_TIMING_MISMATCH",
    "CATEGORY_POLICY_CHANGE",
    "DUPLICATE_TRANSACTION",
    "MANUAL_ADJUSTMENT_OVERRIDE",
    "TAX_RATE_DISCREPANCY",
    "CURRENCY_ROUNDING_ERROR",
]

PAYMENT_METHODS = ["NEFT", "RTGS", "UPI", "Cheque"]


# ─── GENERATE SELLERS ─────────────────────────────────────────────────────────
def generate_sellers():
    sellers = []
    seller_id = 1000
    first_names = ["Ravi", "Priya", "Amit", "Sunita", "Deepak", "Kavya", "Raj", "Meena",
                   "Suresh", "Anita", "Vikram", "Pooja", "Arun", "Nisha", "Kiran", "Rohit",
                   "Divya", "Manoj", "Shreya", "Ajay", "Rekha", "Sanjay", "Usha", "Vijay"]
    last_names = ["Sharma", "Verma", "Patel", "Singh", "Kumar", "Gupta", "Joshi", "Reddy",
                  "Nair", "Iyer", "Mehta", "Shah", "Rao", "Pillai", "Mishra", "Agarwal"]
    business_types = ["Pvt Ltd", "LLP", "Sole Proprietor", "Partnership", "OPC"]

    for tier, cfg in TIER_CONFIG.items():
        for _ in range(cfg["count"]):
            fname = random.choice(first_names)
            lname = random.choice(last_names)
            joined = START_DATE - timedelta(days=random.randint(90, 1800))
            # Risk score factors
            base_risk = {"Platinum": 15, "Gold": 25, "Silver": 40, "Bronze": 60}[tier]
            risk_score = min(100, max(0, base_risk + random.randint(-15, 25)))

            sellers.append({
                "seller_id": f"SLR{seller_id}",
                "seller_name": f"{fname} {lname} {random.choice(business_types)}",
                "tier": tier,
                "category": random.choice(CATEGORIES),
                "state": random.choice(STATES),
                "commission_rate": cfg["commission_rate"],
                "joined_date": joined.strftime("%Y-%m-%d"),
                "payment_method": random.choice(PAYMENT_METHODS),
                "bank_account": f"XXXX{random.randint(1000,9999)}",
                "gstin": f"{''.join(random.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', k=15))}",
                "risk_score": risk_score,
                "avg_monthly_gmv": cfg["avg_gmv"] + random.randint(-5000, 5000),
                "total_orders_lifetime": random.randint(500, 50000),
                "return_rate": round(random.uniform(0.02, 0.18), 3),
                "active": random.random() > 0.05,
            })
            seller_id += 1

    return pd.DataFrame(sellers)


# ─── GENERATE TRANSACTIONS ────────────────────────────────────────────────────
def generate_transactions(sellers_df):
    transactions = []
    txn_id = 100000

    seller_ids = sellers_df["seller_id"].tolist()
    seller_map = sellers_df.set_index("seller_id").to_dict("index")

    months = ["Oct-2024", "Nov-2024", "Dec-2024"]

    for _ in range(NUM_TRANSACTIONS):
        seller_id = random.choice(seller_ids)
        s = seller_map[seller_id]
        tier = s["tier"]
        cfg = TIER_CONFIG[tier]
        month = random.choice(months)

        # GMV per transaction
        gmv = abs(np.random.normal(cfg["avg_gmv"] / 120, cfg["std_gmv"] / 60))
        gmv = round(max(500, gmv), 2)

        commission_rate = cfg["commission_rate"]
        commission = round(gmv * commission_rate, 2)
        gst_on_commission = round(commission * 0.18, 2)
        shipping_fee = round(random.uniform(20, 150), 2)
        return_amount = round(gmv * s["return_rate"] * random.uniform(0, 1.5), 2)

        expected_payout = round(gmv - commission - gst_on_commission - shipping_fee - return_amount, 2)

        # Inject anomalies ~8% of the time
        is_anomaly = random.random() < 0.08
        root_cause = None
        discrepancy_amount = 0.0

        if is_anomaly:
            root_cause = random.choice(ROOT_CAUSES)
            if root_cause == "FEE_CALCULATION_ERROR":
                wrong_rate = commission_rate * random.choice([0.85, 1.15, 1.2])
                actual_payout = round(gmv - gmv * wrong_rate - gst_on_commission - shipping_fee - return_amount, 2)
            elif root_cause == "RETURN_TIMING_MISMATCH":
                actual_payout = round(expected_payout + return_amount * 0.5, 2)
            elif root_cause == "CATEGORY_POLICY_CHANGE":
                actual_payout = round(expected_payout * random.uniform(0.88, 0.95), 2)
            elif root_cause == "DUPLICATE_TRANSACTION":
                actual_payout = round(expected_payout * 2, 2)
            elif root_cause == "MANUAL_ADJUSTMENT_OVERRIDE":
                actual_payout = round(expected_payout + random.uniform(-2000, 2000), 2)
            elif root_cause == "TAX_RATE_DISCREPANCY":
                actual_payout = round(expected_payout + gst_on_commission * 0.1, 2)
            else:  # CURRENCY_ROUNDING_ERROR
                actual_payout = round(expected_payout + random.uniform(-5, 5), 2)

            discrepancy_amount = round(actual_payout - expected_payout, 2)
            status = "Discrepancy"
        else:
            actual_payout = expected_payout
            status = "Processed"

        # SLA: days since transaction (aging)
        days_old = random.randint(0, 45)
        sla_breach = is_anomaly and days_old > 2

        # Date within month
        month_start = {"Oct-2024": datetime(2024,10,1), "Nov-2024": datetime(2024,11,1), "Dec-2024": datetime(2024,12,1)}[month]
        days_in_month = 31 if month in ["Oct-2024","Dec-2024"] else 30
        txn_date = month_start + timedelta(days=random.randint(0, days_in_month - 1))

        transactions.append({
            "transaction_id": f"TXN{txn_id}",
            "seller_id": seller_id,
            "month": month,
            "transaction_date": txn_date.strftime("%Y-%m-%d"),
            "category": s["category"],
            "gmv": gmv,
            "commission_rate": commission_rate,
            "commission": commission,
            "gst_on_commission": gst_on_commission,
            "shipping_fee": shipping_fee,
            "return_amount": return_amount,
            "expected_payout": expected_payout,
            "actual_payout": actual_payout,
            "discrepancy_amount": discrepancy_amount,
            "status": status,
            "root_cause": root_cause if root_cause else "NONE",
            "payment_method": s["payment_method"],
            "days_outstanding": days_old if is_anomaly else 0,
            "sla_breach": sla_breach,
            "resolution_status": random.choice(["Pending", "In Review", "Resolved"]) if is_anomaly else "N/A",
        })
        txn_id += 1

    return pd.DataFrame(transactions)


# ─── MAIN ─────────────────────────────────────────────────────────────────────
def main():
    os.makedirs("data", exist_ok=True)
    os.makedirs("reports", exist_ok=True)

    print("🔄 Generating sellers...")
    sellers_df = generate_sellers()
    sellers_df.to_csv("data/sellers.csv", index=False)
    print(f"   ✅ {len(sellers_df)} sellers created")

    print("🔄 Generating transactions...")
    txn_df = generate_transactions(sellers_df)
    txn_df.to_csv("data/transactions.csv", index=False)
    print(f"   ✅ {len(txn_df)} transactions created")

    print("🔄 Building SQLite database...")
    conn = sqlite3.connect(DB_PATH)
    sellers_df.to_sql("sellers", conn, if_exists="replace", index=False)
    txn_df.to_sql("transactions", conn, if_exists="replace", index=False)
    conn.close()
    print(f"   ✅ Database saved to {DB_PATH}")

    # Summary
    disc = txn_df[txn_df["status"] == "Discrepancy"]
    print(f"\n📊 Dataset Summary:")
    print(f"   Total GMV:           ₹{txn_df['gmv'].sum():,.0f}")
    print(f"   Total Net Payout:    ₹{txn_df['actual_payout'].sum():,.0f}")
    print(f"   Discrepancies:       {len(disc)} ({len(disc)/len(txn_df)*100:.1f}%)")
    print(f"   Amount at Risk:      ₹{disc['discrepancy_amount'].abs().sum():,.0f}")
    print(f"   SLA Breaches:        {txn_df['sla_breach'].sum()}")
    print("\n✅ Data generation complete!")

if __name__ == "__main__":
    main()
