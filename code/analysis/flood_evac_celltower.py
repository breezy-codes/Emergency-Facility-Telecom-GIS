"""Analyse telecommunications accessibility of flood-exposed evacuation facilities in Victoria.

This script calculates the distance from each flood-exposed evacuation facility to its nearest 
telecommunications tower, classifies accessibility according to predefined distance thresholds, 
and generates a visualisation of the resulting accessibility distribution. The resulting spatial
dataset, summary statistics, and figure are exported for use in research publications and
further analysis.
"""

import json
import statistics
from pathlib import Path

import geopandas as gpd
import matplotlib.pyplot as plt
from shapely.geometry import Point


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
TOWERS_DIR = BASE_DIR / "telecommunications_datasets"
RESULTS_DIR = PROJECT_ROOT / "results"
FIGURES_DIR = PROJECT_ROOT / "figures"

RESULTS_DIR.mkdir(parents=True, exist_ok=True)
FIGURES_DIR.mkdir(parents=True, exist_ok=True)

EVACUATION_FILE = RESULTS_DIR / "flood_overlay_within_500m.geojson"
TOWER_FILE = TOWERS_DIR / "cell_tower_dataset.json"

OUTPUT_GEOJSON = RESULTS_DIR / "flood_tower_analysis.geojson"
OUTPUT_REPORT = RESULTS_DIR / "flood_tower_accessibility_analysis.txt"
OUTPUT_FIGURE = FIGURES_DIR / "flood_tower_accessibility.png"

PROJECTED_CRS = "EPSG:3577"
GEOGRAPHIC_CRS = "EPSG:4326"


def classify_distance(distance):
    """Classify telecommunications accessibility based on distance to the nearest tower."""
    if distance <= 100:
        return "Co-located / Immediate Proximity"
    if distance <= 250:
        return "Nearby Infrastructure"
    if distance <= 500:
        return "Moderate Accessibility"
    if distance <= 1000:
        return "Limited Accessibility"
    return "Potential Accessibility Concern"


def calculate_metrics(distances):
    """Calculate summary statistics and accessibility distributions for tower distances."""
    if not distances:
        raise ValueError("No tower distances were available for analysis.")

    total = len(distances)
    categories = {
        "0_100": sum(distance <= 100 for distance in distances),
        "100_250": sum(100 < distance <= 250 for distance in distances),
        "250_500": sum(250 < distance <= 500 for distance in distances),
        "500_1000": sum(500 < distance <= 1000 for distance in distances),
        "over_1000": sum(distance > 1000 for distance in distances),
    }

    return {
        "mean": statistics.mean(distances),
        "median": statistics.median(distances),
        **{f"{category}_count": count for category, count in categories.items()},
        **{f"{category}_pct": count / total * 100 for category, count in categories.items()},
    }


def load_evacuation_facilities(path):
    """Load flood-exposed evacuation facilities and project them to a metric CRS."""
    evacuation = gpd.read_file(path).to_crs(PROJECTED_CRS)

    if evacuation.empty:
        raise ValueError("The evacuation facility dataset contains no features.")

    return evacuation


def load_victorian_towers(path):
    """Load Victorian telecommunications towers from the tower dataset."""
    with open(path, encoding="utf-8") as file:
        tower_data = json.load(file)

    tower_records = []

    for tower in tower_data:
        if tower.get("state") != "VIC":
            continue

        latitude = tower.get("latitude")
        longitude = tower.get("longitude")

        if latitude in (None, "") or longitude in (None, ""):
            continue

        try:
            point = Point(float(longitude), float(latitude))
        except (TypeError, ValueError):
            continue

        tower_records.append({"site_id": tower.get("site_id"), "geometry": point})

    if not tower_records:
        raise ValueError("No valid Victorian telecommunications towers were found.")

    return gpd.GeoDataFrame(tower_records, crs=GEOGRAPHIC_CRS).to_crs(PROJECTED_CRS)


def calculate_nearest_tower_distances(evacuation, towers):
    """Calculate the distance from each evacuation facility to its nearest tower."""
    nearest = gpd.sjoin_nearest(evacuation, towers[["site_id", "geometry"]], how="left", distance_col="tower_distance_m")
    nearest_distances = nearest.groupby(nearest.index)["tower_distance_m"].min()
    evacuation["tower_distance_m"] = nearest_distances.reindex(evacuation.index).values

    if evacuation["tower_distance_m"].isna().any():
        raise ValueError("One or more evacuation facilities could not be matched to a tower.")

    return evacuation


def write_report(path, evacuation, metrics):
    """Write a text summary of the telecommunications accessibility analysis."""
    with open(path, "w", encoding="utf-8") as file:
        file.write("Victorian Flood Telecommunications Accessibility Analysis\n")
        file.write("=" * 60 + "\n\n")
        file.write(f"Facilities analysed: {len(evacuation):,}\n")
        file.write(f"Mean distance to nearest tower: {metrics['mean']:.2f} m\n")
        file.write(f"Median distance to nearest tower: {metrics['median']:.2f} m\n\n")
        file.write("Accessibility classification\n")
        file.write("-" * 60 + "\n")
        file.write(f"0-100 m: {metrics['0_100_count']:,} ({metrics['0_100_pct']:.2f}%)\n")
        file.write(f"100-250 m: {metrics['100_250_count']:,} ({metrics['100_250_pct']:.2f}%)\n")
        file.write(f"250-500 m: {metrics['250_500_count']:,} ({metrics['250_500_pct']:.2f}%)\n")
        file.write(f"500-1000 m: {metrics['500_1000_count']:,} ({metrics['500_1000_pct']:.2f}%)\n")
        file.write(f">1000 m: {metrics['over_1000_count']:,} ({metrics['over_1000_pct']:.2f}%)\n")


def create_accessibility_figure(metrics, path):
    """Create and save a publication-quality bar chart of telecommunications accessibility."""
    labels = ["≤100 m", "100–250 m", "250–500 m", "500–1000 m", ">1000 m"]
    percentages = [
        metrics["0_100_pct"],
        metrics["100_250_pct"],
        metrics["250_500_pct"],
        metrics["500_1000_pct"],
        metrics["over_1000_pct"],
    ]

    plt.rcParams.update({"font.size": 14, "axes.titlesize": 16, "axes.labelsize": 14, "xtick.labelsize": 12, "ytick.labelsize": 12})

    plt.figure(figsize=(10, 6))
    bars = plt.bar(labels, percentages, edgecolor="black", linewidth=1)

    plt.xlabel("Distance to Nearest Telecommunications Tower")
    plt.ylabel("Evacuation Facilities (%)")
    plt.title("Telecommunications Accessibility of Flood-Exposed Evacuation Facilities")
    plt.ylim(0, max(percentages) * 1.15)

    for bar, percentage in zip(bars, percentages):
        plt.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + max(percentages) * 0.015, f"{percentage:.1f}%", ha="center", va="bottom")

    plt.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(path, dpi=300, bbox_inches="tight")
    plt.close()


def main():
    """Execute the flood telecommunications accessibility analysis."""
    print("Loading flood-exposed evacuation facilities...")
    evacuation = load_evacuation_facilities(EVACUATION_FILE)
    print(f"Loaded {len(evacuation):,} evacuation facilities.")

    print("Loading telecommunications towers...")
    towers = load_victorian_towers(TOWER_FILE)
    print(f"Loaded {len(towers):,} Victorian telecommunications towers.")

    print("Calculating distances to nearest telecommunications towers...")
    evacuation = calculate_nearest_tower_distances(evacuation, towers)

    evacuation["tower_accessibility"] = evacuation["tower_distance_m"].apply(classify_distance)

    print("Calculating accessibility metrics...")
    distances = evacuation["tower_distance_m"].tolist()
    metrics = calculate_metrics(distances)

    print("Writing spatial results...")
    evacuation.to_crs(GEOGRAPHIC_CRS).to_file(OUTPUT_GEOJSON, driver="GeoJSON")

    print("Writing analysis report...")
    write_report(OUTPUT_REPORT, evacuation, metrics)

    print("Generating accessibility figure...")
    create_accessibility_figure(metrics, OUTPUT_FIGURE)

    print("Analysis complete.")
    print(f"Mean distance: {metrics['mean']:.2f} m")
    print(f"Median distance: {metrics['median']:.2f} m")
    print(f"Results: {OUTPUT_GEOJSON}")
    print(f"Report: {OUTPUT_REPORT}")
    print(f"Figure: {OUTPUT_FIGURE}")


if __name__ == "__main__":
    main()