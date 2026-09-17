"""Analyse the proximity of evacuation facilities to flood overlay areas in Victoria, Australia.

This script calculates the distance from each evacuation facility to the nearest flood
overlay area and classifies proximity according to predefined distance bands. The
analysis outputs a GeoJSON dataset containing the calculated distances and proximity
classifications, a text summary of the results, a visualisation of the distance
distribution, and a subset of facilities located within 500 m of a flood overlay.
"""

from pathlib import Path

import geopandas as gpd
import matplotlib.pyplot as plt


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
EVACUATION_DIR = BASE_DIR / "evacuation_datasets"
FLOOD_DIR = BASE_DIR / "flood_datasets"
RESULTS_DIR = PROJECT_ROOT / "results"
FIGURES_DIR = PROJECT_ROOT / "figures"

RESULTS_DIR.mkdir(parents=True, exist_ok=True)
FIGURES_DIR.mkdir(parents=True, exist_ok=True)

EVACUATION_FILE = EVACUATION_DIR / "victoria.geojson"
FLOOD_FILE = FLOOD_DIR / "vic_flood_simplified.geojson"

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
        raise ValueError("No evacuation facility distances are available for analysis.")

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


def calculate_nearest_flood_distances(evacuation, flood):
    """Calculate the distance from each evacuation facility to the nearest flood overlay."""
    nearest = gpd.sjoin_nearest(evacuation, flood[["geometry"]], how="left", distance_col="distance_m")
    nearest_distances = nearest.groupby(nearest.index)["distance_m"].min()
    evacuation["flood_distance_m"] = nearest_distances.reindex(evacuation.index).values

    if evacuation["flood_distance_m"].isna().any():
        raise ValueError("One or more evacuation facilities could not be matched to a flood overlay.")

    return evacuation


def write_summary(path, results):
    """Write the flood proximity statistics to a text report."""
    with open(path, "w", encoding="utf-8") as file:
        file.write("Victorian Flood Overlay Proximity Analysis\n")
        file.write("=" * 50 + "\n\n")

        for label in BAND_ORDER:
            file.write(f"{label}: {results[label]['count']:,} ({results[label]['percentage']:.2f}%)\n")


def create_proximity_plot(results, path):
    """Create and save a plot showing the distribution of evacuation facilities by distance band."""
    percentages = [results[band]["percentage"] for band in BAND_ORDER]

    plt.figure(figsize=(12, 6))
    plt.plot(BAND_ORDER, percentages, marker="o", label="Flood Overlay")
    plt.xlabel("Distance Band")
    plt.ylabel("Evacuation Facilities (%)")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(path, dpi=300, bbox_inches="tight")
    plt.close()


def main():
    """Execute the flood overlay proximity analysis."""
    print("Loading evacuation facilities...")
    evacuation = gpd.read_file(EVACUATION_FILE).to_crs(PROJECTED_CRS)
    print(f"Loaded {len(evacuation):,} evacuation facilities.")

    print("Loading flood overlay data...")
    flood = gpd.read_file(FLOOD_FILE).to_crs(PROJECTED_CRS)
    print(f"Loaded {len(flood):,} flood overlay features.")

    print("Validating flood geometries...")
    flood["geometry"] = flood.geometry.make_valid()

    print("Calculating distances to nearest flood overlay...")
    evacuation = calculate_nearest_flood_distances(evacuation, flood)

    evacuation["flood_proximity"] = evacuation["flood_distance_m"].apply(
        lambda distance: next(
            label for lower, upper, label in DISTANCE_BANDS
            if (label == "Inside" and distance == 0)
            or (label != "Inside" and distance > lower and distance <= upper)
        )
    )

    distances = evacuation["flood_distance_m"]
    results = calculate_proximity_statistics(distances)

    print(f"Completed flood analysis (min={distances.min():.2f} m, median={distances.median():.2f} m, max={distances.max():.2f} m).")

    print("Writing spatial results...")
    evacuation.to_crs(GEOGRAPHIC_CRS).to_file(RESULTS_DIR / "evacuation_flood_analysis.geojson", driver="GeoJSON")

    print("Writing summary report...")
    write_summary(RESULTS_DIR / "flood_proximity_analysis.txt", results)

    print("Generating proximity plot...")
    create_proximity_plot(results, FIGURES_DIR / "flood_proximity_analysis.png")

    print("Exporting facilities within 500 m of flood overlay...")
    high_exposure = evacuation[evacuation["flood_distance_m"] <= 500].copy()
    high_exposure.to_crs(GEOGRAPHIC_CRS).to_file(RESULTS_DIR / "flood_overlay_within_500m.geojson", driver="GeoJSON")

    print(f"Facilities within 500 m: {len(high_exposure):,}")
    print("Analysis complete.")


if __name__ == "__main__":
    main()