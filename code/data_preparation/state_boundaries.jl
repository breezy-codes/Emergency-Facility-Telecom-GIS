using HTTP
using GeoJSON
using GeoDataFrames
using DataFrames
using ArchGDAL

# Project paths
PROJECT_ROOT = dirname(dirname(@__DIR__))
BASE_DIR = joinpath(PROJECT_ROOT, "data")
BOUNDARIES_DIR = joinpath(BASE_DIR, "boundaries")

mkpath(BOUNDARIES_DIR)

# ABS GeoServices API
BOUNDARY_URL = "https://geo.abs.gov.au/arcgis/rest/services/ASGS2021/STE/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson"

# States included in the analysis
STATES = [
    "New South Wales",
    "Victoria",
    "South Australia",
    "Tasmania",
]

"""
    download_boundaries()
Download the Australian state boundaries from the ABS GeoServices API and return them as a GeoJSON object
"""
function download_boundaries()
    response = HTTP.get(BOUNDARY_URL)
    response.status == 200 || error("Failed to download boundaries: HTTP $(response.status)")
    return GeoJSON.read(String(response.body))
end

"""
    save_state_boundaries(boundaries)
Save the selected Australian state boundaries to individual GeoJSON files in the `data/boundaries` directory. Each file is named after the state, with spaces replaced by underscores and in lowercase.
"""
function save_state_boundaries(boundaries)
    features = boundaries.features
    selected = filter(feature -> feature.properties[:state_name_2021] in STATES, features)
    isempty(selected) && error("No matching state boundaries were found.")

    for feature in selected
        state_name = feature.properties[:state_name_2021]
        filename = lowercase(replace(state_name, " " => "_")) * "_boundary.geojson"
        filepath = joinpath(BOUNDARIES_DIR, filename)

        collection = GeoJSON.FeatureCollection(features=[feature])

        open(filepath, "w") do file
            write(file, GeoJSON.write(collection))
        end

        println("Saved $filename")
    end
end
 
println("Downloading Australian state boundaries...")
boundaries = download_boundaries()
println("Downloaded $(length(boundaries.features)) state boundaries.")
save_state_boundaries(boundaries)
println("\nBoundary download complete.")