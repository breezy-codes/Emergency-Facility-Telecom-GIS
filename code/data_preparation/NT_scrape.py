"""
Geocode Northern Territory emergency shelter locations.

The shelter data is first downloaded from the SecureNT website using curl:

    curl -L "https://securent.nt.gov.au/prepare-for-an-emergency/emergency-planning/shelter-locations/all-shelters" -o shelters.html

The downloaded HTML tables are then parsed, shelter addresses are geocoded
using Nominatim, and the resulting locations are saved as a GeoJSON file.

Input:
    data/raw/NT_shelters.html

Output:
    data/evacuation_datasets/northern_territory.geojson
"""

import json
import time
from pathlib import Path

import pandas as pd
from geopy.geocoders import Nominatim


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
RAW_DIR = BASE_DIR / "raw"
EVACUATION_DIR = BASE_DIR / "evacuation_datasets"

EVACUATION_DIR.mkdir(parents=True, exist_ok=True)


# Input and output files
INPUT_FILE = RAW_DIR / "NT_shelters.html"
OUTPUT_FILE = EVACUATION_DIR / "northern_territory.geojson"


def load_shelter_tables():
    """Load shelter locations from the downloaded HTML file."""
    tables = pd.read_html(INPUT_FILE)

    if not tables:
        raise ValueError(f"No tables found in {INPUT_FILE}.")

    return tables


def geocode_shelters(tables):
    """Geocode shelter addresses using the Nominatim service."""
    geolocator = Nominatim(user_agent="nt_shelters")
    features = []
    failed = 0

    for table in tables:
        if len(table.columns) < 2:
            continue

        for _, row in table.iterrows():
            name = str(row.iloc[0]).strip()
            address = str(row.iloc[1]).strip()

            try:
                location = geolocator.geocode(
                    f"{address}, Northern Territory, Australia"
                )

                if location:
                    features.append({
                        "type": "Feature",
                        "properties": {
                            "name": name,
                            "address": address,
                        },
                        "geometry": {
                            "type": "Point",
                            "coordinates": [
                                location.longitude,
                                location.latitude,
                            ],
                        },
                    })
                else:
                    failed += 1
                    print(f"Could not geocode: {name} - {address}")

                time.sleep(1)

            except Exception as error:
                failed += 1
                print(f"Error geocoding {name}: {error}")

    print(f"Successfully geocoded: {len(features):,}")
    print(f"Failed to geocode: {failed:,}")

    return features


def save_geojson(features):
    """Save geocoded shelter locations as GeoJSON."""
    geojson = {
        "type": "FeatureCollection",
        "features": features,
    }

    with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
        json.dump(geojson, file, indent=2)

    print(f"Saved to {OUTPUT_FILE}")


def main():
    """Load, geocode, and save Northern Territory shelter locations."""
    print(f"Loading shelter data from {INPUT_FILE}...")

    tables = load_shelter_tables()
    print(f"Found {len(tables):,} tables.")

    print("Geocoding shelter addresses...")
    features = geocode_shelters(tables)

    if not features:
        raise ValueError("No shelter locations were successfully geocoded.")

    save_geojson(features)

    print("Done.")


if __name__ == "__main__":
    main()