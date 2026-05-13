# Stock Screener — SQL Portfolio Project

A normalised PostgreSQL database of equity price and fundamental data, with a Python ingestion pipeline and a suite of factor-based screening queries.

## What it demonstrates

| SQL concept | Where |
|---|---|
| Window functions (`STDDEV`, `LAG`, `RANK`, `NTILE`, `LAST_VALUE`) | All query files |
| CTE chains | `02`, `03`, `05`, `06` |
| `PARTITION BY` across multiple dimensions | `01`, `02`, `05` |
| `DISTINCT ON` for latest-row-per-group | `03`, `06` |
| Multi-table joins across a normalised schema | All query files |
| Derived financial ratios (P/E, P/B, momentum, vol) | `02`, `03`, `06` |
| Cumulative returns via `LN` + `EXP` | `05` |
| Cross-factor rank aggregation (composite score) | `06` |

## Schema

```
sectors ─┐
          ├─ securities ─┬─ daily_prices
                         ├─ fundamentals
                         └─ analyst_estimates
```

Four tables, no denormalised flat files. Prices and fundamentals are stored separately to reflect how real data vendors deliver data.

## Setup

### 1. Create the database

```bash
createdb stock_screener
psql stock_screener -f schema/schema.sql
```

### 2. Configure credentials

```bash
cp .env.example .env
# Edit .env and set DATABASE_URL
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

### 4. Run ingestion

```bash
python ingest/ingest.py
```

Ingests 55 S&P 500 stocks across 11 sectors: ~2 years of daily prices, quarterly income statement and balance sheet data, and earnings history where available. Takes approximately 5–10 minutes.

## Queries

| File | Factor | Key techniques |
|---|---|---|
| `01_rolling_volatility.sql` | Realised vol | `STDDEV` over rolling 20-day window |
| `02_momentum_screen.sql` | 12-1 month momentum | `LAG`, CTE chain, dual `RANK` |
| `03_value_screen.sql` | P/E and P/B | `DISTINCT ON`, ratio derivation, `NTILE` |
| `04_earnings_surprise.sql` | Earnings surprise | `CASE`, trailing 4Q average, beat/miss label |
| `05_sector_attribution.sql` | Sector attribution | Monthly returns, active return vs. universe, 12M cumulative |
| `06_composite_factor_score.sql` | Multi-factor composite | Cross-factor rank aggregation, composite rank, 5-table join |

Run any query directly:

```bash
psql stock_screener -f queries/02_momentum_screen.sql
```

## Sample results (as of May 2026)

### Momentum screen
| Rank | Ticker | Sector | 12-1M Return |
|---|---|---|---|
| 1 | CAT | Industrials | +158% |
| 2 | GOOGL | Communication Services | +125% |
| 3 | NEM | Basic Materials | +118% |
| 4 | FCX | Basic Materials | +68% |
| 5 | SLB | Energy | +62% |

Industrials and Materials dominate the top — CAT benefits from global infrastructure capex; NEM and FCX reflect a commodity/inflation-hedge regime. NVDA ranks 8th (+52%), suggesting the AI momentum trade has broadened beyond a handful of names.

### Earnings surprise (Q1 2026)
Notable misses: SPG (−18%), EQIX (−3.8%), NFLX (−1.4%).  
Notable beats: JNJ, WFC, SLB, ECL.

SPG is the cheapest stock in the universe on P/E (22×) but just delivered a large earnings miss — a classic value trap signal. Cross-referencing momentum (SPG does not appear in the top half) confirms the market has not priced in a recovery.

### Cross-factor signal
NEM and FCX rank in the top 3 for momentum *and* reported earnings beats — a self-reinforcing commodity signal. Running this screen in a portfolio context would produce a long commodity/infrastructure tilt vs. underweight Real Estate and selective Communication Services.

## Data sources

- **Prices & fundamentals**: [yfinance](https://github.com/ranaroussi/yfinance) (Yahoo Finance)
- **Universe**: 55 large-cap US equities across all 11 GICS sectors
