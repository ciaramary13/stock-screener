-- Value factor screen: P/E and P/B ratios from the most recent quarter,
-- ranked within sector. Low ratio = cheap relative to fundamentals.
-- Demonstrates: lateral-style CTE for latest row per group, ratio derivation,
--               NTILE bucketing, multi-join.

WITH latest_price AS (
    SELECT DISTINCT ON (security_id)
        security_id,
        adj_close AS current_price
    FROM daily_prices
    ORDER BY security_id, date DESC
),

latest_fundamentals AS (
    SELECT DISTINCT ON (security_id)
        security_id,
        eps,
        book_value_per_share,
        fiscal_quarter
    FROM fundamentals
    WHERE eps IS NOT NULL
    ORDER BY security_id, fiscal_quarter DESC
),

ratios AS (
    SELECT
        lp.security_id,
        lp.current_price,
        lf.fiscal_quarter,
        ROUND(lp.current_price / NULLIF(lf.eps, 0), 2)                AS pe_ratio,
        ROUND(lp.current_price / NULLIF(lf.book_value_per_share, 0), 2) AS pb_ratio
    FROM latest_price      lp
    JOIN latest_fundamentals lf USING (security_id)
)

SELECT
    s.ticker,
    s.company_name,
    sec.sector_name,
    r.fiscal_quarter,
    r.current_price,
    r.pe_ratio,
    r.pb_ratio,
    RANK()  OVER (PARTITION BY s.sector_id ORDER BY r.pe_ratio ASC)  AS sector_pe_rank,
    RANK()  OVER (PARTITION BY s.sector_id ORDER BY r.pb_ratio ASC)  AS sector_pb_rank,
    NTILE(5) OVER (ORDER BY r.pe_ratio ASC)                           AS pe_quintile   -- 1 = cheapest
FROM ratios     r
JOIN securities s   USING (security_id)
JOIN sectors    sec USING (sector_id)
WHERE r.pe_ratio > 0   -- exclude negative earnings
ORDER BY r.pe_ratio;
