-- Rolling 20-day annualised volatility for every stock on every date.
-- Demonstrates: window functions (STDDEV, ROWS frame), JOIN, derived columns.

SELECT
    s.ticker,
    p.date,
    ROUND(
        STDDEV(p.adj_close) OVER (
            PARTITION BY p.security_id
            ORDER BY p.date
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        )
        / NULLIF(AVG(p.adj_close) OVER (
            PARTITION BY p.security_id
            ORDER BY p.date
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
          ), 0)
        * SQRT(252) * 100,
        2
    ) AS annualised_vol_pct
FROM daily_prices  p
JOIN securities    s USING (security_id)
ORDER BY s.ticker, p.date;
