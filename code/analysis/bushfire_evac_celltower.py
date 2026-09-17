"""
Analyse the telecommunications accessibility of bushfire-exposed evacuation
facilities in New South Wales by calculating the distance to the nearest
telecommunications tower.

Facilities are classified according to distance-based accessibility thresholds.
The script processes three bushfire categories, exports spatial results as
GeoJSON, writes a text summary, and generates comparison figures.
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


# Input files
CATEGORY_FILES = {
    "Category 1": RESULTS_DIR / "category_1_within_500m.geojson",
    "Category 2": RESULTS_DIR / "category_2_within_500m.geojson",
    "Category 3": RESULTS_DIR / "category_3_within_500m.geojson",
}

TOWER_FILE = TOWERS_DIR / "cell_tower_dataset.json"

PROJECTED_CRS = "EPSG:3577"
GEOGRAPHIC_CRS = "EPSG:4326"


def classify_distance(distance):
    """Classify tower accessibility according to distance thresholds."""
    if distance <= 100:
        return "Co-located / Immediate Proximity"
    if distance <= 250:
        return "Nearby Infrastructure"
    if distance <= 500:
        return "Moderate Accessibility"
    if distance <= 1000:
        return "Limited Accessibility"
    return "Potential Accessibility Concern"


def calculate_state_metrics(distances):
    """Calculate distance statistics and accessibility percentages."""
    total = len(distances)

    if total == 0:
        raise ValueError("No evacuation facilities were available for analysis.")

    inside_100 = sum(distance <= 100 for distance in distances)
    between_100_250 = sum(100 < distance <= 250 for distance in distances)
    between_250_500 = sum(250 < distance <= 500 for distance in distances)
    between_500_1000 = sum(500 < distance <= 1000 for distance in distances)
    over_1000 = sum(distance > 1000 for distance in distances)

    return {
        "mean": statistics.mean(distances),
        "median": statistics.median(distances),
        "0_100_pct": inside_100 / total * 100,
        "100_250_pct": between_100_250 / total * 100,
        "250_500_pct": between_250_500 / total * 100,
        "500_1000_pct": between_500_1000 / total * 100,
        "over_1000_pct": over_1000 / total * 100,
        "0_100_count": inside_100,
        "100_250_count": between_100_250,
        "250_500_count": between_250_500,
        "500_1000_count": between_500_1000,
        "over_1000_count": over_1000,
    }


def load_towers():
    """Load NSW telecommunications towers and project them for distance analysis."""
    with open(TOWER_FILE, encoding="utf-8") as file:
        tower_data = json.load(file)

    tower_records = []

    for tower in tower_data:
        if tower.get("state") != "NSW":
            continue

        latitude = tower.get("latitude")
        longitude = tower.get("longitude")

        if latitude in (None, "") or longitude in (None, ""):
            continue

        tower_records.append({
            "site_id": tower.get("site_id"),
            "geometry": Point(float(longitude), float(latitude)),
        })

    towers = gpd.GeoDataFrame(tower_records, crs=GEOGRAPHIC_CRS)

    if towers.empty:
        raise ValueError("No valid NSW telecommunications towers were found.")

    return towers.to_crs(PROJECTED_CRS)


def calculate_tower_distances(evacuation, towers):
    """Calculate the distance from each evacuation facility to its nearest tower."""
    nearest = gpd.sjoin_nearest(
        evacuation,
        towers[["site_id", "geometry"]],
        how="left",
        distance_col="tower_distance_m",
    )

    nearest_distances = nearest.groupby(nearest.index)["tower_distance_m"].min()

    return nearest_distances.reindex(evacuation.index).values


def write_summary(category_results, output_path):
    """Write telecommunications accessibility results to a text report."""
    with open(output_path, "w", encoding="utf-8") as file:
        file.write("NSW Bushfire Telecommunications Accessibility Analysis\n")
        file.write("=" * 60 + "\n\n")

        for category, result in category_results.items():
            metrics = result["metrics"]

            file.write(f"{category}\n")
            file.write("-" * 40 + "\n")
            file.write(f"Facilities analysed: {result['facility_count']}\n")
            file.write(f"Mean distance: {metrics['mean']:.2f} m\n")
            file.write(f"Median distance: {metrics['median']:.2f} m\n")
            file.write(f"0-100 m: {metrics['0_100_count']:,} ({metrics['0_100_pct']:.2f}%)\n")
            file.write(f"100-250 m: {metrics['100_250_count']:,} ({metrics['100_250_pct']:.2f}%)\n")
            file.write(f"250-500 m: {metrics['250_500_count']:,} ({metrics['250_500_pct']:.2f}%)\n")
            file.write(f"500-1000 m: {metrics['500_1000_count']:,} ({metrics['500_1000_pct']:.2f}%)\n")
            file.write(f">1000 m: {metrics['over_1000_count']:,} ({metrics['over_1000_pct']:.2f}%)\n\n")


def create_accessibility_figure(category_results, output_path):
    """Create a comparison of cumulative tower accessibility thresholds."""
    categories = list(category_results.keys())

    within_100 = [category_results[c]["metrics"]["0_100_pct"] for c in categories]
    within_250 = [
        category_results[c]["metrics"]["0_100_pct"] +
        category_results[c]["metrics"]["100_250_pct"]
        for c in categories
    ]
    within_500 = [
        category_results[c]["metrics"]["0_100_pct"] +
        category_results[c]["metrics"]["100_250_pct"] +
        category_results[c]["metrics"]["250_500_pct"]
        for c in categories
    ]

    plt.rcParams.update({
        "font.size": 13,
        "axes.titlesize": 16,
        "axes.labelsize": 14,
        "xtick.labelsize": 12,
        "ytick.labelsize": 12,
    })

    plt.figure(figsize=(10, 6))

    plt.plot(categories, within_100, marker="o", linewidth=2, label="≤100 m")
    plt.plot(categories, within_250, marker="o", linewidth=2, label="≤250 m")
    plt.plot(categories, within_500, marker="o", linewidth=2, label="≤500 m")

    plt.xlabel("Bushfire Category")
    plt.ylabel("Evacuation Facilities (%)")
    plt.title("Telecommunications Accessibility of Bushfire-Exposed Evacuation Facilities")
    plt.ylim(0, 100)
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()


def create_distance_distribution_figure(category_results, output_path):
    """Create a grouped bar chart showing facilities across tower-distance bands."""
    categories = list(category_results.keys())
    bands = ["0-100 m", "100-250 m", "250-500 m", "500-1000 m", ">1000 m"]

    values = {
        "0-100 m": [category_results[c]["metrics"]["0_100_pct"] for c in categories],
        "100-250 m": [category_results[c]["metrics"]["100_250_pct"] for c in categories],
        "250-500 m": [category_results[c]["metrics"]["250_500_pct"] for c in categories],
        "500-1000 m": [category_results[c]["metrics"]["500_1000_pct"] for c in categories],
        ">1000 m": [category_results[c]["metrics"]["over_1000_pct"] for c in categories],
    }

    x = range(len(categories))
    width = 0.15

    plt.rcParams.update({
        "font.size": 13,
        "axes.titlesize": 16,
        "axes.labelsize": 14,
        "xtick.labelsize": 12,
        "ytick.labelsize": 12,
    })

    plt.figure(figsize=(12, 6))

    for index, band in enumerate(bands):
        positions = [value + (index - 2) * width for value in x]
        plt.bar(positions, values[band], width=width, label=band, edgecolor="black")

    plt.xticks(list(x), categories)
    plt.xlabel("Bushfire Category")
    plt.ylabel("Evacuation Facilities (%)")
    plt.title("Distribution of Evacuation Facilities by Distance to Nearest Tower")
    plt.legend(title="Tower Distance")
    plt.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()


def create_median_distance_figure(category_results, output_path):
    """Create a bar chart comparing median distance to the nearest tower."""
    categories = list(category_results.keys())
    medians = [category_results[c]["metrics"]["median"] for c in categories]

    plt.rcParams.update({
        "font.size": 13,
        "axes.titlesize": 16,
        "axes.labelsize": 14,
        "xtick.labelsize": 12,
        "ytick.labelsize": 12,
    })

    plt.figure(figsize=(9, 6))

    plt.bar(categories, medians, edgecolor="black")

    plt.xlabel("Bushfire Category")
    plt.ylabel("Median Distance to Nearest Tower (m)")
    plt.title("Median Telecommunications Distance by Bushfire Category")
    plt.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()


def export_category_1_subsets():
    """Export Category 1 facilities according to tower-distance thresholds."""
    category1_file = RESULTS_DIR / "category_1_tower_analysis.geojson"
    category1 = gpd.read_file(category1_file)

    within_500m = category1[category1["tower_distance_m"] <= 500].copy()

    between_500m_1000m = category1[
        (category1["tower_distance_m"] > 500) &
        (category1["tower_distance_m"] <= 1000)
    ].copy()

    over_1000m = category1[category1["tower_distance_m"] > 1000].copy()

    within_500m.to_file(
        RESULTS_DIR / "category_1_within_500m_tower.geojson",
        driver="GeoJSON",
    )

    between_500m_1000m.to_file(
        RESULTS_DIR / "category_1_500m_to_1000m_tower.geojson",
        driver="GeoJSON",
    )

    over_1000m.to_file(
        RESULTS_DIR / "category_1_over_1000m_tower.geojson",
        driver="GeoJSON",
    )

    print(f"Within 500 m: {len(within_500m):,}")
    print(f"500-1000 m: {len(between_500m_1000m):,}")
    print(f">1000 m: {len(over_1000m):,}")


def main():
    """Run the NSW bushfire telecommunications accessibility analysis."""
    print("Loading telecommunications towers...")
    towers = load_towers()
    print(f"Loaded {len(towers):,} NSW towers.")

    category_results = {}

    for category_name, evac_file in CATEGORY_FILES.items():
        print(f"\nProcessing {category_name}...")

        evacuation = gpd.read_file(evac_file)
        print(f"Loaded {len(evacuation):,} evacuation facilities.")

        evacuation = evacuation.to_crs(PROJECTED_CRS)

        print("Calculating nearest tower distances...")
        evacuation["tower_distance_m"] = calculate_tower_distances(evacuation, towers)

        if evacuation["tower_distance_m"].isna().any():
            raise ValueError(f"One or more facilities could not be matched to {category_name} towers.")

        evacuation["tower_accessibility"] = evacuation["tower_distance_m"].apply(classify_distance)

        distances = evacuation["tower_distance_m"].tolist()
        metrics = calculate_state_metrics(distances)
        classification_counts = evacuation["tower_accessibility"].value_counts()

        category_results[category_name] = {
            "facility_count": len(evacuation),
            "metrics": metrics,
            "classification_counts": classification_counts,
        }

        output_geojson = RESULTS_DIR / f"{category_name.lower().replace(' ', '_')}_tower_analysis.geojson"

        evacuation.to_crs(GEOGRAPHIC_CRS).to_file(
            output_geojson,
            driver="GeoJSON",
        )

        print(
            f"Completed {category_name}: "
            f"mean={metrics['mean']:.2f} m, "
            f"median={metrics['median']:.2f} m"
        )

    print("\nWriting analysis report...")
    write_summary(
        category_results,
        RESULTS_DIR / "tower_accessibility_analysis.txt",
    )

    print("Generating accessibility figure...")
    create_accessibility_figure(
        category_results,
        FIGURES_DIR / "tower_accessibility_comparison.png",
    )

    print("Generating distance distribution figure...")
    create_distance_distribution_figure(
        category_results,
        FIGURES_DIR / "tower_accessibility_distance_distribution.png",
    )

    print("Generating median distance figure...")
    create_median_distance_figure(
        category_results,
        FIGURES_DIR / "tower_accessibility_median_distance.png",
    )

    print("\nResults")

    for category_name, result in category_results.items():
        metrics = result["metrics"]

        print(f"\n{category_name}")
        print(f"Facilities analysed: {result['facility_count']:,}")
        print(f"Mean distance: {metrics['mean']:.2f} m")
        print(f"Median distance: {metrics['median']:.2f} m")
        print(f"Within 100 m: {metrics['0_100_pct']:.2f}%")
        print(f"Within 250 m: {metrics['0_100_pct'] + metrics['100_250_pct']:.2f}%")
        print(f"Within 500 m: {metrics['0_100_pct'] + metrics['100_250_pct'] + metrics['250_500_pct']:.2f}%")
        print(f"Within 1000 m: {100 - metrics['over_1000_pct']:.2f}%")
        print(f"Over 1000 m: {metrics['over_1000_pct']:.2f}%")

    print("\nExporting Category 1 tower proximity subsets...")
    export_category_1_subsets()

    print("\nAnalysis complete.")


if __name__ == "__main__":
    main()