"""
Download Australian state boundaries from the ABS GeoServices API and save
each selected state as a separate GeoJSON file for use in the analysis.
"""

from pathlib import Path

import geopandas as gpd


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
BOUNDARIES_DIR = BASE_DIR / "boundaries"

BOUNDARIES_DIR.mkdir(parents=True, exist_ok=True)


# ABS GeoServices API
BOUNDARY_URL = (
    "https://geo.abs.gov.au/arcgis/rest/services/"
    "ASGS2021/STE/FeatureServer/0/query"
    "?where=1%3D1&outFields=*&f=geojson"
)


# States included in the analysis
STATES = [
    "New South Wales",
    "Victoria",
    "South Australia",
    "Tasmania",
    "Northern Territory",
]


def download_boundaries():
    """Download Australian state boundaries from the ABS GeoServices API."""
    return gpd.read_file(BOUNDARY_URL).to_crs("EPSG:4326")


def save_state_boundaries(boundaries):
    """Filter and save each selected state as an individual GeoJSON file."""
    boundaries = boundaries[boundaries["state_name_2021"].isin(STATES)]

    if boundaries.empty:
        raise ValueError("No matching state boundaries were found.")

    for _, state in boundaries.iterrows():
        state_name = state["state_name_2021"]
        filename = f"{state_name.lower().replace(' ', '_')}_boundary.geojson"

        state_gdf = gpd.GeoDataFrame(
            [state],
            columns=boundaries.columns,
            crs=boundaries.crs,
        )

        state_gdf.to_file(
            BOUNDARIES_DIR / filename,
            driver="GeoJSON",
        )

        print(f"Saved {filename}")


def main():
    """Download and save the selected Australian state boundaries."""
    print("Downloading Australian state boundaries...")

    boundaries = download_boundaries()

    print(f"Downloaded {len(boundaries):,} state boundaries.")

    save_state_boundaries(boundaries)

    print("\nBoundary download complete.")


if __name__ == "__main__":
    main()