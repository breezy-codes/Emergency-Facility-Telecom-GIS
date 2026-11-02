# ============================================================
# PATHS AND SETTINGS
# ============================================================

# Data directories
const TELCO_SITES_PATH = "data/telecommunications_datasets/cell_tower_dataset.json"
const EVACUATION_DIR = "data/evacuation_datasets"
const BUSHFIRE_DIR = "data/bushfire_datasets"
const FLOOD_VIC_PATH = "data/flood_datasets"
const EARTHQUAKE_DIR = "data/earthquake_datasets"
const EARTHQUAKE_CONTOURS_PATH = joinpath(EARTHQUAKE_DIR, "earthquake_contours.geojson")
const BOUNDARY_DIR = "data/boundaries"
const NSW_EVACUATION_PATH = joinpath(EVACUATION_DIR, "new_south_wales.geojson")
const VIC_EVACUATION_PATH = joinpath(EVACUATION_DIR, "victoria.geojson")
const SA_EVACUATION_PATH = joinpath(EVACUATION_DIR, "south_australia.geojson")

# Results directories
const OUTPUT_DIR = "results"
const ANALYSIS_DIR = "results"
const PLOT_DIR = joinpath(ANALYSIS_DIR, "plots")
const PLOT_PAPER_DIR = joinpath(ANALYSIS_DIR, "paper")


# ============================================================
# BUSHFIRE CATEGORY MAPPING
# ============================================================

# Bushfire category mapping
# If a bushfire category is not in this mapping, it will be treated as "excluded" (i.e. no exposure)
# Add additional mappings as needed for other datasets or categories
const BUSHFIRE_CATEGORY_TO_EXPOSURE = Dict(
    # NSW numeric categories
    1 => "high",
    2 => "medium",
    3 => "low",

    # South Australia bf_code categories
    "high" => "high",
    "medium" => "medium",
    "general" => "low",
    "excluded" => nothing,
)

const EXPOSURE_PRIORITY = Dict("low" => 1, "medium" => 2, "high" => 3)

normalise_bushfire_category(::Missing) = nothing
normalise_bushfire_category(category::Number) = get(BUSHFIRE_CATEGORY_TO_EXPOSURE, Int(category), nothing)
normalise_bushfire_category(category::AbstractString) = get(BUSHFIRE_CATEGORY_TO_EXPOSURE, lowercase(strip(category)), nothing)

# Fire probabilities by exposure classification
const FIRE_PROBABILITIES = Dict(
    "high" => 0.8,
    "medium" => 0.5,
    "low" => 0.2,
    "none" => 0.1,
)

# ============================================================
# STATE AND HAZARD SETTINGS
# ============================================================

# Define the states considered in the analysis
const STATES = ("NSW", "VIC", "SA")

# Define the hazards considered in the analysis
const HAZARDS = ("fire", "flood", "earthquake")

# Set which hazards are relevant for each state.
# UPdate this mapping if new hazards are added or if the analysis is extended to other states.
const STATE_HAZARDS = Dict(
    "NSW" => ("fire", "flood", "earthquake"),
    "VIC" => ("flood", "earthquake"),
    "SA" => ("fire", "earthquake")
)

# ============================================================
# EARTHQUAKE SETTINGS
# ============================================================

# Define the earthquake model parameters based on peak-ground-acceleration (PGA) values and their corresponding probabilities of failure and impact.
const EARTHQUAKE_CONFIG = (
    max_pga_g=0.5,
    α=2.0,
    β=1.0,
    max_failure_probability=0.5,
    max_impact_probability=1.0,
)

# ============================================================
# FLOOD SETTINGS
# ============================================================

# Define the flood model parameters based on distance from flood zones and their corresponding probabilities of failure and impact.
const FLOOD_CONFIG = (
    max_distance_m=2000.0,
    α=2.0,
    β=1.0,
    max_failure_probability=0.5,
    max_impact_probability=1.0,
)

# ============================================================
# TELECOMMUNICATIONS SETTINGS
# ============================================================

# Define the telecommunications scenarios considered in the analysis and their order for plotting and reporting.
const SCENARIO_ORDER = lowercase.([
    "4G urban",
    "4G suburban",
    "4G rural",
    "5G dense urban",
    "5G urban",
    "5G suburban",
])