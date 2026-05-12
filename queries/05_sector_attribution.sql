-- Monthly sector return attribution: average return per sector vs. universe,
-- with cumulative sector return over trailing 12 months.
-- Demonstrates: DATE_TRUNC, GROUP BY, window functions over aggregates,
--               subquery / CTE composition.

WITH monthly_returns AS (
    SELECT
        p.security_id,
        DATE_TRUNC('month', p.date) AS month,
        (
            LAST_VALUE(p.adj_close) OVER (
                PARTITION BY p.security_id, DATE_TRUNC('month', p.date)
                ORDER BY p.date
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            )
            /
            NULLIF(
                FIRST_VALUE(p.adj_close) OVER (
                    PARTITION BY p.security_id, DATE_TRUNC('month', p.date)
                    ORDER BY p.date
                    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                ), 0
            ) - 1
        ) AS monthly_return
    FROM daily_prices p
),

deduplicated AS (
    SELECT DISTINCT security_id, month, monthly_return FROM monthly_returns
),

sector_monthly AS (
    SELECT
        sec.sector_name,
        d.month,
        AVG(d.monthly_return)                                            AS avg_sector_return,
        AVG(AVG(d.monthly_return)) OVER (PARTITION BY d.month)          AS avg_universe_return
    FROM deduplicated d
    JOIN securities   s   USING (security_id)
    JOIN sectors      sec USING (sector_id)
    GROUP BY sec.sector_name, d.month
),

with_cumulative AS (
    SELECT
        sector_name,
        month,
        ROUND(avg_sector_return   * 100, 3) AS sector_return_pct,
        ROUND(avg_universe_return * 100, 3) AS universe_return_pct,
        ROUND((avg_sector_return - avg_universe_return) * 100, 3) AS active_return_pct,
        ROUND(
            EXP(SUM(LN(1 + avg_sector_return)) OVER (
                PARTITION BY sector_name
                ORDER BY month
                ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
            )) - 1,
            4
        ) * 100                                                          AS trailing_12m_cum_return_pct
    FROM sector_monthly
)

SELECT *
FROM with_cumulative
WHERE month >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '12 months')
ORDER BY month DESC, active_return_pct DESC;
