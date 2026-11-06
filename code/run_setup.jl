using GeoDataFrames
using Printf
using Statistics
using HTTP
using GeoJSON
using ArchGDAL
using DataFrames
using Downloads


cd(@__DIR__) do
    run(`bash data_preparation/download_data.sh`)
end

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const PYTHON = "python3"

function run_python(script)
    script_path = joinpath(PROJECT_ROOT, "code", "data_preparation", script)
    println("\nRunning $script...")
    run(`$PYTHON $script_path`)
end

run_python("collect_cell_towers.py")
run_python("sanitise_cell_towers.py")

include("config.jl")
include("data_preparation/state_boundaries.jl")

include("data_preparation/fire_history_to_tif.jl")

build_fire_rastors("NSW")
build_fire_rastors("SA")
build_fire_rastors("TAS")

# If you don't download the Victoria fire history data, you can comment out the following line.
build_fire_rastors("VIC")

include("data_preparation/flood_history_to_tif.jl")