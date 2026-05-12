-- ============================================================
-- Stock Screener Schema
-- ============================================================

CREATE TABLE sectors (
    sector_id   SERIAL PRIMARY KEY,
    sector_name VARCHAR(50)  NOT NULL UNIQUE,
    industry    VARCHAR(100)
);

CREATE TABLE securities (
    security_id     SERIAL PRIMARY KEY,
    ticker          VARCHAR(10)  NOT NULL UNIQUE,
    company_name    VARCHAR(100) NOT NULL,
    sector_id       INT REFERENCES sectors(sector_id),
    market_cap_tier VARCHAR(10) CHECK (market_cap_tier IN ('large', 'mid', 'small'))
);

CREATE TABLE daily_prices (
    security_id INT  NOT NULL REFERENCES securities(security_id),
    date        DATE NOT NULL,
    open        NUMERIC(12, 4),
    high        NUMERIC(12, 4),
    low         NUMERIC(12, 4),
    close       NUMERIC(12, 4),
    volume      BIGINT,
    adj_close   NUMERIC(12, 4),
    PRIMARY KEY (security_id, date)
);

CREATE TABLE fundamentals (
    security_id          INT  NOT NULL REFERENCES securities(security_id),
    fiscal_quarter       DATE NOT NULL,
    revenue              NUMERIC(18, 2),
    net_income           NUMERIC(18, 2),
    total_assets         NUMERIC(18, 2),
    total_equity         NUMERIC(18, 2),
    shares_outstanding   BIGINT,
    eps                  NUMERIC(10, 4),
    book_value_per_share NUMERIC(10, 4),
    PRIMARY KEY (security_id, fiscal_quarter)
);

CREATE TABLE analyst_estimates (
    security_id    INT  NOT NULL REFERENCES securities(security_id),
    fiscal_quarter DATE NOT NULL,
    eps_estimate   NUMERIC(10, 4),
    eps_actual     NUMERIC(10, 4),
    PRIMARY KEY (security_id, fiscal_quarter)
);

-- Indexes for time-series query performance
CREATE INDEX idx_prices_date        ON daily_prices (date);
CREATE INDEX idx_prices_security    ON daily_prices (security_id, date DESC);
CREATE INDEX idx_fundamentals_qtr   ON fundamentals (fiscal_quarter);
CREATE INDEX idx_estimates_qtr      ON analyst_estimates (fiscal_quarter);
