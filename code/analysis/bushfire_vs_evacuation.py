"""Analyse the proximity of evacuation facilities to bushfire-prone land in New South Wales, Australia.

This script calculates the distance from each evacuation facility to the nearest
bushfire-prone area for three bushfire risk categories and classifies proximity
according to predefined distance bands. Summary statistics and spatial results are
generated for each category. Results are exported as GeoJSON files, a text report,
and a publication-quality figure showing the distribution of evacuation facilities
across distance bands.
"""

from pathlib import Path

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
EVACUATION_DIR = BASE_DIR / "evacuation_datasets"
BUSHFIRE_DIR = BASE_DIR / "bushfire_datasets"
RESULTS_DIR = PROJECT_ROOT / "results"
FIGURES_DIR = PROJECT_ROOT / "figures"

RESULTS_DIR.mkdir(parents=True, exist_ok=True)
FIGURES_DIR.mkdir(parents=True, exist_ok=True)

EVACUATION_FILE = EVACUATION_DIR / "new_south_wales.geojson"

CATEGORY_FILES = {
    "Category 1": BUSHFIRE_DIR / "bushfire_category_1_simplified.geojson",
    "Category 2": BUSHFIRE_DIR / "bushfire_category_2_simplified.geojson",
    "Category 3": BUSHFIRE_DIR / "bushfire_category_3_simplified.geojson",
}

PROJECTED_CRS = "EPSG:3577"
GEOGRAPHIC_CRS = "EPSG:4326"

DISTANCE_BANDS = [
    (0, 0, "Inside"),
    (0, 250, "0-250m"),
    (250, 500, "250-500m"),
    (500, 1000, "500-1000m"),
    (1000, 2500, "1000-2500m"),
    (2500, 5000, "2500-5000m"),
    (5000, 10000, "5000-10000m"),
    (10000, float("inf"), ">10000m"),
]

BAND_ORDER = [
    "Inside",
    "0-250m",
    "250-500m",
    "500-1000m",
    "1000-2500m",
    "2500-5000m",
    "5000-10000m",
    ">10000m",
]


def calculate_proximity_statistics(distances):
    """Calculate the number and percentage of facilities within each distance band."""
    if len(distances) == 0:
        raise ValueError("No distances were available for analysis.")

    total = len(distances)
    results = {}

    for lower, upper, label in DISTANCE_BANDS:
        if label == "Inside":
            count = (distances == 0).sum()
        elif upper == float("inf"):
            count = (distances > lower).sum()
        else:
            count = ((distances > lower) & (distances <= upper)).sum()

        results[label] = {"count": int(count), "percentage": count / total * 100}

    return results


def calculate_nearest_distances(evacuation, bushfire):
    """Calculate the distance from each evacuation facility to the nearest bushfire area."""
    nearest = gpd.sjoin_nearest(evacuation, bushfire[["geometry"]], how="left", distance_col="distance_m")
    nearest_distances = nearest.groupby(nearest.index)["distance_m"].min()

    return nearest_distances.reindex(evacuation.index).values


def create_distance_column_name(category):
    """Create a standardised distance column name for a bushfire category."""
    return f"{category.lower().replace(' ', '_').replace('-', '_')}_distance_m"


def write_summary(path, category_results):
    """Write bushfire proximity statistics to a text report."""
    with open(path, "w", encoding="utf-8") as file:
        file.write("New South Wales Bushfire Proximity Analysis\n")
        file.write("=" * 60 + "\n\n")

        for category, results in category_results.items():
            file.write(f"{category}\n")
            file.write("-" * 50 + "\n")

            for label in BAND_ORDER:
                file.write(f"{label}: {results[label]['count']:,} ({results[label]['percentage']:.2f}%)\n")

            file.write("\n")


def create_proximity_figure(category_results, path):
    """Generate and save a figure comparing proximity distributions across bushfire categories."""
    plt.rcParams.update({"font.size": 14, "axes.titlesize": 16, "axes.labelsize": 14, "xtick.labelsize": 12, "ytick.labelsize": 13})

    plt.figure(figsize=(12, 6))

    for category, results in category_results.items():
        percentages = [results[band]["percentage"] for band in BAND_ORDER]
        plt.plot(BAND_ORDER, percentages, marker="o", label=category)

    plt.xlabel("Distance to Bushfire-Prone Land")
    plt.ylabel("Evacuation Facilities (%)")
    plt.title("Proximity of NSW Evacuation Facilities to Bushfire-Prone Land")
    plt.legend(title="Bushfire Category")
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(path, dpi=300, bbox_inches="tight")
    plt.close()

def create_threshold_comparison_figure(category_results, path):
    """Generate and save a figure comparing the percentage of facilities within key distance thresholds."""
    categories = list(category_results.keys())
    thresholds = {
        "≤250 m": "0-250m",
        "≤500 m": "250-500m",
        "≤1 km": "500-1000m",
    }

    percentages = {}

    for category in categories:
        results = category_results[category]
        percentages[category] = {
            "≤250 m": results["Inside"]["percentage"] + results["0-250m"]["percentage"],
            "≤500 m": results["Inside"]["percentage"] + results["0-250m"]["percentage"] + results["250-500m"]["percentage"],
            "≤1 km": results["Inside"]["percentage"] + results["0-250m"]["percentage"] + results["250-500m"]["percentage"] + results["500-1000m"]["percentage"],
        }

    x = np.arange(len(thresholds))
    width = 0.25

    plt.rcParams.update({"font.size": 14, "axes.titlesize": 16, "axes.labelsize": 14, "xtick.labelsize": 13, "ytick.labelsize": 13})

    plt.figure(figsize=(10, 6))

    for index, category in enumerate(categories):
        values = [percentages[category][threshold] for threshold in thresholds]
        plt.bar(x + (index - 1) * width, values, width, label=category, edgecolor="black", linewidth=1)

    plt.xlabel("Distance Threshold")
    plt.ylabel("Evacuation Facilities (%)")
    plt.title("Evacuation Facilities within Key Distances of Bushfire-Prone Land")
    plt.xticks(x, thresholds.keys())
    plt.ylim(0, 100)
    plt.legend(title="Bushfire Category")
    plt.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(path, dpi=300, bbox_inches="tight")
    plt.close()

def create_median_distance_figure(evacuation, category_columns, path):
    """Generate and save a figure comparing median distance to bushfire-prone land by category."""
    categories = list(category_columns.keys())
    medians = [evacuation[column].median() for column in category_columns.values()]

    plt.rcParams.update({"font.size": 14, "axes.titlesize": 16, "axes.labelsize": 14, "xtick.labelsize": 13, "ytick.labelsize": 13})

    plt.figure(figsize=(8, 6))
    bars = plt.bar(categories, medians, edgecolor="black", linewidth=1)

    plt.xlabel("Bushfire Category")
    plt.ylabel("Median Distance (m)")
    plt.title("Median Distance of Evacuation Facilities to Bushfire-Prone Land")

    for bar, median in zip(bars, medians):
        plt.text(bar.get_x() + bar.get_width() / 2, bar.get_height(), f"{median:,.0f} m", ha="center", va="bottom", fontsize=11)

    plt.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(path, dpi=300, bbox_inches="tight")
    plt.close()

def export_high_risk_facilities(evacuation, category_columns):
    """Export evacuation facilities located within 500 m of each bushfire risk category."""
    for category, column in category_columns.items():
        facilities = evacuation[evacuation[column] <= 500].copy()
        category_number = category.split()[-1]
        output_path = RESULTS_DIR / f"category_{category_number}_within_500m.geojson"
        facilities.to_crs(GEOGRAPHIC_CRS).to_file(output_path, driver="GeoJSON")


def main():
    """Execute the NSW bushfire proximity analysis."""
    print("Loading evacuation facilities...")
    evacuation = gpd.read_file(EVACUATION_FILE).to_crs(PROJECTED_CRS)
    print(f"Loaded {len(evacuation):,} evacuation facilities.")

    category_results = {}
    category_columns = {}

    for category, category_file in CATEGORY_FILES.items():
        print(f"Processing {category}...")

        bushfire = gpd.read_file(category_file).to_crs(PROJECTED_CRS)

        if bushfire.empty:
            raise ValueError(f"No features were found for {category}.")

        print("Fixing geometries...")
        bushfire["geometry"] = bushfire.geometry.make_valid()

        print("Calculating nearest distances...")
        column_name = create_distance_column_name(category)
        evacuation[column_name] = calculate_nearest_distances(evacuation, bushfire)

        if evacuation[column_name].isna().any():
            raise ValueError(f"One or more evacuation facilities could not be matched to {category}.")

        distances = evacuation[column_name]
        category_results[category] = calculate_proximity_statistics(distances)
        category_columns[category] = column_name

        print(f"Completed {category} (min={distances.min():.2f} m, median={distances.median():.2f} m, max={distances.max():.2f} m).")

    print("Writing spatial results...")
    evacuation.to_crs(GEOGRAPHIC_CRS).to_file(RESULTS_DIR / "evacuation_bushfire_analysis.geojson", driver="GeoJSON")

    print("Writing analysis report...")
    write_summary(RESULTS_DIR / "bushfire_proximity_analysis.txt", category_results)

    print("Generating proximity figures...")
    create_proximity_figure(category_results, FIGURES_DIR / "bushfire_proximity_analysis.png")
    create_threshold_comparison_figure(category_results, FIGURES_DIR / "bushfire_threshold_comparison.png")
    create_median_distance_figure(evacuation, category_columns, FIGURES_DIR / "bushfire_median_distance.png")

    print("Exporting facilities within 500 m of bushfire-prone land...")
    export_high_risk_facilities(evacuation, category_columns)

    print("Analysis complete.")


if __name__ == "__main__":
    main()