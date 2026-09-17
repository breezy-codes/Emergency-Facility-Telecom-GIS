"""Analyse telecommunications accessibility for evacuation facilities across Australia.

This script calculates the distance from each evacuation facility to the nearest
telecommunications tower and classifies accessibility according to predefined distance
thresholds. Summary statistics and accessibility classifications are calculated at both
the national and state levels. Results are exported as a text report and publication-quality
figures for further analysis and reporting.
"""

import json
import statistics
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from sklearn.neighbors import BallTree


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
TOWERS_DIR = BASE_DIR / "telecommunications_datasets"
EVACUATION_DIR = BASE_DIR / "evacuation_datasets"
RESULTS_DIR = PROJECT_ROOT / "results"
FIGURES_DIR = PROJECT_ROOT / "figures"

RESULTS_DIR.mkdir(parents=True, exist_ok=True)
FIGURES_DIR.mkdir(parents=True, exist_ok=True)

OUTPUT_FILE = RESULTS_DIR / "telecommunications_accessibility_classification.txt"
TOWER_FILE = TOWERS_DIR / "cell_tower_dataset.json"

EVACUATION_FILES = {
    "NSW": "new_south_wales.geojson",
    "VIC": "victoria.geojson",
    "SA": "south_australia.geojson",
    "TAS": "tasmania.geojson",
    "NT": "northern_territory.geojson",
}

STATE_ORDER = ["NSW", "VIC", "SA", "TAS", "NT"]

EARTH_RADIUS_M = 6_371_000

CLASSIFICATIONS = [
    "Co-located / Immediate Proximity",
    "Nearby Infrastructure",
    "Moderate Accessibility",
    "Limited Accessibility",
    "Potential Accessibility Concern",
]


def load_json(path):
    """Load and return data from a JSON file."""
    with open(path, "r", encoding="utf-8") as file:
        return json.load(file)


def load_tower_coordinates():
    """Load telecommunications tower coordinates as an array of latitude-longitude pairs."""
    towers = load_json(TOWER_FILE)
    coordinates = []

    for tower in towers:
        latitude = tower.get("latitude")
        longitude = tower.get("longitude")

        if latitude in (None, "") or longitude in (None, ""):
            continue

        try:
            coordinates.append([float(latitude), float(longitude)])
        except (TypeError, ValueError):
            continue

    if not coordinates:
        raise ValueError("No valid telecommunications tower coordinates were found.")

    return np.array(coordinates, dtype=float)


def load_evacuation_coordinates(filepath):
    """Load evacuation facility coordinates from a GeoJSON file."""
    geojson = load_json(filepath)
    coordinates = []

    for feature in geojson["features"]:
        longitude, latitude = feature["geometry"]["coordinates"][:2]
        coordinates.append([float(latitude), float(longitude)])

    return coordinates


def classify_distance(distance):
    """Classify the distance to the nearest telecommunications tower."""
    if distance <= 100:
        return "Co-located / Immediate Proximity"
    if distance <= 250:
        return "Nearby Infrastructure"
    if distance <= 500:
        return "Moderate Accessibility"
    if distance <= 1000:
        return "Limited Accessibility"
    return "Potential Accessibility Concern"


def empty_classification_dict():
    """Create an empty classification dictionary."""
    return {classification: 0 for classification in CLASSIFICATIONS}


def add_classification(result_dict, classification):
    """Increment the count for a telecommunications accessibility classification."""
    result_dict[classification] += 1


def calculate_state_metrics(distances):
    """Calculate summary statistics and threshold-based accessibility measures."""
    if not distances:
        raise ValueError("No distances were provided for analysis.")

    total = len(distances)
    within_100 = sum(distance <= 100 for distance in distances)
    within_250 = sum(distance <= 250 for distance in distances)
    within_500 = sum(distance <= 500 for distance in distances)
    over_1000 = sum(distance > 1000 for distance in distances)

    return {
        "mean": statistics.mean(distances),
        "median": statistics.median(distances),
        "within_100_pct": within_100 / total * 100,
        "within_250_pct": within_250 / total * 100,
        "within_500_pct": within_500 / total * 100,
        "over_1000_pct": over_1000 / total * 100,
    }


def save_state_mean_distance_figure(state_distances, filename):
    """Generate and save a bar chart comparing mean distance to the nearest tower by state."""
    means = [statistics.mean(state_distances[state]) for state in STATE_ORDER]

    plt.rcParams.update({"font.size": 14, "axes.titlesize": 16, "axes.labelsize": 14, "xtick.labelsize": 13, "ytick.labelsize": 13})

    plt.figure(figsize=(8, 5))
    plt.bar(STATE_ORDER, means, edgecolor="black", linewidth=1)
    plt.ylabel("Mean Distance (m)")
    plt.xlabel("State")
    plt.title("Mean Distance to Nearest Telecommunications Asset by State")
    plt.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(FIGURES_DIR / filename, dpi=300, bbox_inches="tight")
    plt.close()


def save_classification_distribution(counts, filename):
    """Generate and save a bar chart showing the national accessibility classification distribution."""
    categories = list(counts.keys())
    values = list(counts.values())

    plt.rcParams.update({"font.size": 14, "axes.titlesize": 16, "axes.labelsize": 14, "xtick.labelsize": 12, "ytick.labelsize": 13})

    plt.figure(figsize=(10, 6))
    bars = plt.bar(categories, values, edgecolor="black", linewidth=1)
    plt.ylabel("Number of Evacuation Facilities")
    plt.xlabel("Accessibility Classification")
    plt.title("Telecommunications Accessibility Classification of Evacuation Facilities")
    plt.xticks(rotation=20, ha="right")

    for bar, value in zip(bars, values):
        plt.text(bar.get_x() + bar.get_width() / 2, bar.get_height(), f"{value:,}", ha="center", va="bottom", fontsize=11)

    plt.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(FIGURES_DIR / filename, dpi=300, bbox_inches="tight")
    plt.close()


def write_section(lines, title, counts):
    """Append an accessibility classification summary to the report."""
    total = sum(counts.values())

    lines.append(title)
    lines.append("-" * len(title))
    lines.append("")

    for classification in CLASSIFICATIONS:
        count = counts[classification]
        percentage = count / total * 100 if total > 0 else 0
        lines.append(f"{classification:<35}{count:>8,}{percentage:>12.2f}%")

    lines.append(f"{'Total':<35}{total:>8,}{100:>12.2f}%")
    lines.extend(["", ""])


def write_state_comparison(lines, state_distances):
    """Append state-level distance and accessibility statistics to the report."""
    lines.append("STATE COMPARISON")
    lines.append("-" * 70)
    lines.append("")
    lines.append(f"{'State':<5}{'Mean (m)':>15}{'Median (m)':>15}{'Within 100m (%)':>18}{'Within 500m (%)':>18}{'>1000m (%)':>15}")

    for state in STATE_ORDER:
        metrics = calculate_state_metrics(state_distances[state])
        lines.append(f"{state:<5}{metrics['mean']:>15.2f}{metrics['median']:>15.2f}{metrics['within_100_pct']:>18.2f}{metrics['within_500_pct']:>18.2f}{metrics['over_1000_pct']:>15.2f}")

    lines.append("")


def main():
    """Execute the telecommunications accessibility analysis."""
    print("Loading telecommunications tower data...")
    tower_coords = load_tower_coordinates()
    tower_tree = BallTree(np.radians(tower_coords), metric="haversine")
    print(f"Loaded {len(tower_coords):,} telecommunications towers.")

    national_counts = empty_classification_dict()
    state_distances = {state: [] for state in STATE_ORDER}

    for state, filename in EVACUATION_FILES.items():
        print(f"Processing evacuation facilities in {state}...")
        evacuation_points = load_evacuation_coordinates(EVACUATION_DIR / filename)

        for latitude, longitude in evacuation_points:
            distance, _ = tower_tree.query(np.radians([[latitude, longitude]]), k=1)
            distance_m = distance[0][0] * EARTH_RADIUS_M
            state_distances[state].append(distance_m)
            add_classification(national_counts, classify_distance(distance_m))

    lines = []
    write_section(lines, "NATIONAL", national_counts)

    for state in STATE_ORDER:
        state_counts = empty_classification_dict()

        for distance in state_distances[state]:
            add_classification(state_counts, classify_distance(distance))

        write_section(lines, state, state_counts)

    write_state_comparison(lines, state_distances)

    output = "\n".join(lines)
    print()
    print(output)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
        file.write(output)

    print(f"Saved results to: {OUTPUT_FILE}")

    print("Generating accessibility classification figure...")
    save_classification_distribution(national_counts, "classification_distribution.png")

    print("Generating state comparison figure...")
    save_state_mean_distance_figure(state_distances, "state_mean_distance_comparison.png")

    print("Analysis complete.")


if __name__ == "__main__":
    main()