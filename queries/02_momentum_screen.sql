-- 12-1 month price momentum, ranked within each sector.
-- Classic Jegadeesh-Titman factor: 12-month return skipping the most recent month.
-- Demonstrates: LAG, CTE chain, RANK with PARTITION BY, multi-table JOIN.

WITH latest_date AS (
    SELECT MAX(date) AS d FROM daily_prices
),

monthly_prices AS (
    -- Close price on (approximately) the last trading day of each calendar month
    SELECT
        security_id,
        DATE_TRUNC('month', date) AS month,
        LAST_VALUE(adj_close) OVER (
            PARTITION BY security_id, DATE_TRUNC('month', date)
            ORDER BY date
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS eom_price
    FROM daily_prices
),

deduplicated AS (
    SELECT DISTINCT security_id, month, eom_price FROM monthly_prices
),

momentum AS (
    SELECT
        security_id,
        month,
        eom_price,
        LAG(eom_price, 1)  OVER (PARTITION BY security_id ORDER BY month) AS price_1m_ago,
        LAG(eom_price, 12) OVER (PARTITION BY security_id ORDER BY month) AS price_12m_ago
    FROM deduplicated
),

latest_momentum AS (
    SELECT
        security_id,
        (price_1m_ago / NULLIF(price_12m_ago, 0)) - 1 AS momentum_12_1
    FROM momentum
    WHERE month = DATE_TRUNC('month', (SELECT d FROM latest_date))
)

SELECT
    s.ticker,
    s.company_name,
    sec.sector_name,
    ROUND(lm.momentum_12_1 * 100, 2)                                          AS momentum_pct,
    RANK() OVER (PARTITION BY s.sector_id ORDER BY lm.momentum_12_1 DESC)     AS sector_rank,
    RANK() OVER (ORDER BY lm.momentum_12_1 DESC)                               AS universe_rank
FROM latest_momentum lm
JOIN securities      s   USING (security_id)
JOIN sectors         sec USING (sector_id)
ORDER BY universe_rank;
