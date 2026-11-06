using ArchGDAL
using Printf
using Statistics

# ============================================================
# CONFIGURATION
# ============================================================

const STATE = "TAS"

const INPUT_DIR = "$(FLOOD_DIR)/TAS_depth"
const BOUNDARY_PATH = "$(BOUNDARY_DIR)/tasmania_boundary.geojson"

const FLOOD_DEPTH_THRESHOLD = 1  # metres; 1 cm

const OUTPUT_DIR = joinpath("data", "flood_history")
const PROJECTED_DIR = joinpath(RAW_DIR, "flood_history", "projected")
const TEMP_DIR = joinpath(RAW_DIR, "flood_history", "temporary")

const PROJECTED_BOUNDARY = joinpath(PROJECTED_DIR, "tasmania_boundary_3577.gpkg")
const MASK_TIF = joinpath(TEMP_DIR, "tasmania_mask.tif")
const OUTPUT_TIF = joinpath(OUTPUT_DIR, "tas_flood_event_frequency_250m.tif")

const NODATA = -9999.0

# ============================================================
# CHECK GDAL INSTALLATION
# ============================================================

function check_command(command)
    success(pipeline(`$command --version`, stdout=devnull, stderr=devnull)) || error("$command is not installed or not available in PATH.")
end

for command in ["ogr2ogr", "ogrinfo", "gdalinfo", "gdal_rasterize", "gdalwarp", "gdal_translate"]
    check_command(command)
end

# ============================================================
# FIND FLOOD DEPTH RASTERS
# ============================================================

println("\n============================================")
println("FLOOD EVENT FREQUENCY ANALYSIS: TASMANIA")
println("============================================")

event_files = filter(f -> occursin(r"_Depth_COG\.tif$"i, basename(f)), readdir(INPUT_DIR; join=true))
sort!(event_files)

isempty(event_files) && error("No flood depth GeoTIFF files found in $INPUT_DIR")

println("\nFlood events found: ", length(event_files))

for file in event_files
    println("  ", basename(file))
end

# ============================================================
# PROJECT TASMANIA BOUNDARY
# ============================================================

println("\nProjecting Tasmania boundary...")

run(`ogr2ogr -f GPKG -t_srs $TARGET_CRS $PROJECTED_BOUNDARY $BOUNDARY_PATH -overwrite`)

# ============================================================
# OBTAIN PROJECTED STATE EXTENT
# ============================================================

function get_extent(path)
    output = read(`ogrinfo -al -so $path`, String)
    result = match(r"Extent: \(([-\d.]+), ([-\d.]+)\) - \(([-\d.]+), ([-\d.]+)\)", output)
    isnothing(result) && error("Could not determine extent for $path")
    return parse.(Float64, result.captures)
end

xmin, ymin, xmax, ymax = get_extent(PROJECTED_BOUNDARY)

# Align extent to the 250 m raster grid
xmin = floor(xmin / CELL_SIZE) * CELL_SIZE
ymin = floor(ymin / CELL_SIZE) * CELL_SIZE
xmax = ceil(xmax / CELL_SIZE) * CELL_SIZE
ymax = ceil(ymax / CELL_SIZE) * CELL_SIZE

# GDAL expects dimensions in columns × rows
ncols = Int(round((xmax - xmin) / CELL_SIZE))
nrows = Int(round((ymax - ymin) / CELL_SIZE))

println("\nRaster extent:")
println("X: ", xmin, " to ", xmax)
println("Y: ", ymin, " to ", ymax)
println("GDAL dimensions: ", ncols, " columns × ", nrows, " rows")

# ============================================================
# CREATE TASMANIA MASK
# ============================================================

println("\nCreating Tasmania mask...")

run(`gdal_rasterize -q -burn 1 -init 0 -ot Byte -of GTiff -tr $CELL_SIZE $CELL_SIZE -te $xmin $ymin $xmax $ymax -co COMPRESS=LZW $PROJECTED_BOUNDARY $MASK_TIF`)

mask = ArchGDAL.read(MASK_TIF) do dataset
    ArchGDAL.read(ArchGDAL.getband(dataset, 1))
end

println("Mask array dimensions: ", size(mask))
println("Valid state cells: ", count(mask .> 0))

# ============================================================
# INITIALISE FLOOD EVENT COUNTS
# ============================================================

# Always use the dimensions returned by ArchGDAL for Julia arrays.

array_size = size(mask)

# Number of events in which each cell was flooded.
flood_count = zeros(UInt16, array_size)

# Number of events with valid data for each cell.
valid_event_count = zeros(UInt16, array_size)

# ============================================================
# PROCESS EACH FLOOD EVENT
# ============================================================

println("\nProcessing flood events...")

for (event_number, input_file) in enumerate(event_files)

    event_name = replace(basename(input_file), r"_Depth_COG\.tif$"i => "")

    println("\n[$event_number/$(length(event_files))] Processing: ", event_name)

    event_tif = joinpath(TEMP_DIR, "$(event_name)_250m.tif")

    # Reproject and resample the event onto the common 250 m grid.
    # Maximum resampling retains inundation if any part of a
    # 250 m cell contains floodwater.
    run(`gdalwarp -q -overwrite -t_srs $TARGET_CRS -te $xmin $ymin $xmax $ymax -ts $ncols $nrows -r max -srcnodata $NODATA -dstnodata $NODATA -ot Float32 -co COMPRESS=LZW $input_file $event_tif`)

    # Read aligned event raster.
    event_data = ArchGDAL.read(event_tif) do dataset
        ArchGDAL.read(ArchGDAL.getband(dataset, 1))
    end

    # Check array dimensions before processing.
    println("  Mask dimensions: ", size(mask))
    println("  Event dimensions: ", size(event_data))

    size(event_data) == array_size || error("Raster dimension mismatch for $event_name: event=$(size(event_data)), expected=$array_size")

    # Determine cells with valid flood model data.
    valid_cells = isfinite.(event_data) .& (event_data .> NODATA)

    # Determine which cells were inundated during this event.
    flooded_cells = valid_cells .& (event_data .> FLOOD_DEPTH_THRESHOLD)

    # Restrict calculations to Tasmania and valid event coverage.
    valid_cells .&= mask .> 0
    flooded_cells .&= mask .> 0

    # Update counts.
    valid_event_count .+= UInt16.(valid_cells)
    flood_count .+= UInt16.(flooded_cells)

    println("  Valid cells: ", count(valid_cells))
    println("  Flooded cells: ", count(flooded_cells))

    # Remove temporary raster.
    rm(event_tif; force=true)
end

# ============================================================
# CALCULATE FLOOD EVENT FREQUENCY
# ============================================================

println("\nCalculating flood event frequencies...")

frequency = fill(Float32(NODATA), array_size)

for i in eachindex(frequency)
    if mask[i] > 0 && valid_event_count[i] > 0
        frequency[i] = Float32(flood_count[i] / valid_event_count[i])
    end
end

# ============================================================
# CREATE OUTPUT GEOTIFF
# ============================================================

println("\nCreating output GeoTIFF...")

run(`gdal_translate -q -ot Float32 -a_nodata $NODATA -co COMPRESS=DEFLATE -co PREDICTOR=3 -co TILED=YES -co BIGTIFF=IF_SAFER $MASK_TIF $OUTPUT_TIF`)

ArchGDAL.read(OUTPUT_TIF, flags=ArchGDAL.OF_UPDATE) do dataset
    band = ArchGDAL.getband(dataset, 1)
    ArchGDAL.write!(band, frequency)
    ArchGDAL.setnodatavalue!(band, NODATA)
end

# ============================================================
# CALCULATE STATISTICS
# ============================================================

valid = filter(x -> isfinite(x) && 0 <= x <= 1, vec(frequency))

isempty(valid) && error("No valid flood frequency cells were produced.")

flooded_cells = count(>(0), valid)
never_flooded_cells = count(==(0), valid)

percentage_nonzero = 100 * flooded_cells / length(valid)

# ============================================================
# SUMMARY
# ============================================================

println("\n============================================")
println("FLOOD EVENT FREQUENCY RASTER COMPLETE")
println("============================================")

println("State: Tasmania")
println("Output: ", OUTPUT_TIF)
println("CRS: ", TARGET_CRS)
println("Cell size: ", CELL_SIZE, " m")
println("Raster dimensions: ", ncols, " × ", nrows)
println("Flood events processed: ", length(event_files))
println("Depth threshold: ", FLOOD_DEPTH_THRESHOLD, " m")
println("--------------------------------------------")
println("FREQUENCY STATISTICS")
println("--------------------------------------------")
println("Valid cells: ", length(valid))
println("Minimum frequency: ", minimum(valid))
println("Maximum frequency: ", maximum(valid))
println("Mean frequency: ", mean(valid))
println("Median frequency: ", median(valid))
println("Standard deviation: ", std(valid))
println("Cells with at least one flood: ", flooded_cells)
println("Cells with no recorded flooding: ", never_flooded_cells)
println("Percentage with flooding: ", percentage_nonzero, "%")
println("--------------------------------------------")
println("EVENT COVERAGE")
println("--------------------------------------------")
println("Minimum valid events per cell: ", minimum(valid_event_count[mask .> 0]))
println("Maximum valid events per cell: ", maximum(valid_event_count[mask .> 0]))
println("============================================")