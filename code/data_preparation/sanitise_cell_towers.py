"""
Sanitise the cell tower dataset by removing towers from states without
corresponding evacuation datasets and towers located outside the included
state boundaries.
"""

import json
from pathlib import Path

from shapely.geometry import Point, shape


# States without matching evacuation datasets
REMOVE_STATES = {"QLD", "WA", "ACT"}


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
BOUNDARIES_DIR = BASE_DIR / "boundaries"
TOWERS_DIR = BASE_DIR / "telecommunications_datasets"

INPUT_FILE = TOWERS_DIR / "mobile_sites_cleaned.json"
OUTPUT_FILE = TOWERS_DIR / "cell_tower_dataset.json"


def load_state_polygons(boundaries_dir):
    """Load state boundary polygons from GeoJSON files."""
    polygons = []

    for geojson_file in boundaries_dir.glob("*.geojson"):
        with open(geojson_file, encoding="utf-8") as file:
            geojson = json.load(file)

        if geojson["type"] == "FeatureCollection":
            polygons.extend(shape(feature["geometry"]) for feature in geojson["features"])
        elif geojson["type"] == "Feature":
            polygons.append(shape(geojson["geometry"]))
        else:
            polygons.append(shape(geojson))

    if not polygons:
        raise ValueError(f"No state boundary polygons found in {boundaries_dir}.")

    return polygons


def point_in_any_state(latitude, longitude, polygons):
    """Check whether a coordinate falls within or on any state boundary."""
    point = Point(longitude, latitude)
    return any(polygon.contains(point) or polygon.touches(point) for polygon in polygons)


def sanitise_towers(towers, state_polygons):
    """Remove towers from excluded states and towers outside state boundaries."""
    filtered = []
    removed_by_state = 0
    removed_outside_boundary = 0

    for tower in towers:
        if tower.get("state") in REMOVE_STATES:
            removed_by_state += 1
            continue

        latitude = tower.get("latitude")
        longitude = tower.get("longitude")

        if latitude is None or longitude is None:
            removed_outside_boundary += 1
            continue

        try:
            latitude = float(latitude)
            longitude = float(longitude)
        except (TypeError, ValueError):
            removed_outside_boundary += 1
            continue

        if not point_in_any_state(latitude, longitude, state_polygons):
            removed_outside_boundary += 1
            continue

        filtered.append(tower)

    return filtered, removed_by_state, removed_outside_boundary


def main():
    """Run the cell tower dataset sanitisation."""
    print("Loading cell tower dataset...")
    with open(INPUT_FILE, encoding="utf-8") as file:
        towers = json.load(file)

    print(f"Loaded {len(towers):,} towers.")

    print("Loading state boundaries...")
    state_polygons = load_state_polygons(BOUNDARIES_DIR)
    print(f"Loaded {len(state_polygons):,} state boundary polygons.")

    print("Filtering towers...")
    filtered, removed_by_state, removed_outside_boundary = sanitise_towers(
        towers,
        state_polygons,
    )

    print("Saving sanitised dataset...")
    with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
        json.dump(filtered, file, indent=2)

    print("\nResults")
    print("=" * 40)
    print(f"Original towers:          {len(towers):,}")
    print(f"Removed by state:         {removed_by_state:,}")
    print(f"Removed outside boundary: {removed_outside_boundary:,}")
    print(f"Final towers:             {len(filtered):,}")
    print(f"Saved to: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()