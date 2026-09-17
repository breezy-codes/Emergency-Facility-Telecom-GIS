"""
Prepare NSW bushfire-prone land data for analysis.

The script loads the original bushfire-prone land dataset, separates it into
the three bushfire categories, removes unnecessary metadata fields, simplifies
the geometries using a projected CRS, and saves the processed datasets as
GeoJSON files.

Input:
    data/raw/bushfire.json

Outputs:
    data/bushfire_datasets/bushfire_category_1.geojson
    data/bushfire_datasets/bushfire_category_2.geojson
    data/bushfire_datasets/bushfire_category_3.geojson
    data/bushfire_datasets/bushfire_category_1_simplified.geojson
    data/bushfire_datasets/bushfire_category_2_simplified.geojson
    data/bushfire_datasets/bushfire_category_3_simplified.geojson

The original dataset is available from the NSW Spatial Information Exchange:
https://portal.spatial.nsw.gov.au/client/services?id=84c338fe2e8c49a9836751ed49c9c581
"""

import json
from pathlib import Path

import geopandas as gpd


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
RAW_DIR = BASE_DIR / "raw"
BUSHFIRE_DIR = BASE_DIR / "bushfire_datasets"

BUSHFIRE_DIR.mkdir(parents=True, exist_ok=True)


# Input and output files
BUSHFIRE_FILE = RAW_DIR / "bushfire.json"

CATEGORY_FILES = {
    1: BUSHFIRE_DIR / "bushfire_category_1.geojson",
    2: BUSHFIRE_DIR / "bushfire_category_2.geojson",
    3: BUSHFIRE_DIR / "bushfire_category_3.geojson",
}

PROJECTED_CRS = "EPSG:3577"
GEOGRAPHIC_CRS = "EPSG:4326"
SIMPLIFICATION_TOLERANCE = 100

COLUMNS_TO_REMOVE = [
    "startdate",
    "enddate",
    "lastupdate",
    "guideline",
    "d_guidelin",
]


def load_bushfire_data():
    """Load the NSW bushfire-prone land dataset from JSON."""
    with open(BUSHFIRE_FILE, encoding="utf-8") as file:
        data = json.load(file)

    features = data["NSWBushFireProneLand"]["features"]

    gdf = gpd.GeoDataFrame.from_features(
        features,
        crs=GEOGRAPHIC_CRS,
    )

    if gdf.empty:
        raise ValueError("The bushfire dataset contains no features.")

    return gdf


def export_categories(gdf):
    """Separate the dataset into bushfire categories and save GeoJSON files."""
    print("\nCategory counts:")
    print(gdf["category"].value_counts().sort_index())

    for category, output_file in CATEGORY_FILES.items():
        category_gdf = gdf[gdf["category"] == category].copy()

        if category_gdf.empty:
            print(f"Warning: Category {category} contains no features.")
            continue

        print(f"\nExporting Category {category}: {len(category_gdf):,} features")

        category_gdf.to_file(
            output_file,
            driver="GeoJSON",
        )

        print(f"Saved {output_file}")


def remove_unnecessary_columns(gdf):
    """Remove metadata fields that are not required for the analysis."""
    existing_columns = [column for column in COLUMNS_TO_REMOVE if column in gdf.columns]

    if existing_columns:
        gdf = gdf.drop(columns=existing_columns)

    print(f"Removed columns: {existing_columns or 'None'}")

    return gdf


def simplify_category(input_file):
    """Simplify a bushfire category dataset and save the processed GeoJSON."""
    print(f"\nLoading {input_file}...")
    gdf = gpd.read_file(input_file)

    if gdf.empty:
        raise ValueError(f"{input_file} contains no features.")

    print(f"Features: {len(gdf):,}")

    gdf = remove_unnecessary_columns(gdf)

    print(f"Projecting to {PROJECTED_CRS}...")
    gdf = gdf.to_crs(PROJECTED_CRS)

    print(f"Simplifying geometries with {SIMPLIFICATION_TOLERANCE} m tolerance...")
    gdf["geometry"] = gdf.geometry.simplify(
        tolerance=SIMPLIFICATION_TOLERANCE,
        preserve_topology=True,
    )

    print(f"Reprojecting to {GEOGRAPHIC_CRS}...")
    gdf = gdf.to_crs(GEOGRAPHIC_CRS)

    output_file = input_file.with_name(f"{input_file.stem}_simplified.geojson")

    print(f"Saving {output_file}...")
    gdf.to_file(
        output_file,
        driver="GeoJSON",
    )

    print(f"Saved {len(gdf):,} features.")


def main():
    """Prepare and simplify the NSW bushfire-prone land datasets."""
    print(f"Loading {BUSHFIRE_FILE}...")

    gdf = load_bushfire_data()

    print(f"Loaded {len(gdf):,} features.")

    export_categories(gdf)

    print("\nSimplifying category datasets...")

    for input_file in CATEGORY_FILES.values():
        simplify_category(input_file)

    print("\nAll bushfire datasets processed.")


if __name__ == "__main__":
    main()