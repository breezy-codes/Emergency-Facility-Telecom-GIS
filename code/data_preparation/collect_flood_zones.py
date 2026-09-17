"""
Download the Victorian flood zone dataset from the ArcGIS REST API.

The dataset is downloaded in pages to avoid request timeouts and API record
limits, then combined and saved as a GeoJSON file.
"""

from io import StringIO
from pathlib import Path

import geopandas as gpd
import pandas as pd
import requests


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
FLOOD_DIR = BASE_DIR / "flood_datasets"

FLOOD_DIR.mkdir(parents=True, exist_ok=True)

OUTPUT_FILE = FLOOD_DIR / "vic_flood.geojson"


# ArcGIS Feature Service
LAYER_URL = "https://services2.arcgis.com/18ajPSI0b3ppsmMt/arcgis/rest/services/VIC_Flood_Overlay/FeatureServer/4"

PAGE_SIZE = 2000


def get_feature_count():
    """Retrieve the total number of features available from the ArcGIS layer."""
    response = requests.get(
        f"{LAYER_URL}/query",
        params={
            "where": "1=1",
            "returnCountOnly": "true",
            "f": "json",
        },
        timeout=60,
    )
    response.raise_for_status()

    data = response.json()

    if "count" not in data:
        raise ValueError(f"Unexpected ArcGIS response: {data}")

    return data["count"]


def download_page(offset, total_features):
    """Download one page of flood zone features."""
    print(
        f"Downloading {offset + 1:,} - "
        f"{min(offset + PAGE_SIZE, total_features):,}"
    )

    response = requests.get(
        f"{LAYER_URL}/query",
        params={
            "where": "1=1",
            "outFields": "*",
            "returnGeometry": "true",
            "resultOffset": offset,
            "resultRecordCount": PAGE_SIZE,
            "f": "geojson",
        },
        timeout=120,
    )
    response.raise_for_status()

    gdf = gpd.read_file(StringIO(response.text))

    if gdf.empty:
        return None

    return gdf


def download_dataset(total_features):
    """Download the complete flood dataset in pages."""
    gdfs = []
    offset = 0

    while offset < total_features:
        gdf = download_page(offset, total_features)

        if gdf is None:
            break

        gdfs.append(gdf)
        offset += len(gdf)

    if not gdfs:
        raise ValueError("No flood zone features were downloaded.")

    return gpd.GeoDataFrame(
        pd.concat(gdfs, ignore_index=True),
        crs=gdfs[0].crs,
    )


def main():
    """Download and save the Victorian flood zone dataset."""
    print("Checking ArcGIS dataset...")
    total_features = get_feature_count()
    print(f"Found {total_features:,} features.")

    print("\nDownloading flood zones...")
    result = download_dataset(total_features)

    print(f"\nDownloaded {len(result):,} features.")

    result.to_file(
        OUTPUT_FILE,
        driver="GeoJSON",
    )

    print(f"Saved to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()