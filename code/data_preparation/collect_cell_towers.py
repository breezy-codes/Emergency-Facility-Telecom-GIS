"""
Download and prepare the Australian cell tower dataset from BitBot's API.

The script downloads tower data for Optus, Telstra, and Vodafone, saves the
raw carrier datasets, combines them into a single dataset, and aggregates
records by site_id so that each site contains a list of carriers present.
"""

import json
from pathlib import Path

import pandas as pd
import requests


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
TOWERS_DIR = BASE_DIR / "telecommunications_datasets"

TOWERS_DIR.mkdir(parents=True, exist_ok=True)


# BitBot API endpoints
BASE_URL = "https://api.bitbot.com.au/api/towers"

DATASETS = {
    "optus": f"{BASE_URL}/optus/",
    "telstra": f"{BASE_URL}/telstra/",
    "vodafone": f"{BASE_URL}/vodafone/",
}


def download_dataset(name, url):
    """Download and save the tower dataset for a single carrier."""
    rows = []
    raw_rows = []
    start = 0

    while True:
        response = requests.get(
            f"{url}?_start={start}&_view=json",
            timeout=60,
        )
        response.raise_for_status()

        data = response.json()
        batch = data["restify"]["rows"]

        if not batch:
            break

        print(f"{name}: {len(rows) + len(batch):,} records")

        raw_rows.extend(batch)

        for row in batch:
            values = row["values"]

            rows.append({
                "site_id": values.get("site_id", {}).get("value"),
                "latitude": values.get("latitude", {}).get("value"),
                "longitude": values.get("longitude", {}).get("value"),
                "name": values.get("name", {}).get("value"),
                "state": values.get("state", {}).get("value"),
                "postcode": values.get("postcode", {}).get("value"),
                "site_precision": values.get("site_precision", {}).get("value"),
                "elevation": values.get("elevation", {}).get("value"),
                "geohash": values.get("geohash", {}).get("value"),
                "carrier": name,
            })

        start += len(batch)

    with open(TOWERS_DIR / f"{name}.json", "w", encoding="utf-8") as file:
        json.dump(raw_rows, file, indent=2)

    dataframe = pd.DataFrame(rows)
    dataframe.to_csv(TOWERS_DIR / f"{name}.csv", index=False)

    return dataframe


def combine_datasets(carrier_datasets):
    """Combine the individual carrier datasets."""
    combined = pd.concat(carrier_datasets, ignore_index=True)

    combined.to_csv(
        TOWERS_DIR / "all_carriers_raw.csv",
        index=False,
    )

    combined.to_json(
        TOWERS_DIR / "all_carriers_raw.json",
        orient="records",
        indent=2,
    )

    return combined


def aggregate_sites(combined):
    """Aggregate carrier records by unique site_id."""
    cleaned = (
        combined
        .groupby("site_id", dropna=False)
        .agg({
            "latitude": "first",
            "longitude": "first",
            "name": "first",
            "state": "first",
            "postcode": "first",
            "site_precision": "first",
            "elevation": "first",
            "geohash": "first",
            "carrier": lambda carriers: sorted(set(carriers)),
        })
        .reset_index()
    )

    cleaned["carrier_count"] = cleaned["carrier"].apply(len)

    return cleaned


def save_cleaned_dataset(cleaned):
    """Save the aggregated tower dataset as CSV and JSON."""
    cleaned.to_csv(
        TOWERS_DIR / "mobile_sites_cleaned.csv",
        index=False,
    )

    cleaned.to_json(
        TOWERS_DIR / "mobile_sites_cleaned.json",
        orient="records",
        indent=2,
    )


def main():
    """Download, combine, and prepare the cell tower datasets."""
    print("Downloading cell tower datasets...")

    carrier_datasets = [
        download_dataset(carrier, url)
        for carrier, url in DATASETS.items()
    ]

    print("\nCombining carrier datasets...")
    combined = combine_datasets(carrier_datasets)

    print("Aggregating tower sites...")
    cleaned = aggregate_sites(combined)

    print("Saving cleaned dataset...")
    save_cleaned_dataset(cleaned)

    print("\nResults")
    print("=" * 40)
    print(f"Combined records: {len(combined):,}")
    print(f"Unique sites:     {len(cleaned):,}")
    print(f"Output directory: {TOWERS_DIR}")


if __name__ == "__main__":
    main()