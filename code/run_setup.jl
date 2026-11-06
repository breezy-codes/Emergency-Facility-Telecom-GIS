using GeoDataFrames
using Printf
using Statistics
using HTTP
using GeoJSON
using ArchGDAL
using DataFrames
using Downloads
using JSON3
using CSV
using Tables

cd(@__DIR__) do
    run(`bash data_preparation/download_data.sh`)
end

include("config.jl")
include("data_preparation/state_boundaries.jl")

include("data_preparation/fire_history_to_tif.jl")

build_fire_rastors("NSW")
build_fire_rastors("SA")
build_fire_rastors("TAS")

# If you don't download the Victoria fire history data, you can comment out the following line.
build_fire_rastors("VIC")

include("data_preparation/flood_history_to_tif.jl")