-- ============================================================
-- payout_queries.sql
-- FinOps Seller Payout Intelligence System
-- Amazon Seller Services · Process Associate L3
-- ============================================================
-- Database: SQLite (seller_payouts.db)
-- Tables:   transactions, sellers
-- Author:   Aditi Yadav
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- QUERY 1: Monthly Payout Reconciliation Summary
-- Purpose : Compare expected vs actual payouts per month
--           Flags months where reconciliation gap > ₹5,000
-- Used by : Finance team, Month-end closing
-- ────────────────────────────────────────────────────────────
SELECT
    t.month,
    COUNT(DISTINCT t.seller_id)                         AS active_sellers,
    COUNT(t.transaction_id)                             AS total_transactions,
    ROUND(SUM(t.gmv), 2)                                AS total_gmv,
    ROUND(SUM(t.commission), 2)                         AS total_commission,
    ROUND(SUM(t.gst_on_commission), 2)                  AS total_gst,
    ROUND(SUM(t.return_amount), 2)                      AS total_returns,
    ROUND(SUM(t.expected_payout), 2)                    AS total_expected_payout,
    ROUND(SUM(t.actual_payout), 2)                      AS total_actual_payout,
    ROUND(SUM(t.actual_payout) - SUM(t.expected_payout), 2) AS reconciliation_gap,
    SUM(CASE WHEN t.status = 'Discrepancy' THEN 1 ELSE 0 END) AS discrepancy_count,
    ROUND(
        SUM(CASE WHEN t.status = 'Discrepancy' THEN 1.0 ELSE 0 END)
        / COUNT(t.transaction_id) * 100, 2
    )                                                   AS discrepancy_rate_pct,
    SUM(CASE WHEN t.sla_breach = 1 THEN 1 ELSE 0 END)  AS sla_breaches,
    CASE
        WHEN ABS(SUM(t.actual_payout) - SUM(t.expected_payout)) > 5000
        THEN '⚠️ REVIEW REQUIRED'
        ELSE '✅ OK'
    END                                                 AS reconciliation_status
FROM transactions t
GROUP BY t.month
ORDER BY t.month;


-- ────────────────────────────────────────────────────────────
-- QUERY 2: Root Cause Classification with Financial Impact
-- Purpose : Aggregate all discrepancies by root cause type,
--           compute severity and financial exposure
-- Used by : Root cause analysis, Process improvement
-- ────────────────────────────────────────────────────────────
SELECT
    t.root_cause,
    COUNT(t.transaction_id)                             AS total_cases,
    ROUND(COUNT(t.transaction_id) * 100.0 /
        (SELECT COUNT(*) FROM transactions WHERE status = 'Discrepancy'), 1)
                                                        AS pct_of_all_discrepancies,
    ROUND(SUM(ABS(t.discrepancy_amount)), 2)            AS total_amount_at_risk,
    ROUND(AVG(ABS(t.discrepancy_amount)), 2)            AS avg_discrepancy_amount,
    SUM(CASE WHEN t.discrepancy_amount > 0 THEN 1 ELSE 0 END) AS overpayments,
    SUM(CASE WHEN t.discrepancy_amount < 0 THEN 1 ELSE 0 END) AS underpayments,
    SUM(CASE WHEN t.sla_breach = 1 THEN 1 ELSE 0 END)  AS sla_breaches_associated,
    CASE
        WHEN SUM(ABS(t.discrepancy_amount)) > 30000
             OR COUNT(*) > 80                          THEN 'CRITICAL'
        WHEN SUM(ABS(t.discrepancy_amount)) > 15000
             OR COUNT(*) > 40                          THEN 'HIGH'
        WHEN SUM(ABS(t.discrepancy_amount)) > 5000
             OR COUNT(*) > 15                          THEN 'MEDIUM'
        ELSE 'LOW'
    END                                                 AS severity_level
FROM transactions t
WHERE t.status = 'Discrepancy'
  AND t.root_cause != 'NONE'
GROUP BY t.root_cause
ORDER BY total_amount_at_risk DESC;


-- ────────────────────────────────────────────────────────────
-- QUERY 3: SLA Breach Tracker with Aging Analysis
-- Purpose : Identify all discrepancies breaching 48hr SLA,
--           sorted by financial exposure and age
-- Used by : Operations team, daily standup
-- ────────────────────────────────────────────────────────────
SELECT
    t.transaction_id,
    s.seller_name,
    s.tier,
    t.month,
    t.category,
    ROUND(t.gmv, 2)                                     AS gmv,
    ROUND(t.expected_payout, 2)                         AS expected_payout,
    ROUND(t.actual_payout, 2)                           AS actual_payout,
    ROUND(t.discrepancy_amount, 2)                      AS discrepancy_amount,
    CASE
        WHEN t.discrepancy_amount > 0 THEN 'OVERPAYMENT'
        ELSE 'UNDERPAYMENT'
    END                                                 AS discrepancy_type,
    t.root_cause,
    t.days_outstanding,
    CASE
        WHEN t.days_outstanding <= 2   THEN '0-2d (OK)'
        WHEN t.days_outstanding <= 7   THEN '3-7d (Warning)'
        WHEN t.days_outstanding <= 14  THEN '8-14d (Overdue)'
        ELSE '15+d (CRITICAL)'
    END                                                 AS aging_bucket,
    t.resolution_status
FROM transactions t
JOIN sellers s ON t.seller_id = s.seller_id
WHERE t.sla_breach = 1
ORDER BY t.days_outstanding DESC,
         ABS(t.discrepancy_amount) DESC;


-- ────────────────────────────────────────────────────────────
-- QUERY 4: Seller Risk Scoring Formula
-- Purpose : Compute multi-factor risk score for each seller
--           combining discrepancy rate, SLA history, return rate
-- Used by : Seller risk management, Account review
-- ────────────────────────────────────────────────────────────
SELECT
    t.seller_id,
    s.seller_name,
    s.tier,
    s.category,
    s.state,
    COUNT(t.transaction_id)                             AS total_transactions,
    ROUND(SUM(t.gmv), 2)                                AS total_gmv,
    SUM(CASE WHEN t.status='Discrepancy' THEN 1 ELSE 0 END)
                                                        AS discrepancy_count,
    ROUND(
        SUM(CASE WHEN t.status='Discrepancy' THEN 1.0 ELSE 0 END)
        / COUNT(t.transaction_id) * 100, 2
    )                                                   AS discrepancy_rate_pct,
    SUM(CASE WHEN t.sla_breach=1 THEN 1 ELSE 0 END)    AS sla_breaches,
    ROUND(AVG(t.days_outstanding), 1)                   AS avg_days_outstanding,
    COUNT(DISTINCT CASE WHEN t.root_cause!='NONE' THEN t.root_cause END)
                                                        AS unique_root_causes,
    -- Composite Risk Score (0-100)
    ROUND(
        LEAST(40,
            SUM(CASE WHEN t.status='Discrepancy' THEN 1.0 ELSE 0 END)
            / COUNT(t.transaction_id) * 400
        )
        + LEAST(20, SUM(CASE WHEN t.sla_breach=1 THEN 1 ELSE 0 END) * 1.5)
        + LEAST(15, COUNT(DISTINCT CASE WHEN t.root_cause!='NONE'
                          THEN t.root_cause END) * 3)
        + LEAST(15, s.return_rate * 80)
        + LEAST(10, AVG(t.days_outstanding) / 5)
    , 1)                                                AS computed_risk_score,
    CASE
        WHEN ROUND(
            LEAST(40,
                SUM(CASE WHEN t.status='Discrepancy' THEN 1.0 ELSE 0 END)
                / COUNT(t.transaction_id) * 400
            )
            + LEAST(20, SUM(CASE WHEN t.sla_breach=1 THEN 1 ELSE 0 END) * 1.5)
            + LEAST(15, COUNT(DISTINCT CASE WHEN t.root_cause!='NONE'
                              THEN t.root_cause END) * 3)
            + LEAST(15, s.return_rate * 80)
            + LEAST(10, AVG(t.days_outstanding) / 5)
        , 1) >= 70 THEN 'CRITICAL'
        WHEN ROUND(
            LEAST(40,
                SUM(CASE WHEN t.status='Discrepancy' THEN 1.0 ELSE 0 END)
                / COUNT(t.transaction_id) * 400
            )
            + LEAST(20, SUM(CASE WHEN t.sla_breach=1 THEN 1 ELSE 0 END) * 1.5)
        , 1) >= 50 THEN 'HIGH'
        WHEN ROUND(
            LEAST(40,
                SUM(CASE WHEN t.status='Discrepancy' THEN 1.0 ELSE 0 END)
                / COUNT(t.transaction_id) * 400
            )
        , 1) >= 30 THEN 'MEDIUM'
        ELSE 'LOW'
    END                                                 AS risk_tier
FROM transactions t
JOIN sellers s ON t.seller_id = s.seller_id
GROUP BY t.seller_id, s.seller_name, s.tier, s.category, s.state, s.return_rate
ORDER BY computed_risk_score DESC;


-- ────────────────────────────────────────────────────────────
-- QUERY 5: Category-Level Payout & Refund Analysis
-- Purpose : Benchmark category performance, identify high-risk
--           categories with elevated discrepancy/refund rates
-- Used by : Category management, FinOps planning
-- ────────────────────────────────────────────────────────────
SELECT
    t.category,
    COUNT(DISTINCT t.seller_id)                         AS active_sellers,
    COUNT(t.transaction_id)                             AS total_transactions,
    ROUND(SUM(t.gmv), 2)                                AS total_gmv,
    ROUND(AVG(t.gmv), 2)                                AS avg_transaction_gmv,
    ROUND(SUM(t.commission), 2)                         AS total_commission_earned,
    ROUND(SUM(t.actual_payout), 2)                      AS total_net_payout,
    ROUND(SUM(t.return_amount), 2)                      AS total_returns,
    ROUND(SUM(t.return_amount) / SUM(t.gmv) * 100, 2)  AS return_rate_pct,
    SUM(CASE WHEN t.status='Discrepancy' THEN 1 ELSE 0 END)
                                                        AS discrepancy_count,
    ROUND(
        SUM(CASE WHEN t.status='Discrepancy' THEN 1.0 ELSE 0 END)
        / COUNT(t.transaction_id) * 100, 2
    )                                                   AS discrepancy_rate_pct,
    ROUND(SUM(ABS(t.discrepancy_amount)), 2)            AS total_discrepancy_amount,
    -- Category health flag
    CASE
        WHEN SUM(CASE WHEN t.status='Discrepancy' THEN 1.0 ELSE 0 END)
             / COUNT(t.transaction_id) * 100 > 10      THEN '🔴 HIGH RISK'
        WHEN SUM(CASE WHEN t.status='Discrepancy' THEN 1.0 ELSE 0 END)
             / COUNT(t.transaction_id) * 100 > 7       THEN '🟡 MEDIUM RISK'
        ELSE '🟢 HEALTHY'
    END                                                 AS category_health
FROM transactions t
GROUP BY t.category
ORDER BY total_gmv DESC;


-- ────────────────────────────────────────────────────────────
-- QUERY 6: Month-over-Month Growth & Trend Analysis
-- Purpose : Track GMV, payout, and discrepancy trends for
--           business review and forecasting
-- Used by : Business review, leadership reporting
-- ────────────────────────────────────────────────────────────
WITH monthly_base AS (
    SELECT
        month,
        ROUND(SUM(gmv), 2)             AS total_gmv,
        ROUND(SUM(actual_payout), 2)   AS total_payout,
        SUM(CASE WHEN status='Discrepancy' THEN 1 ELSE 0 END) AS disc_count,
        ROUND(SUM(ABS(discrepancy_amount)), 2) AS disc_amount,
        SUM(CASE WHEN sla_breach=1 THEN 1 ELSE 0 END) AS sla_breaches
    FROM transactions
    GROUP BY month
),
with_prev AS (
    SELECT
        m.*,
        LAG(m.total_gmv)    OVER (ORDER BY m.month) AS prev_gmv,
        LAG(m.total_payout) OVER (ORDER BY m.month) AS prev_payout,
        LAG(m.disc_count)   OVER (ORDER BY m.month) AS prev_disc_count
    FROM monthly_base m
)
SELECT
    month,
    total_gmv,
    total_payout,
    disc_count,
    disc_amount,
    sla_breaches,
    CASE WHEN prev_gmv IS NOT NULL
        THEN ROUND((total_gmv - prev_gmv) / prev_gmv * 100, 2)
        ELSE NULL
    END                                               AS gmv_mom_growth_pct,
    CASE WHEN prev_payout IS NOT NULL
        THEN ROUND((total_payout - prev_payout) / prev_payout * 100, 2)
        ELSE NULL
    END                                               AS payout_mom_growth_pct,
    CASE WHEN prev_disc_count IS NOT NULL AND prev_disc_count > 0
        THEN ROUND((disc_count - prev_disc_count) * 100.0 / prev_disc_count, 2)
        ELSE NULL
    END                                               AS disc_mom_change_pct
FROM with_prev
ORDER BY month;


-- ────────────────────────────────────────────────────────────
-- QUERY 7: Seller-Facing Payout Statement (per seller)
-- Purpose : Generate clean individual payout breakdown
--           for seller portal transparency
-- Used by : Seller communication, dispute resolution
-- Param   : Replace 'SLR1000' with actual seller_id
-- ────────────────────────────────────────────────────────────
SELECT
    t.transaction_id,
    t.transaction_date,
    t.month,
    t.category,
    ROUND(t.gmv, 2)                                     AS gross_sale_value,
    ROUND(t.commission, 2)                              AS platform_commission,
    ROUND(t.gst_on_commission, 2)                       AS gst_on_commission,
    ROUND(t.shipping_fee, 2)                            AS shipping_deduction,
    ROUND(t.return_amount, 2)                           AS return_deduction,
    ROUND(t.expected_payout, 2)                         AS calculated_payout,
    ROUND(t.actual_payout, 2)                           AS actual_payout_disbursed,
    ROUND(t.discrepancy_amount, 2)                      AS discrepancy,
    t.status,
    CASE WHEN t.status = 'Discrepancy' THEN t.root_cause ELSE '—' END AS discrepancy_reason,
    t.resolution_status
FROM transactions t
JOIN sellers s ON t.seller_id = s.seller_id
WHERE t.seller_id = 'SLR1000'  -- Replace with actual seller_id
ORDER BY t.transaction_date DESC;


-- ────────────────────────────────────────────────────────────
-- QUERY 8: Duplicate Transaction Detection
-- Purpose : Surface potential duplicate payouts — same seller,
--           same amount, same month, within 24hr window
-- Used by : Fraud prevention, audit
-- ────────────────────────────────────────────────────────────
SELECT
    a.seller_id,
    s.seller_name,
    a.transaction_id          AS txn_1,
    b.transaction_id          AS txn_2,
    a.transaction_date        AS date_1,
    b.transaction_date        AS date_2,
    ROUND(a.actual_payout, 2) AS payout_1,
    ROUND(b.actual_payout, 2) AS payout_2,
    ROUND(a.actual_payout + b.actual_payout, 2) AS combined_exposure
FROM transactions a
JOIN transactions b
    ON  a.seller_id = b.seller_id
    AND a.month     = b.month
    AND a.transaction_id < b.transaction_id
    AND ROUND(a.actual_payout, 0) = ROUND(b.actual_payout, 0)
JOIN sellers s ON a.seller_id = s.seller_id
WHERE a.root_cause = 'DUPLICATE_TRANSACTION'
   OR b.root_cause = 'DUPLICATE_TRANSACTION'
ORDER BY combined_exposure DESC
LIMIT 25;


-- ────────────────────────────────────────────────────────────
-- QUERY 9: Stakeholder Alert Query — Critical Unresolved Items
-- Purpose : Single-query daily alert for the FinOps lead
--           covering all critical open items
-- Used by : Morning standup, escalation emails
-- ────────────────────────────────────────────────────────────
SELECT
    'SLA Breach 15+ Days'        AS alert_type,
    COUNT(*)                     AS count,
    ROUND(SUM(ABS(discrepancy_amount)), 2) AS amount_at_risk,
    'CRITICAL'                   AS priority,
    'Operations Lead'            AS owner
FROM transactions
WHERE sla_breach = 1
  AND days_outstanding >= 15
  AND resolution_status != 'Resolved'

UNION ALL

SELECT
    'Duplicate Transactions'     AS alert_type,
    COUNT(*)                     AS count,
    ROUND(SUM(ABS(discrepancy_amount)), 2) AS amount_at_risk,
    'P0 CRITICAL'                AS priority,
    'FinOps Lead'                AS owner
FROM transactions
WHERE root_cause = 'DUPLICATE_TRANSACTION'
  AND resolution_status = 'Pending'

UNION ALL

SELECT
    'Manual Override Anomalies'  AS alert_type,
    COUNT(*)                     AS count,
    ROUND(SUM(ABS(discrepancy_amount)), 2) AS amount_at_risk,
    'HIGH'                       AS priority,
    'Finance Controller'         AS owner
FROM transactions
WHERE root_cause = 'MANUAL_ADJUSTMENT_OVERRIDE'
  AND resolution_status = 'Pending'

ORDER BY amount_at_risk DESC;
