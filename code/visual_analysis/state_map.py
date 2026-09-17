"""
Create an interactive map of a selected Australian state showing the state
boundary, evacuation facilities, and mobile tower locations.

Folium is used to provide interactive layer controls.

Inputs:
    data/boundaries/<state>_boundary.geojson
    data/evacuation_datasets/<state>.geojson
    data/telecommunications_datasets/cell_tower_dataset.json

Output:
    maps/<state>_map.html
"""

import json
from pathlib import Path

import folium
from shapely.geometry import Point, shape


# Selected state
SELECTED_STATE = "south_australia"


# Project paths
PROJECT_ROOT = Path(__file__).resolve().parents[2]
BASE_DIR = PROJECT_ROOT / "data"

BOUNDARIES_DIR = BASE_DIR / "boundaries"
TOWERS_DIR = BASE_DIR / "telecommunications_datasets"
EVACUATION_DIR = BASE_DIR / "evacuation_datasets"

MAP_DIR = PROJECT_ROOT / "maps"
MAP_DIR.mkdir(parents=True, exist_ok=True)


# Input and output files
STATE_BOUNDARY_FILE = BOUNDARIES_DIR / f"{SELECTED_STATE}_boundary.geojson"
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
    """Load the state boundary geometry."""
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
    """Filter mobile towers to those within or on the state boundary."""
    filtered = []

    for (latitude, longitude), properties in tower_points:
        point = Point(longitude, latitude)

        if isinstance(state_polygon, list):
            inside = any(
                polygon.contains(point) or polygon.touches(point)
                for polygon in state_polygon
            )
        else:
            inside = (
                state_polygon.contains(point)
                or state_polygon.touches(point)
            )

        if inside:
            filtered.append(((latitude, longitude), properties))

    return filtered


def add_state_boundary(map_object, state_data):
    """Add the state boundary to the map."""
    state_name = SELECTED_STATE.replace("_", " ").title()

    folium.GeoJson(
        state_data,
        name=state_name,
        style_function=lambda feature: {
            "fillColor": "#377eb8",
            "color": "#377eb8",
            "weight": 2,
            "fillOpacity": 0.5,
        },
        tooltip=state_name,
    ).add_to(map_object)


def add_evacuation_layer(map_object, evacuation_points):
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


def add_tower_layer(map_object, tower_points):
    """Add mobile towers to the map."""
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


    add_state_boundary(
        map_object,
        load_json(STATE_BOUNDARY_FILE),
    )

    add_evacuation_layer(
        map_object,
        evacuation_points,
    )

    add_tower_layer(
        map_object,
        tower_points,
    )

    folium.LayerControl(collapsed=False).add_to(map_object)

    map_object.save(output_path)

    print(f"Map saved to {output_path}")


def main():
    """Load spatial datasets and create the selected-state map."""
    state_name = SELECTED_STATE.replace("_", " ").title()

    print(f"Creating map for {state_name}...")

    print("Loading state boundary...")
    state_polygon = load_state_polygon(STATE_BOUNDARY_FILE)

    print("Loading evacuation facilities...")
    evacuation_points = extract_points(load_json(EVACUATION_FILE))

    print("Loading mobile towers...")
    tower_points = extract_points(load_json(TOWER_FILE))

    print("Filtering towers to the selected state...")
    tower_points = filter_towers_in_state(
        tower_points,
        state_polygon,
    )

    print(f"Evacuation facilities: {len(evacuation_points):,}")
    print(f"Mobile towers: {len(tower_points):,}")

    build_map(
        evacuation_points,
        tower_points,
        OUTPUT_HTML,
    )


if __name__ == "__main__":
    main()