import os
import logging
import yfinance as yf
import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

UNIVERSE = [
    # Technology
    "AAPL", "MSFT", "NVDA", "GOOGL", "META",
    # Financials
    "JPM", "BAC", "GS", "WFC", "MS",
    # Healthcare
    "JNJ", "UNH", "PFE", "MRK", "ABBV",
    # Consumer Discretionary
    "AMZN", "TSLA", "HD", "MCD", "NKE",
    # Industrials
    "CAT", "GE", "HON", "UPS", "DE",
    # Energy
    "XOM", "CVX", "COP", "SLB", "EOG",
    # Materials
    "LIN", "APD", "ECL", "NEM", "FCX",
    # Utilities
    "NEE", "DUK", "SO", "AEP", "EXC",
    # Real Estate
    "PLD", "AMT", "CCI", "EQIX", "SPG",
    # Consumer Staples
    "PG", "KO", "PEP", "COST", "WMT",
    # Communication Services
    "NFLX", "DIS", "VZ", "T", "CMCSA",
]

PRICE_PERIOD = "2y"


def get_conn():
    return psycopg2.connect(os.environ["DATABASE_URL"])


def market_cap_tier(mc):
    if mc is None:
        return None
    if mc >= 10_000_000_000:
        return "large"
    if mc >= 2_000_000_000:
        return "mid"
    return "small"


def upsert_sector(cur, sector_name):
    cur.execute(
        """
        INSERT INTO sectors (sector_name)
        VALUES (%s)
        ON CONFLICT (sector_name) DO NOTHING
        RETURNING sector_id
        """,
        (sector_name,),
    )
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute("SELECT sector_id FROM sectors WHERE sector_name = %s", (sector_name,))
    return cur.fetchone()[0]


def ingest_securities(cur, ticker_info: dict):
    sector_name = ticker_info.get("sector") or "Unknown"
    sector_id = upsert_sector(cur, sector_name)
    tier = market_cap_tier(ticker_info.get("marketCap"))

    cur.execute(
        """
        INSERT INTO securities (ticker, company_name, sector_id, market_cap_tier)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (ticker) DO UPDATE
            SET company_name    = EXCLUDED.company_name,
                sector_id       = EXCLUDED.sector_id,
                market_cap_tier = EXCLUDED.market_cap_tier
        RETURNING security_id
        """,
        (
            ticker_info["symbol"],
            ticker_info.get("longName") or ticker_info["symbol"],
            sector_id,
            tier,
        ),
    )
    return cur.fetchone()[0]


def ingest_prices(cur, security_id: int, hist: pd.DataFrame):
    if hist.empty:
        return
    rows = [
        (
            security_id,
            row.Index.date(),
            float(row.Open)  if pd.notna(row.Open)     else None,
            float(row.High)  if pd.notna(row.High)     else None,
            float(row.Low)   if pd.notna(row.Low)      else None,
            float(row.Close) if pd.notna(row.Close)    else None,
            int(row.Volume)  if pd.notna(row.Volume)   else None,
            float(row.Close) if pd.notna(row.Close)    else None,  # adj_close via yfinance auto-adjust
        )
        for row in hist.itertuples()
    ]
    execute_values(
        cur,
        """
        INSERT INTO daily_prices (security_id, date, open, high, low, close, volume, adj_close)
        VALUES %s
        ON CONFLICT (security_id, date) DO NOTHING
        """,
        rows,
    )


def ingest_fundamentals(cur, security_id: int, ticker: yf.Ticker):
    try:
        income = ticker.quarterly_income_stmt
        balance = ticker.quarterly_balance_sheet
    except Exception:
        return

    if income is None or income.empty:
        return

    quarters = income.columns.tolist()
    rows = []
    for q in quarters:
        try:
            revenue    = float(income.loc["Total Revenue", q])          if "Total Revenue"     in income.index else None
            net_income = float(income.loc["Net Income", q])             if "Net Income"        in income.index else None
            eps        = float(income.loc["Basic EPS", q])              if "Basic EPS"         in income.index else None
            t_assets   = float(balance.loc["Total Assets", q])         if "Total Assets"      in balance.index else None
            t_equity   = float(balance.loc["Stockholders Equity", q])  if "Stockholders Equity" in balance.index else None
            shares     = int(balance.loc["Ordinary Shares Number", q]) if "Ordinary Shares Number" in balance.index else None
            bvps       = (t_equity / shares) if (t_equity and shares) else None

            rows.append((
                security_id,
                q.date(),
                revenue,
                net_income,
                t_assets,
                t_equity,
                shares,
                eps,
                bvps,
            ))
        except Exception:
            continue

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO fundamentals
                (security_id, fiscal_quarter, revenue, net_income, total_assets,
                 total_equity, shares_outstanding, eps, book_value_per_share)
            VALUES %s
            ON CONFLICT (security_id, fiscal_quarter) DO NOTHING
            """,
            rows,
        )


def ingest_estimates(cur, security_id: int, ticker: yf.Ticker):
    try:
        hist = ticker.earnings_history
    except Exception:
        return

    if hist is None or hist.empty:
        return

    rows = []
    for row in hist.itertuples():
        try:
            rows.append((
                security_id,
                row.Index.date() if hasattr(row.Index, "date") else None,
                float(row.epsEstimate) if pd.notna(row.epsEstimate) else None,
                float(row.epsActual)   if pd.notna(row.epsActual)   else None,
            ))
        except Exception:
            continue

    rows = [r for r in rows if r[1] is not None]
    if rows:
        execute_values(
            cur,
            """
            INSERT INTO analyst_estimates (security_id, fiscal_quarter, eps_estimate, eps_actual)
            VALUES %s
            ON CONFLICT (security_id, fiscal_quarter) DO NOTHING
            """,
            rows,
        )


def main():
    conn = get_conn()
    try:
        for symbol in UNIVERSE:
            log.info("Processing %s", symbol)
            try:
                t = yf.Ticker(symbol)
                info = t.info
                info["symbol"] = symbol

                with conn:
                    with conn.cursor() as cur:
                        security_id = ingest_securities(cur, info)
                        hist = t.history(period=PRICE_PERIOD, auto_adjust=True)
                        ingest_prices(cur, security_id, hist)
                        ingest_fundamentals(cur, security_id, t)
                        ingest_estimates(cur, security_id, t)

                log.info("  Done: %s (id=%d)", symbol, security_id)
            except Exception as e:
                log.warning("  Skipped %s: %s", symbol, e)
    finally:
        conn.close()

    log.info("Ingestion complete.")


if __name__ == "__main__":
    main()
