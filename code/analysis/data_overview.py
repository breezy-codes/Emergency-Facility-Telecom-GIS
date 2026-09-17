"""Summarise the datasets used in the analysis.

This script reports the number of evacuation facilities and telecommunications assets
within each Australian state included in the analysis. State boundaries are used to
assign telecommunications assets to their respective states, while evacuation facility
counts are obtained directly from the corresponding state-level GeoJSON datasets. The
resulting summary is printed to the console and exported as a text file.
"""

import json
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

from shapely.geometry import Point, shape


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
BOUNDARIES_DIR = BASE_DIR / "boundaries"
TOWERS_DIR = BASE_DIR / "telecommunications_datasets"
EVACUATION_DIR = BASE_DIR / "evacuation_datasets"
RESULTS_DIR = PROJECT_ROOT / "results"

RESULTS_DIR.mkdir(parents=True, exist_ok=True)

OUTPUT_FILE = RESULTS_DIR / "dataset_summary.txt"
TOWER_FILE = TOWERS_DIR / "cell_tower_dataset.json"

FIGURES_DIR = PROJECT_ROOT / "figures"
FIGURES_DIR.mkdir(parents=True, exist_ok=True)

OUTPUT_FIGURE = FIGURES_DIR / "dataset_counts_by_state.png"

STATE_FILES = {
    "NSW": "new_south_wales_boundary.geojson",
    "VIC": "victoria_boundary.geojson",
    "SA": "south_australia_boundary.geojson",
    "TAS": "tasmania_boundary.geojson",
    "NT": "northern_territory_boundary.geojson",
}

EVACUATION_FILES = {
    "NSW": "new_south_wales.geojson",
    "VIC": "victoria.geojson",
    "SA": "south_australia.geojson",
    "TAS": "tasmania.geojson",
    "NT": "northern_territory.geojson",
}

STATE_ORDER = ["NSW", "VIC", "SA", "TAS", "NT"]


def load_json(path):
    """Load and return data from a JSON file."""
    with open(path, "r", encoding="utf-8") as file:
        return json.load(file)


def load_state_polygons():
    """Load state boundary geometries and return them indexed by state code."""
    polygons = {}

    for state, filename in STATE_FILES.items():
        geojson = load_json(BOUNDARIES_DIR / filename)
        polygons[state] = [shape(feature["geometry"]) for feature in geojson["features"]]

    return polygons


def count_evacuation_facilities():
    """Count evacuation facilities in each state."""
    counts = {}

    for state, filename in EVACUATION_FILES.items():
        geojson = load_json(EVACUATION_DIR / filename)
        counts[state] = len(geojson["features"])

    return counts


def count_towers_by_state(state_polygons):
    """Count telecommunications assets located within each state boundary."""
    towers = load_json(TOWER_FILE)
    counts = {state: 0 for state in STATE_FILES}

    for tower in towers:
        latitude = tower.get("latitude")
        longitude = tower.get("longitude")

        if latitude in (None, "") or longitude in (None, ""):
            continue

        try:
            point = Point(float(longitude), float(latitude))
        except (TypeError, ValueError):
            continue

        for state, polygons in state_polygons.items():
            if any(polygon.contains(point) for polygon in polygons):
                counts[state] += 1
                break

    return counts

def save_dataset_counts_figure(evacuation_counts, tower_counts, path):
    """Generate and save a grouped bar chart comparing evacuation facilities and telecommunications assets by state."""
    states = STATE_ORDER
    x = np.arange(len(states))
    width = 0.38

    evacuation_values = [evacuation_counts[state] for state in states]
    tower_values = [tower_counts[state] for state in states]

    plt.rcParams.update({"font.size": 14, "axes.titlesize": 16, "axes.labelsize": 14, "xtick.labelsize": 13, "ytick.labelsize": 13})

    plt.figure(figsize=(10, 6))
    plt.bar(x - width / 2, evacuation_values, width, label="Evacuation Facilities", edgecolor="black")
    plt.bar(x + width / 2, tower_values, width, label="Telecommunications Assets", edgecolor="black")

    plt.xlabel("State")
    plt.ylabel("Number of Locations")
    plt.title("Evacuation Facilities and Telecommunications Assets by State")
    plt.xticks(x, states)
    plt.legend()
    plt.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(path, dpi=300, bbox_inches="tight")
    plt.close()

def create_summary(evacuation_counts, tower_counts):
    """Create a formatted dataset summary containing state and total counts."""
    lines = [
        "Dataset Summary",
        "=" * 65,
        "",
        f"{'State':<5} {'Evacuation Facilities':>25} {'Telecommunications Assets':>30}",
        "-" * 65,
    ]

    total_evacuation = 0
    total_towers = 0

    for state in STATE_ORDER:
        evacuation_count = evacuation_counts[state]
        tower_count = tower_counts[state]
        total_evacuation += evacuation_count
        total_towers += tower_count
        lines.append(f"{state:<5} {evacuation_count:>25,} {tower_count:>30,}")

    lines.extend([
        "-" * 65,
        f"{'Total':<5} {total_evacuation:>25,} {total_towers:>30,}",
        "",
    ])

    return "\n".join(lines)


def main():
    """Execute the dataset summary analysis."""
    print("Loading state boundaries...")
    state_polygons = load_state_polygons()

    print("Counting evacuation facilities...")
    evacuation_counts = count_evacuation_facilities()

    print("Counting telecommunications assets...")
    tower_counts = count_towers_by_state(state_polygons)

    create_summary(evacuation_counts, tower_counts)
    save_dataset_counts_figure(evacuation_counts, tower_counts, OUTPUT_FIGURE)

    output = create_summary(evacuation_counts, tower_counts)

    print()
    print(output)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
        file.write(output)

    print(f"Saved results to: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()