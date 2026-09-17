"""
Prepare the Victorian flood overlay dataset for analysis.

The script removes unnecessary metadata fields, projects the geometries to
EPSG:3577 for metric-based simplification, simplifies the polygons while
preserving topology, and reprojects the result to EPSG:4326.

Input:
    data/flood_datasets/vic_flood.geojson

Output:
    data/flood_datasets/vic_flood_simplified.geojson
"""

from pathlib import Path

import geopandas as gpd


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
FLOOD_DIR = BASE_DIR / "flood_datasets"

FLOOD_DIR.mkdir(parents=True, exist_ok=True)


# Input and output files
INPUT_FILE = FLOOD_DIR / "vic_flood.geojson"
OUTPUT_FILE = FLOOD_DIR / "vic_flood_simplified.geojson"

PROJECTED_CRS = "EPSG:3577"
GEOGRAPHIC_CRS = "EPSG:4326"
SIMPLIFICATION_TOLERANCE = 50


def load_flood_data():
    """Load the Victorian flood overlay dataset."""
    gdf = gpd.read_file(INPUT_FILE)

    if gdf.empty:
        raise ValueError("The flood dataset contains no features.")

    return gdf


def remove_unnecessary_columns(gdf):
    """Remove metadata fields that are not required for the analysis."""
    columns_to_remove = [
        "PFI_CR",
        "UFI",
        "UFI_CR",
        "GAZ_B_DATE",
    ]

    existing_columns = [column for column in columns_to_remove if column in gdf.columns]

    if existing_columns:
        gdf = gdf.drop(columns=existing_columns)

    print(f"Removed columns: {existing_columns or 'None'}")

    return gdf


def simplify_geometries(gdf):
    """Simplify flood polygons using a metric projected coordinate system."""
    print(f"Projecting to {PROJECTED_CRS}...")
    gdf = gdf.to_crs(PROJECTED_CRS)

    print(f"Simplifying geometries with {SIMPLIFICATION_TOLERANCE} m tolerance...")
    gdf["geometry"] = gdf.geometry.simplify(
        tolerance=SIMPLIFICATION_TOLERANCE,
        preserve_topology=True,
    )

    print(f"Reprojecting to {GEOGRAPHIC_CRS}...")
    return gdf.to_crs(GEOGRAPHIC_CRS)


def main():
    """Prepare and save the simplified Victorian flood dataset."""
    print(f"Loading {INPUT_FILE}...")
    gdf = load_flood_data()

    print(f"Features: {len(gdf):,}")

    gdf = remove_unnecessary_columns(gdf)
    gdf = simplify_geometries(gdf)

    print(f"Saving {OUTPUT_FILE}...")
    gdf.to_file(
        OUTPUT_FILE,
        driver="GeoJSON",
    )

    print(f"Saved {len(gdf):,} features.")
    print("Done.")


if __name__ == "__main__":
    main()