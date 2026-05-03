# FinOps Seller Payout Intelligence System
### Amazon Seller Services · Process Associate L3 · Q4 2024

> **Built to demonstrate production-grade FinOps skills** — automated reconciliation, root cause classification, SLA tracking, seller risk scoring, and stakeholder-specific reporting across 12,000 transactions and 120 sellers.

---

## 🎯 Business Problem

Amazon processes thousands of seller payouts monthly. Manual reconciliation is:
- **Error-prone** — fee miscalculations go undetected for weeks
- **Reactive** — issues are caught *after* disbursement, not before
- **Opaque** — different stakeholders see the same raw dump instead of tailored views

This system solves all three.

---

## 📊 Dataset

| Metric | Value |
|---|---|
| Transactions | 12,000 |
| Sellers | 120 |
| Period | Q4 2024 (Oct – Dec) |
| Total GMV | ₹76,46,389 |
| Net Payout | ₹50,55,393 |
| Discrepancies Auto-Detected | 994 (8.3%) |
| Amount at Risk Flagged | ₹1,91,642 |
| SLA Breaches Tracked | 917 |
| Seller Tiers | Platinum · Gold · Silver · Bronze |

---

## 🚀 What Makes This Different

### ✅ Root Cause Intelligence Engine
Every flagged discrepancy is automatically classified into one of 7 root causes:

| Code | Description | Financial Impact |
|---|---|---|
| `MANUAL_ADJUSTMENT_OVERRIDE` | Unauthorized manual edits | ₹1,25,002 |
| `DUPLICATE_TRANSACTION` | Same payout processed twice | ₹55,663 |
| `CATEGORY_POLICY_CHANGE` | Mid-month rate change | ₹5,186 |
| `RETURN_TIMING_MISMATCH` | Refund in wrong billing cycle | ₹3,508 |
| `FEE_CALCULATION_ERROR` | Wrong commission rate applied | ₹1,784 |
| `CURRENCY_ROUNDING_ERROR` | Sub-rupee compounding errors | ₹317 |
| `TAX_RATE_DISCREPANCY` | GST at incorrect slab | ₹182 |

This is what a senior analyst does manually. This system does it in seconds.

### ✅ SLA Breach Tracker
Every discrepancy is tracked against a 48-hour resolution SLA with aging buckets:
- 0–2 days (OK)
- 3–7 days (Warning)  
- 8–14 days (Overdue)
- 15+ days (Critical) ← 657 cases, ₹1,21,839 at risk

### ✅ Seller Risk Scoring
Multi-factor composite risk score (0–100) using:
```
Risk Score = 
  min(40, discrepancy_rate × 4)        ← biggest driver
+ min(20, sla_breaches × 1.5)
+ min(15, unique_root_causes × 3)
+ min(15, return_rate × 80)
+ min(10, avg_days_outstanding / 5)
```
**94 sellers flagged** as predicted anomaly risks for next month.

### ✅ Stakeholder-Specific Outputs
The same data produces 3 different views:
- **Finance team** → Full Excel reconciliation (6 sheets)
- **Operations** → SLA breach tracker with aging
- **Manager** → P0/P1/P2 alert digest with owners and deadlines

---

## 🗂️ Project Structure

```
FinOps-Payout-Intelligence/
│
├── 📄 README.md
├── 🐍 generate_data.py              # Synthetic dataset generation
├── 🐍 payout_automation.py          # 6-step reconciliation pipeline
├── 🗃️  sql/payout_queries.sql        # 9 production-grade SQL queries
├── 🌐 seller_payout_dashboard.html  # Interactive dashboard (no server needed)
│
├── data/
│   ├── seller_payouts.db            # SQLite database
│   ├── transactions.csv             # 12,000 transaction records
│   ├── sellers.csv                  # 120 seller profiles
│   └── dashboard_data.json         # Pre-processed dashboard data
│
└── reports/
    └── FinOps_Payout_Intelligence_Q4_2024.xlsx  # 6-sheet Excel report
```

---

## ⚙️ How to Run

### Prerequisites
```bash
pip install pandas numpy openpyxl
```

### Step 1 — Generate Dataset
```bash
python generate_data.py
```
Output: `seller_payouts.db`, `transactions.csv`, `sellers.csv`

### Step 2 — Run Reconciliation Pipeline
```bash
python payout_automation.py
```
Output: Excel report + terminal alerts

```
[1/6] Monthly payout reconciliation
[2/6] Root cause classification engine  ← 994 discrepancies in 7 categories
[3/6] SLA breach tracker                ← 917 breaches, aging analysis
[4/6] Seller risk scoring               ← 47 critical, 57 high risk
[5/6] Category performance              ← 10 categories benchmarked
[6/6] Excel + JSON export               ← 6-sheet report generated
```

### Step 3 — Open Dashboard
Double-click `seller_payout_dashboard.html` — opens in any browser, zero server required.

---

## 🔍 Key SQL Queries

### Monthly Reconciliation
```sql
SELECT month,
    COUNT(DISTINCT seller_id)    AS active_sellers,
    ROUND(SUM(gmv), 2)           AS total_gmv,
    ROUND(SUM(actual_payout), 2) AS total_actual_payout,
    ROUND(SUM(actual_payout) - SUM(expected_payout), 2) AS reconciliation_gap,
    CASE WHEN ABS(SUM(actual_payout) - SUM(expected_payout)) > 5000
         THEN '⚠️ REVIEW REQUIRED' ELSE '✅ OK'
    END                          AS reconciliation_status
FROM transactions
GROUP BY month;
```

### Root Cause with Severity Classification
```sql
SELECT root_cause,
    COUNT(*) AS cases,
    ROUND(SUM(ABS(discrepancy_amount)), 2) AS amount_at_risk,
    CASE WHEN SUM(ABS(discrepancy_amount)) > 30000 THEN 'CRITICAL'
         WHEN SUM(ABS(discrepancy_amount)) > 15000 THEN 'HIGH'
         ELSE 'MEDIUM' END AS severity
FROM transactions
WHERE status = 'Discrepancy'
GROUP BY root_cause
ORDER BY amount_at_risk DESC;
```

Full query bank: [`sql/payout_queries.sql`](sql/payout_queries.sql) — 9 queries covering reconciliation, SLA tracking, risk scoring, category analysis, MoM growth, duplicate detection, and stakeholder alerts.

---

## 📈 Business Impact

| Metric | Result |
|---|---|
| Transactions reconciled | 12,000 |
| Discrepancies auto-detected | 994 |
| Root causes auto-classified | 7 categories |
| Amount at risk flagged | ₹1,91,642 |
| SLA breaches tracked | 917 |
| High-risk sellers identified | 104 (CRITICAL + HIGH) |
| Next-month anomaly predictions | 94 sellers |
| Excel report sheets generated | 6 |
| Estimated manual time saved | ~85% |

---

## 🛠️ Tech Stack

| Tool | Purpose |
|---|---|
| Python (Pandas, NumPy) | Data generation & pipeline automation |
| SQLite | Relational data storage |
| SQL (9 queries) | Financial analysis & reconciliation logic |
| HTML/CSS/JavaScript | Interactive dashboard UI |
| Chart.js | Data visualizations |
| openpyxl | Multi-sheet Excel report generation |
| Git + GitHub Pages | Version control & deployment |

---

## 👤 Author

**Aditi Yadav**  
Aspiring Process Associate · FinOps & Data Analytics  
Built for Amazon Seller Services L3 Application

---

*This project demonstrates hands-on skills in financial operations, SQL analysis, Python automation, anomaly detection, risk scoring, and stakeholder communication — directly aligned with the Amazon Seller Services Process Associate (L3) role.*
