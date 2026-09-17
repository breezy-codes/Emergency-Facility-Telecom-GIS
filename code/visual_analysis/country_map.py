"""
Create an interactive map of Australia showing state boundaries, evacuation
facilities, and mobile tower locations.

The map uses Folium and provides layer controls for toggling state boundaries,
evacuation facilities, and mobile towers.

Inputs:
    data/boundaries/*.geojson
    data/evacuation_datasets/*.geojson
    data/telecommunications_datasets/cell_tower_dataset.json

Output:
    maps/country_map.html
"""

import json
from pathlib import Path

import folium


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"
BOUNDARIES_DIR = BASE_DIR / "boundaries"
TOWERS_DIR = BASE_DIR / "telecommunications_datasets"
EVACUATION_DIR = BASE_DIR / "evacuation_datasets"
MAP_DIR = PROJECT_ROOT / "maps"

MAP_DIR.mkdir(parents=True, exist_ok=True)


# Input files
STATE_FILES = [
    "south_australia_boundary.geojson",
    "new_south_wales_boundary.geojson",
    "tasmania_boundary.geojson",
    "victoria_boundary.geojson",
    "northern_territory_boundary.geojson",
]

EVACUATION_FILES = [
    "south_australia.geojson",
    "new_south_wales.geojson",
    "tasmania.geojson",
    "victoria.geojson",
    "northern_territory.geojson",
]

TOWER_FILE = TOWERS_DIR / "cell_tower_dataset.json"
OUTPUT_HTML = MAP_DIR / "country_map.html"


# State boundary colours
STATE_COLOURS = {
    "south_australia_boundary.geojson": "#e41a1c",
    "new_south_wales_boundary.geojson": "#377eb8",
    "tasmania_boundary.geojson": "#4daf4a",
    "victoria_boundary.geojson": "#984ea3",
    "northern_territory_boundary.geojson": "#ff7f00",
}


def load_json(source):
    """Load a JSON file."""
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
                points.append((
                    (float(latitude), float(longitude)),
                    feature.get("properties", {}),
                ))

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
                points.append(((latitude, longitude), data.get("properties", {})))
            except (ValueError, TypeError):
                pass

    return points


def add_state_boundaries(map_object):
    """Add state boundary layers to the map."""
    for state_file in STATE_FILES:
        state_data = load_json(BOUNDARIES_DIR / state_file)
        colour = STATE_COLOURS[state_file]
        state_name = state_file.replace("_boundary.geojson", "").replace("_", " ").title()

        folium.GeoJson(
            state_data,
            name=state_name,
            style_function=lambda feature, colour=colour: {
                "fillColor": colour,
                "color": colour,
                "weight": 2,
                "fillOpacity": 0.5,
                "opacity": 0.8,
            },
        ).add_to(map_object)


def add_evacuation_points(map_object, evacuation_points):
    """Add evacuation facilities to the map."""
    evacuation_layer = folium.FeatureGroup(
        name="Evacuation Points",
        show=True,
    )

    for (latitude, longitude), properties in evacuation_points:
        popup = folium.Popup(
            json.dumps(properties, indent=2),
            max_width=350,
        )

        folium.Marker(
            location=(latitude, longitude),
            popup=popup,
            icon=folium.Icon(
                color="red",
                icon="home",
            ),
        ).add_to(evacuation_layer)

    evacuation_layer.add_to(map_object)


def add_tower_points(map_object, tower_points):
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


def build_map(evacuation_points, tower_points, output_path):
    """Build and save the interactive map."""

    if not evacuation_points and not tower_points:
        raise ValueError("No evacuation or tower point features were found.")

    center = evacuation_points[0][0] if evacuation_points else tower_points[0][0]

    map_object = folium.Map(
        location=center,
        zoom_start=5,
        tiles=None,
    )

    # Refer to docs/basemaps.md for information about available basemaps. This also contains instructions for using CARTO Voyager with a personal API key. As well as explaining recent folium changes that require explicit basemap configuration.

    # OpenStreetMap (default)
    folium.TileLayer(
        tiles="https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        attr="&copy; <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a> contributors",
        name="OpenStreetMap",
        referrer_policy="strict-origin",
    ).add_to(map_object)

    # CARTO Voyager
    # Requires a personal CARTO API key. See docs/basemaps.md.
    #
    # folium.TileLayer(
    #     tiles="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png?key=YOUR_KEY",
    #     attr='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>, &copy; <a href="https://carto.com/attributions">CARTO</a>',
    #     subdomains="abcd",
    #     max_zoom=20,
    #     name="CARTO Voyager",
    # ).add_to(map_object)

    add_state_boundaries(map_object)
    add_evacuation_points(map_object, evacuation_points)
    add_tower_points(map_object, tower_points)

    folium.LayerControl(collapsed=False).add_to(map_object)

    map_object.save(output_path)

    print(f"Map saved to {output_path}")


def main():
    """Load spatial datasets and create the interactive map."""
    print("Loading evacuation facilities...")

    evacuation_points = []

    for filename in EVACUATION_FILES:
        points = extract_points(load_json(EVACUATION_DIR / filename))
        evacuation_points.extend(points)
        print(f"{filename}: {len(points):,} points")

    print(f"Total evacuation points: {len(evacuation_points):,}")

    print("\nLoading mobile towers...")
    tower_points = extract_points(load_json(TOWER_FILE))
    print(f"Total mobile towers: {len(tower_points):,}")

    print("\nBuilding map...")
    build_map(
        evacuation_points,
        tower_points,
        OUTPUT_HTML,
    )


if __name__ == "__main__":
    main()