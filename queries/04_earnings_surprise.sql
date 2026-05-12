-- Earnings surprise magnitude and direction, with trailing 4-quarter average.
-- Demonstrates: derived columns, aggregation, window functions over time,
--               CASE expressions, multi-join.

WITH surprises AS (
    SELECT
        e.security_id,
        e.fiscal_quarter,
        e.eps_actual,
        e.eps_estimate,
        e.eps_actual - e.eps_estimate                                      AS surprise_abs,
        ROUND(
            (e.eps_actual - e.eps_estimate) / NULLIF(ABS(e.eps_estimate), 0) * 100,
            2
        )                                                                  AS surprise_pct,
        AVG(e.eps_actual - e.eps_estimate) OVER (
            PARTITION BY e.security_id
            ORDER BY e.fiscal_quarter
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        )                                                                  AS trailing_4q_avg_surprise
    FROM analyst_estimates e
    WHERE e.eps_estimate IS NOT NULL
      AND e.eps_actual   IS NOT NULL
)

SELECT
    s.ticker,
    s.company_name,
    sec.sector_name,
    sur.fiscal_quarter,
    sur.eps_estimate,
    sur.eps_actual,
    sur.surprise_abs,
    sur.surprise_pct,
    ROUND(sur.trailing_4q_avg_surprise, 4)                               AS trailing_4q_avg_surprise,
    CASE
        WHEN sur.surprise_pct >  5 THEN 'large beat'
        WHEN sur.surprise_pct >  0 THEN 'beat'
        WHEN sur.surprise_pct = 0  THEN 'in-line'
        WHEN sur.surprise_pct > -5 THEN 'miss'
        ELSE                            'large miss'
    END                                                                  AS outcome
FROM surprises  sur
JOIN securities s   USING (security_id)
JOIN sectors    sec USING (sector_id)
ORDER BY sur.fiscal_quarter DESC, ABS(sur.surprise_pct) DESC;
