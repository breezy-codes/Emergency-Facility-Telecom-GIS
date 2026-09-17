"""
Create an interactive map of a selected Australian state showing the state
boundary, evacuation facilities, mobile towers, and Category 1 bushfire-exposed
facilities classified by their distance to the nearest tower.

Folium is used to provide interactive layer controls.

Inputs:
    data/bushfire_datasets/bushfire_category_1_simplified.geojson
    data/evacuation_datasets/<state>.geojson
    data/telecommunications_datasets/cell_tower_dataset.json
    results/category_1_within_500m_tower.geojson
    results/category_1_500m_to_1000m_tower.geojson
    results/category_1_over_1000m_tower.geojson

Output:
    maps/<state>_map.html
"""

import json
from pathlib import Path

import folium
from shapely.geometry import Point, shape


# Selected state
SELECTED_STATE = "new_south_wales"


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"

BOUNDARIES_DIR = BASE_DIR / "boundaries"
TOWERS_DIR = BASE_DIR / "telecommunications_datasets"
EVACUATION_DIR = BASE_DIR / "evacuation_datasets"
BUSHFIRE_DIR = BASE_DIR / "bushfire_datasets"

MAP_DIR = PROJECT_ROOT / "maps"
RESULTS_DIR = PROJECT_ROOT / "results"

MAP_DIR.mkdir(parents=True, exist_ok=True)


# Input files
CATEGORY_500_TO_1000_FILE = RESULTS_DIR / "category_1_500m_to_1000m_tower.geojson"
CATEGORY_WITHIN_500_FILE = RESULTS_DIR / "category_1_within_500m_tower.geojson"
CATEGORY_OVER_1000_FILE = RESULTS_DIR / "category_1_over_1000m_tower.geojson"

STATE_BOUNDARY_FILE = BUSHFIRE_DIR / "bushfire_category_1_simplified.geojson"
EVACUATION_FILE = EVACUATION_DIR / f"{SELECTED_STATE}.geojson"
TOWER_FILE = TOWERS_DIR / "cell_tower_dataset.json"

OUTPUT_HTML = MAP_DIR / f"{SELECTED_STATE}_map.html"


def load_json(source):
    """Load a JSON or GeoJSON file."""
    with open(source, encoding="utf-8") as file:
        return json.load(file)


def extract_points(data):
    """Extract point coordinates and properties from supported data formats."""
    points = []

    if isinstance(data, dict) and data.get("type") == "FeatureCollection":
        for feature in data.get("features", []):
            geometry = feature.get("geometry") or {}
            coordinates = geometry.get("coordinates")

            if coordinates and len(coordinates) >= 2:
                longitude, latitude = coordinates[:2]

                try:
                    points.append((
                        (float(latitude), float(longitude)),
                        feature.get("properties", {}),
                    ))
                except (ValueError, TypeError):
                    pass

    elif isinstance(data, list):
        for obj in data:
            if "latitude" in obj and "longitude" in obj:
                try:
                    latitude = float(obj["latitude"])
                    longitude = float(obj["longitude"])
                    properties = {
                        key: value
                        for key, value in obj.items()
                        if key not in {"latitude", "longitude"}
                    }
                    points.append(((latitude, longitude), properties))
                    continue
                except (ValueError, TypeError):
                    pass

            geo_point = obj.get("geo_point_2d")

            if (
                isinstance(geo_point, dict)
                and "lat" in geo_point
                and "lon" in geo_point
            ):
                try:
                    latitude = float(geo_point["lat"])
                    longitude = float(geo_point["lon"])
                    properties = {
                        key: value
                        for key, value in obj.items()
                        if key not in {"geo_point_2d", "geo_shape", "geometry"}
                    }
                    points.append(((latitude, longitude), properties))
                    continue
                except (ValueError, TypeError):
                    pass

            geometry = obj.get("geometry") or {}
            coordinates = geometry.get("coordinates")

            if coordinates and len(coordinates) >= 2:
                try:
                    longitude = float(coordinates[0])
                    latitude = float(coordinates[1])
                    properties = {
                        key: value
                        for key, value in obj.items()
                        if key != "geometry"
                    }
                    points.append(((latitude, longitude), properties))
                except (ValueError, TypeError):
                    pass

    elif isinstance(data, dict) and data.get("geometry"):
        coordinates = data["geometry"].get("coordinates")

        if coordinates and len(coordinates) >= 2:
            try:
                longitude = float(coordinates[0])
                latitude = float(coordinates[1])
                points.append((
                    (latitude, longitude),
                    data.get("properties", {}),
                ))
            except (ValueError, TypeError):
                pass

    return points


def load_state_polygon(boundary_file):
    """Load the bushfire boundary polygon used to filter tower locations."""
    data = load_json(boundary_file)

    if data.get("type") == "FeatureCollection":
        geometries = [
            shape(feature["geometry"])
            for feature in data.get("features", [])
            if feature.get("geometry")
        ]

        if not geometries:
            raise ValueError(f"No geometries found in {boundary_file}.")

        return geometries[0] if len(geometries) == 1 else geometries

    if data.get("type") == "Feature":
        return shape(data["geometry"])

    return shape(data)


def filter_towers_in_state(tower_points, state_polygon):
    """Filter tower points to those within or on the state boundary."""
    if isinstance(state_polygon, list):
        return [
            ((latitude, longitude), properties)
            for (latitude, longitude), properties in tower_points
            if any(
                polygon.contains(Point(longitude, latitude))
                or polygon.touches(Point(longitude, latitude))
                for polygon in state_polygon
            )
        ]

    return [
        ((latitude, longitude), properties)
        for (latitude, longitude), properties in tower_points
        if state_polygon.contains(Point(longitude, latitude))
        or state_polygon.touches(Point(longitude, latitude))
    ]


def add_state_boundary(map_object):
    """Add the bushfire-prone land boundary layer to the map."""
    state_data = load_json(STATE_BOUNDARY_FILE)
    state_name = SELECTED_STATE.replace("_", " ").title()

    folium.GeoJson(
        state_data,
        name=f"{state_name} Bushfire-Prone Land",
        style_function=lambda feature: {
            "fillColor": "#377eb8",
            "color": "#377eb8",
            "weight": 2,
            "fillOpacity": 0.5,
        },
        tooltip=state_name,
    ).add_to(map_object)


def add_tower_layer(map_object, tower_points):
    """Add mobile tower locations to the map."""
    tower_layer = folium.FeatureGroup(
        name="Mobile Towers",
        show=True,
    )

    for (latitude, longitude), properties in tower_points:
        popup = folium.Popup(
            json.dumps(properties, indent=2),
            max_width=350,
        )

        folium.CircleMarker(
            location=(latitude, longitude),
            radius=3,
            popup=popup,
            fill=True,
        ).add_to(tower_layer)

    tower_layer.add_to(map_object)


def add_category_layer(map_object, points, name, colour):
    """Add a bushfire-exposed evacuation facility category to the map."""
    layer = folium.FeatureGroup(
        name=name,
        show=True,
    )

    for (latitude, longitude), properties in points:
        popup = folium.Popup(
            json.dumps(properties, indent=2),
            max_width=350,
        )

        folium.CircleMarker(
            location=(latitude, longitude),
            radius=15,
            color=colour,
            fill=True,
            fill_color=colour,
            fill_opacity=0.8,
            popup=popup,
        ).add_to(layer)

    layer.add_to(map_object)


def build_map(
    evacuation_points,
    tower_points,
    category_500_to_1000,
    category_within_500,
    category_over_1000,
    output_path,
):
    """Build and save the interactive state map."""
    if not evacuation_points and not tower_points:
        raise ValueError("No evacuation or tower point features were found.")

    center = (
        evacuation_points[0][0]
        if evacuation_points
        else tower_points[0][0]
    )

    map_object = folium.Map(
        location=center,
        zoom_start=7,
        tiles="cartodbpositron",
    )

    add_state_boundary(map_object)
    add_tower_layer(map_object, tower_points)

    add_category_layer(
        map_object,
        category_within_500,
        "Category 1 (<500 m Tower)",
        "green",
    )

    add_category_layer(
        map_object,
        category_500_to_1000,
        "Category 1 (500-1000 m Tower)",
        "orange",
    )

    add_category_layer(
        map_object,
        category_over_1000,
        "Category 1 (>1000 m Tower)",
        "red",
    )

    folium.LayerControl(collapsed=False).add_to(map_object)

    map_object.save(output_path)

    print(f"Map saved to {output_path}")


def main():
    """Load spatial datasets and create the selected-state map."""
    print(f"Creating map for {SELECTED_STATE.replace('_', ' ').title()}...")

    print("Loading Category 1 proximity datasets...")
    category_500_to_1000 = extract_points(load_json(CATEGORY_500_TO_1000_FILE))
    category_within_500 = extract_points(load_json(CATEGORY_WITHIN_500_FILE))
    category_over_1000 = extract_points(load_json(CATEGORY_OVER_1000_FILE))

    print("Loading state boundary...")
    state_polygon = load_state_polygon(STATE_BOUNDARY_FILE)

    print("Loading evacuation facilities...")
    evacuation_points = extract_points(load_json(EVACUATION_FILE))

    print("Loading mobile towers...")
    tower_points = extract_points(load_json(TOWER_FILE))

    print("Filtering towers to the selected state...")
    tower_points = filter_towers_in_state(tower_points, state_polygon)

    print(f"Evacuation facilities: {len(evacuation_points):,}")
    print(f"Mobile towers: {len(tower_points):,}")
    print(f"Within 500 m: {len(category_within_500):,}")
    print(f"500-1000 m: {len(category_500_to_1000):,}")
    print(f">1000 m: {len(category_over_1000):,}")

    build_map(
        evacuation_points,
        tower_points,
        category_500_to_1000,
        category_within_500,
        category_over_1000,
        OUTPUT_HTML,
    )


if __name__ == "__main__":
    main()