-- Multi-factor composite score: momentum + value (P/E) + earnings quality.
-- Each stock is ranked 1..N on each factor, then factor ranks are summed to
-- produce a composite score — lower is better on all three.
-- Stocks at the top combine price momentum with cheap valuation and a history
-- of beating estimates, the classic "quality momentum" long candidate.
-- Demonstrates: multi-CTE chain, cross-factor rank aggregation, RANK over
--               composite score, full five-table join path.

WITH

-- ── Factor 1: 12-1 month momentum ────────────────────────────────────────────
latest_date AS (
    SELECT MAX(date) AS d FROM daily_prices
),

monthly_prices AS (
    SELECT
        security_id,
        DATE_TRUNC('month', date)                                               AS month,
        LAST_VALUE(adj_close) OVER (
            PARTITION BY security_id, DATE_TRUNC('month', date)
            ORDER BY date
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        )                                                                        AS eom_price
    FROM daily_prices
),

monthly_dedup AS (
    SELECT DISTINCT security_id, month, eom_price FROM monthly_prices
),

momentum_calc AS (
    SELECT
        security_id,
        (LAG(eom_price, 1)  OVER (PARTITION BY security_id ORDER BY month)
         / NULLIF(LAG(eom_price, 12) OVER (PARTITION BY security_id ORDER BY month), 0))
        - 1                                                                      AS momentum_12_1,
        month
    FROM monthly_dedup
),

momentum_latest AS (
    SELECT security_id, momentum_12_1
    FROM   momentum_calc
    WHERE  month = DATE_TRUNC('month', (SELECT d FROM latest_date))
      AND  momentum_12_1 IS NOT NULL
),

-- ── Factor 2: P/E value ───────────────────────────────────────────────────────
latest_price AS (
    SELECT DISTINCT ON (security_id)
        security_id,
        adj_close AS current_price
    FROM  daily_prices
    ORDER BY security_id, date DESC
),

latest_fundamentals AS (
    SELECT DISTINCT ON (security_id)
        security_id,
        eps,
        fiscal_quarter
    FROM  fundamentals
    WHERE eps IS NOT NULL AND eps > 0          -- positive earnings only
    ORDER BY security_id, fiscal_quarter DESC
),

pe_calc AS (
    SELECT
        lp.security_id,
        ROUND(lp.current_price / lf.eps, 2)   AS pe_ratio
    FROM latest_price       lp
    JOIN latest_fundamentals lf USING (security_id)
),

-- ── Factor 3: trailing 4-quarter earnings surprise ────────────────────────────
earnings_calc AS (
    SELECT DISTINCT ON (security_id)
        security_id,
        ROUND(
            AVG(eps_actual - eps_estimate) OVER (
                PARTITION BY security_id
                ORDER BY fiscal_quarter
                ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
            ), 4
        )                                      AS trailing_4q_surprise
    FROM analyst_estimates
    WHERE eps_estimate IS NOT NULL
      AND eps_actual   IS NOT NULL
    ORDER BY security_id, fiscal_quarter DESC
),

-- ── Per-factor ranks (1 = best) ───────────────────────────────────────────────
factor_ranks AS (
    SELECT
        m.security_id,
        ROUND(m.momentum_12_1 * 100, 2)                                         AS momentum_pct,
        v.pe_ratio,
        e.trailing_4q_surprise,
        RANK() OVER (ORDER BY m.momentum_12_1      DESC)                        AS momentum_rank,
        RANK() OVER (ORDER BY v.pe_ratio           ASC)                         AS value_rank,
        RANK() OVER (ORDER BY e.trailing_4q_surprise DESC)                      AS earnings_rank
    FROM     momentum_latest m
    JOIN     pe_calc          v USING (security_id)
    JOIN     earnings_calc    e USING (security_id)
)

-- ── Composite ─────────────────────────────────────────────────────────────────
SELECT
    s.ticker,
    s.company_name,
    sec.sector_name,
    f.momentum_pct,
    f.pe_ratio,
    f.trailing_4q_surprise,
    f.momentum_rank,
    f.value_rank,
    f.earnings_rank,
    (f.momentum_rank + f.value_rank + f.earnings_rank)                          AS composite_score,
    RANK() OVER (ORDER BY (f.momentum_rank + f.value_rank + f.earnings_rank))   AS composite_rank
FROM   factor_ranks f
JOIN   securities   s   USING (security_id)
JOIN   sectors      sec USING (sector_id)
ORDER  BY composite_rank;
