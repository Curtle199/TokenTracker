from __future__ import annotations

import math
import re
from datetime import datetime
from pathlib import Path

from playwright.sync_api import sync_playwright

WOWTOKEN_URL = "https://wowtoken.app/"
OUTPUT_FILE = Path(r"C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\TokenTracker\TokenTrackerExternal.lua")


def load_existing_history(path: Path) -> list[dict]:
    if not path.exists():
        return []

    text = path.read_text(encoding="utf-8", errors="ignore")
    matches = re.findall(r'\{ time = "([^"]+)", priceGold = (\d+) \}', text)

    history = []
    for time_str, price in matches:
        history.append({"time": time_str, "priceGold": int(price)})
    return history


def compute_analytics(history: list[dict]) -> dict:
    if not history:
        return {
            "avg24": 0,
            "low24": 0,
            "high24": 0,
            "trend": "unknown",
            "bestBuyWindow": {"low": 0, "high": 0, "verdict": "No data"},
        }

    prices = [entry["priceGold"] for entry in history]
    avg24 = math.floor(sum(prices) / len(prices))
    low24 = min(prices)
    high24 = max(prices)

    if len(prices) >= 2:
        if prices[0] > prices[1]:
            trend = "rising"
        elif prices[0] < prices[1]:
            trend = "falling"
        else:
            trend = "flat"
    else:
        trend = "flat"

    current = prices[0]
    window_low = low24
    window_high = math.floor(low24 + (avg24 - low24) * 0.35)

    if window_high < window_low:
        window_high = window_low

    if current <= window_high:
        verdict = "STRONG BUY" if current <= low24 * 1.01 else "BUY"
    elif current <= avg24:
        verdict = "WAIT"
    else:
        verdict = "AVOID"

    return {
        "avg24": avg24,
        "low24": low24,
        "high24": high24,
        "trend": trend,
        "bestBuyWindow": {
            "low": window_low,
            "high": window_high,
            "verdict": verdict,
        },
    }


def write_lua(path: Path, current_price: int, history: list[dict], analytics: dict) -> None:
    updated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    history_lua = ",\n        ".join(
        f'{{ time = "{entry["time"]}", priceGold = {entry["priceGold"]} }}'
        for entry in history[:24]
    )

    lua = f'''TokenTrackerExternalDB = {{
    source = "wowtoken.app",
    region = "US",
    updatedAt = "{updated_at}",
    currentPriceGold = {current_price},
    history = {{
        {history_lua}
    }},
    analytics = {{
        avg24 = {analytics["avg24"]},
        low24 = {analytics["low24"]},
        high24 = {analytics["high24"]},
        trend = "{analytics["trend"]}",
        bestBuyWindow = {{
            low = {analytics["bestBuyWindow"]["low"]},
            high = {analytics["bestBuyWindow"]["high"]},
            verdict = "{analytics["bestBuyWindow"]["verdict"]}",
        }},
    }},
}}
'''
    path.write_text(lua, encoding="utf-8")


def parse_price_from_rendered_text(text: str) -> int | None:
    patterns = [
        r'1 Token\s*=\s*([0-9,]+)\s*Gold',
        r'Current[^0-9]*([0-9,]{5,})',
        r'([0-9,]{5,})\s*Gold',
    ]

    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            value = int(match.group(1).replace(",", ""))
            if value > 0:
                return value

    return None


def fetch_rendered_price() -> int:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto(WOWTOKEN_URL, wait_until="networkidle", timeout=60000)

        # Give the site a moment in case the data fills after initial render.
        page.wait_for_timeout(5000)

        text = page.locator("body").inner_text()
        browser.close()

    price = parse_price_from_rendered_text(text)
    if price is None:
        raise RuntimeError("Could not parse token price from rendered wowtoken.app page text.")
    return price


def main() -> None:
    current_price = fetch_rendered_price()

    history = load_existing_history(OUTPUT_FILE)
    now_label = datetime.now().strftime("%m/%d %H:%M")

    if not history or history[0]["priceGold"] != current_price:
        history.insert(0, {"time": now_label, "priceGold": current_price})

    history = history[:48]
    analytics = compute_analytics(history)
    write_lua(OUTPUT_FILE, current_price, history, analytics)

    print(f"Updated token price: {current_price}g")


if __name__ == "__main__":
    main()