# ============================================================
# PATHS AND SETTINGS
# ============================================================

# Data directories
const TELCO_SITES_PATH = "data/telecommunications_datasets/cell_tower_dataset.json"
const EVACUATION_DIR = "data/evacuation_datasets"
const BUSHFIRE_DIR = "data/fire_history"
const FLOOD_VIC_PATH = "data/flood_history"
const BOUNDARY_DIR = "data/boundaries"

# Results directories
const OUTPUT_DIR = "results"
const ANALYSIS_DIR = "results"
const FIGURES_DIR = joinpath("figures")
const PLOT_DIR = joinpath(ANALYSIS_DIR, "plots")
const PLOT_PAPER_DIR = joinpath(ANALYSIS_DIR, "paper")

mkpath(OUTPUT_DIR)
mkpath(ANALYSIS_DIR)
mkpath(FIGURES_DIR)
mkpath(PLOT_DIR)
mkpath(PLOT_PAPER_DIR)

# ============================================================
# STATE SETTINGS
# ============================================================

# Load evacuation paths for each state from the evacuation datasets directory
const EVACUATION_PATHS = Dict(
    :NSW => joinpath(EVACUATION_DIR, "new_south_wales.geojson"),
    :VIC => joinpath(EVACUATION_DIR, "victoria.geojson"),
    :SA  => joinpath(EVACUATION_DIR, "south_australia.geojson"),
    :TAS => joinpath(EVACUATION_DIR, "tasmania.geojson")
)

# Define the states considered in the analysis
const STATES = ("NSW", "VIC", "SA", "TAS")

# Define the mapping of state names to their codes for consistent referencing
const STATE_CODES = Dict(
    "NEW SOUTH WALES" => "NSW",
    "VICTORIA" => "VIC",
    "SOUTH AUSTRALIA" => "SA",
    "TASMANIA" => "TAS"
)

_state_code(value) = (name = uppercase(strip(string(value))); get(STATE_CODES, name, name))

const BOUNDARY_FILENAMES = Dict(
    :NSW => "new_south_wales_boundary.geojson",
    :SA  => "south_australia_boundary.geojson",
    :VIC => "victoria_boundary.geojson",
    :TAS => "tasmania_boundary.geojson"
)

function load_state_boundary(state::Symbol)
    filename = get(BOUNDARY_FILENAMES, state) do
        error("Unsupported state: $state")
    end

    path = joinpath(BOUNDARY_DIR, filename)
    isfile(path) || error("Boundary file not found: $path")
    return _json(path)
end

# ============================================================
# HAZARD SETTINGS
# ============================================================

# Define the hazards considered in the analysis
const HAZARDS = ("fire", "flood")

# Set which hazards are relevant for each state.
const STATE_HAZARDS = Dict(
    "NSW" => ("fire",),
    "VIC" => ("fire",),
    "SA"  => ("fire",),
    "TAS" => ("fire", "flood"),
)

# ============================================================
# ANALYSIS CONFIGURATION
# ============================================================

const ANALYSIS_PERIODS = [1, 5, 10]

# ============================================================
# CONDITIONAL INFRASTRUCTURE IMPACT PROBABILITIES
# ============================================================

const ASSET_FAILURE_PROBABILITIES = Dict(
    "fire" => 0.75, 
    "flood" => 0.75,
)

const FACILITY_FAILURE_PROBABILITIES = Dict(
    "fire" => 0.75,
    "flood" => 0.75,
)

# ============================================================
# TELECOMMUNICATIONS SETTINGS
# ============================================================

# Minimum coverage probability for candidate assets
const MIN_COVERAGE_PROBABILITY = 0.075

coverage_scenario(distance, exponent, sigma) = (
    nominal_distance_m=Float64(distance),
    pathloss_exponent=Float64(exponent),
    shadow_fading_std_db=Float64(sigma),
)

# Define telecommunications coverage scenarios
const COVERAGE_SCENARIOS = Dict(
    # 4G (1.8 GHz)
    "4G Urban"    => coverage_scenario(680, 3.5, 8),
    "4G Suburban" => coverage_scenario(2780, 3.3, 7),
    "4G Rural"    => coverage_scenario(7130, 3.0, 5),

    # 5G
    "5G Dense Urban" => coverage_scenario(368, 3.9, 8),
    "5G Urban"       => coverage_scenario(610, 3.5, 8),
    "5G Suburban"    => coverage_scenario(1230, 3.0, 7),
)

# Define the telecommunications scenarios considered in the analysis and their order for plotting and reporting.
const SCENARIO_ORDER = titlecase.([
    "4G Urban",
    "4G Suburban",
    "4G Rural",
    "5G Dense Urban",
    "5G Urban",
    "5G Suburban",
])