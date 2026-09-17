"""Analyse the proximity of evacuation facilities to telecommunications assets across Australia.

This script calculates the distance from each evacuation facility to the nearest
telecommunications tower and generates summary statistics and visualisations of
telecommunications accessibility at the national and state levels. Results are
exported as a text report and publication-quality figures.
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

OUTPUT_FILE = RESULTS_DIR / "telecommunications_accessibility_statistics.txt"
TOWER_FILE = TOWERS_DIR / "cell_tower_dataset.json"

EVACUATION_FILES = {
    "NSW": "new_south_wales.geojson",
    "VIC": "victoria.geojson",
    "SA": "south_australia.geojson",
    "TAS": "tasmania.geojson",
    "NT": "northern_territory.geojson",
}

EARTH_RADIUS_M = 6_371_000


def load_json(path):
    """Load and return data from a JSON file."""
    with open(path, "r", encoding="utf-8") as file:
        return json.load(file)


def load_tower_coordinates():
    """Load telecommunications tower coordinates from the tower dataset."""
    towers = load_json(TOWER_FILE)

    return np.array(
        [[float(tower["latitude"]), float(tower["longitude"])] for tower in towers],
        dtype=float,
    )


def load_evacuation_coordinates(filepath):
    """Load evacuation facility coordinates from a GeoJSON file."""
    geojson = load_json(filepath)
    coordinates = []

    for feature in geojson["features"]:
        longitude, latitude = feature["geometry"]["coordinates"][:2]
        coordinates.append([latitude, longitude])

    return coordinates


def calculate_stats(distances):
    """Calculate descriptive statistics for a collection of distances."""
    return {
        "min": min(distances),
        "max": max(distances),
        "mean": statistics.mean(distances),
        "median": statistics.median(distances),
        "std": statistics.stdev(distances) if len(distances) > 1 else 0,
    }


def format_stats(title, stats):
    """Format descriptive statistics for inclusion in the summary report."""
    return [
        title,
        "-" * len(title),
        f"Minimum: {stats['min']:.2f} m",
        f"Maximum: {stats['max']:.2f} m",
        f"Mean: {stats['mean']:.2f} m",
        f"Median: {stats['median']:.2f} m",
        f"Standard Deviation: {stats['std']:.2f} m",
        "",
    ]


def save_state_comparison_bar_iqr(national_distances, state_distances, filename="state_distance_bar_iqr.png", ylim=None):
    """Generate a bar chart comparing median tower distances and interquartile ranges."""
    labels = ["National", "NSW", "VIC", "SA", "TAS", "NT"]
    datasets = [
        national_distances,
        state_distances["NSW"],
        state_distances["VIC"],
        state_distances["SA"],
        state_distances["TAS"],
        state_distances["NT"],
    ]

    medians = [np.median(data) for data in datasets]
    q1 = [np.percentile(data, 25) for data in datasets]
    q3 = [np.percentile(data, 75) for data in datasets]
    lower = [median - quartile for median, quartile in zip(medians, q1)]
    upper = [quartile - median for median, quartile in zip(medians, q3)]

    plt.rcParams.update({"font.size": 14, "axes.titlesize": 16, "axes.labelsize": 14, "xtick.labelsize": 13, "ytick.labelsize": 13})

    plt.figure(figsize=(10, 6))
    plt.bar(labels, medians, color="#896BBC", edgecolor="black", linewidth=1)
    plt.errorbar(labels, medians, yerr=[lower, upper], fmt="none", ecolor="black", capsize=5, linewidth=1.5)
    plt.ylabel("Median Distance (m)")
    plt.xlabel("State")
    plt.title("Median Distance to Nearest Telecommunications Asset by State")

    if ylim is not None:
        plt.ylim(ylim)

    plt.tight_layout()
    plt.savefig(FIGURES_DIR / filename, dpi=300, bbox_inches="tight")
    plt.close()


def save_state_accessibility_stacked_bar(national_distances, state_distances, filename="state_accessibility_stacked_bar.png"):
    """Generate a stacked bar chart showing telecommunications accessibility by distance category."""
    labels = ["National", "NSW", "VIC", "SA", "TAS", "NT"]
    datasets = [
        national_distances,
        state_distances["NSW"],
        state_distances["VIC"],
        state_distances["SA"],
        state_distances["TAS"],
        state_distances["NT"],
    ]

    categories = [
        ("≤100 m", 0, 100),
        ("100–250 m", 100, 250),
        ("250–500 m", 250, 500),
        ("500–1000 m", 500, 1000),
        (">1000 m", 1000, np.inf),
    ]

    percentages = []

    for data in datasets:
        data = np.asarray(data)
        total = len(data)
        percentages.append([100 * np.sum((data > lower) & (data <= upper)) / total for _, lower, upper in categories])

    percentages = np.array(percentages)

    plt.rcParams.update({"font.size": 14, "axes.titlesize": 16, "axes.labelsize": 14, "xtick.labelsize": 13, "ytick.labelsize": 13})

    plt.figure(figsize=(10, 5))
    colors = ["#2E7D32", "#66BB6A", "#AED581", "#FFC107", "#D32F2F"]
    left = np.zeros(len(labels))

    for index, (label, _, _) in enumerate(categories):
        plt.barh(labels, percentages[:, index], left=left, label=label, color=colors[index], edgecolor="black")
        left += percentages[:, index]

    plt.xlabel("Percentage of Locations (%)")
    plt.ylabel("State")
    plt.title("Accessibility to the Nearest Telecommunications Asset by State")
    plt.xlim(0, 100)
    plt.legend(title="Distance Category", loc="lower right")
    plt.tight_layout()
    plt.savefig(FIGURES_DIR / filename, dpi=300, bbox_inches="tight")
    plt.close()


def main():
    """Execute the telecommunications accessibility analysis."""
    print("Loading telecommunications tower data...")
    tower_coords = load_tower_coordinates()
    tower_tree = BallTree(np.radians(tower_coords), metric="haversine")
    print(f"Loaded {len(tower_coords):,} telecommunications towers.")

    national_distances = []
    state_distances = {state: [] for state in EVACUATION_FILES}

    for state, filename in EVACUATION_FILES.items():
        print(f"Processing evacuation facilities in {state}...")
        evacuation_points = load_evacuation_coordinates(EVACUATION_DIR / filename)

        for latitude, longitude in evacuation_points:
            distance, _ = tower_tree.query(np.radians([[latitude, longitude]]), k=1)
            distance_m = distance[0][0] * EARTH_RADIUS_M
            national_distances.append(distance_m)
            state_distances[state].append(distance_m)

    national_stats = calculate_stats(national_distances)

    lines = []
    lines.extend(format_stats("NATIONAL", national_stats))

    for state in EVACUATION_FILES:
        lines.extend(format_stats(state, calculate_stats(state_distances[state])))

    output = "\n".join(lines)
    print(output)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
        file.write(output)

    print(f"\nSaved results to: {OUTPUT_FILE}")

    save_state_comparison_bar_iqr(national_distances, state_distances, filename="state_distance_bar_iqr_full.png")
    save_state_comparison_bar_iqr(national_distances, state_distances, filename="state_distance_bar_iqr_zoomed.png", ylim=(0, 25_000))
    save_state_accessibility_stacked_bar(national_distances, state_distances, filename="state_accessibility_stacked_bar.png")


if __name__ == "__main__":
    main()