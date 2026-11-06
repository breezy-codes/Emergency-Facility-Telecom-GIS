using GeoDataFrames, DataFrames, ArchGDAL
using Printf
using Statistics

# ============================================================
# CONFIGURATION
# ============================================================

const FIRE_STATES = Dict(
    "NSW" => (
        name="New South Wales",
        fire_path="NSW/NPWSFireHistory.shp",
        boundary_path="new_south_wales_boundary.geojson",
        fire_type="Wildfire",
        year_function=row -> parse(Int, first(row.Label, 4)),
        fire_filter="Label LIKE '%Wildfire'",
        season_filter=year -> "Label = '$(@sprintf("%d-%02d Wildfire", year, mod(year + 1, 100)))"
    ),
    "VIC" => (
        name="Victoria",
        fire_path="VIC/FIRE_HISTORY.shp",
        boundary_path="victoria_boundary.geojson",
        fire_type="Bushfire",
        year_function=row -> Int(row.SEASON),
        fire_filter="FIRETYPE = 'Bushfire'",
        season_filter=year -> "SEASON = $year AND FIRETYPE = 'Bushfire'"
    ),
    "SA" => (
        name="South Australia",
        fire_path="SA/FIREMGT_FireHistory_GDA2020.shp",
        boundary_path="south_australia_boundary.geojson",
        fire_type="Bushfire",
        year_function=row -> Int(row.FIREYEAR),
        fire_filter="INCIDENTTY = 'Bushfire'",
        season_filter=year -> "FIREYEAR = $year AND INCIDENTTY = 'Bushfire'"
    ),
    "TAS" => (
        name="Tasmania",
        fire_path="TAS/list_fire_history_statewide.shp",
        boundary_path="tasmania_boundary.geojson",
        fire_type="Bushfire",
        year_function=row -> Int(floor(row.IGN_SEASON / 10000)),
        fire_filter="FIRE_TYPE = 'Bushfire'",
        season_filter=year -> "IGN_SEASON = $(year * 10000 + year + 1) AND FIRE_TYPE = 'Bushfire'"
    )
)

mkpath(PROJECTED_DIR)
mkpath(TEMP_DIR)

# ============================================================
# CHECK GDAL INSTALLATION
# ============================================================

function check_command(command)
    success(pipeline(`$command --version`, stdout=devnull, stderr=devnull)) || error("$command is not installed or not available in PATH.")
end

for command in ["ogr2ogr", "ogrinfo", "gdalinfo", "gdal_rasterize", "gdal_translate"]
    check_command(command)
end

# ============================================================
# IMPORT AND FILTER FIRE RECORDS
# ============================================================

function build_fire_rastors(state)

    state = uppercase(String(state))
    # Validate state
    state in STATES || error("Invalid state: $state. Choose from $STATES")

    state_config = FIRE_STATES[state]

    FIRE_PATH = joinpath(FIRE_RAW_DIR, state_config.fire_path)
    BOUNDARY_PATH = joinpath(BOUNDARY_DIR, state_config.boundary_path)

    PROJECTED_DIR = joinpath(RAW_DIR, "fire_history", "projected")
    TEMP_DIR = joinpath(RAW_DIR, "fire_history", "temporary")

    PROJECTED_FIRES = joinpath(PROJECTED_DIR, "$(lowercase(state))_wildfires_3577.gpkg")
    PROJECTED_BOUNDARY = joinpath(PROJECTED_DIR, "$(lowercase(state))_boundary_3577.gpkg")

    MASK_TIF = joinpath(TEMP_DIR, "$(lowercase(state))_mask.tif")
    OUTPUT_TIF = joinpath(BUSHFIRE_DIR, "$(lowercase(state))_annual_fire_probability_$(Int(CELL_SIZE))m.tif")


    println("\n============================================")
    println("FIRE PROBABILITY ANALYSIS: ", state)
    println("============================================")

    println("\nReading fire history...")

    fires = GeoDataFrames.read(FIRE_PATH)

    # NSW-specific filtering and season extraction
    if state == "NSW"

        wildfires = filter(row -> !ismissing(row.Label) && occursin("Wildfire", row.Label), fires)
        wildfires.year = parse.(Int, first.(wildfires.Label, 4))

        # VIC-specific filtering and season extraction
    elseif state == "VIC"

        wildfires = filter(row -> !ismissing(row.FIRETYPE) && row.FIRETYPE == "Bushfire", fires)
        wildfires.year = Int.(wildfires.SEASON)

        # SA-specific filtering and season extraction
    elseif state == "SA"

        wildfires = filter(row -> !ismissing(row.INCIDENTTY) && row.INCIDENTTY == "Bushfire", fires)
        wildfires.year = Int.(wildfires.FIREYEAR)

    elseif state == "TAS"

        wildfires = filter(row -> !ismissing(row.FIRE_TYPE) && row.FIRE_TYPE == "Bushfire", fires)
        wildfires.year = Int.(floor.(wildfires.IGN_SEASON ./ 10000))
    end

    # Apply observation period
    wildfires = filter(row -> OBSERVATION_START <= row.year <= OBSERVATION_END, wildfires)

    recorded_seasons = Set(wildfires.year)
    missing_seasons = setdiff(OBSERVATION_START:OBSERVATION_END, recorded_seasons)

    println("Fire records: ", nrow(wildfires))
    println("Distinct recorded seasons: ", length(recorded_seasons))
    println("Observation period: ", OBSERVATION_START, "-", OBSERVATION_END)
    println("Probability denominator: ", OBSERVATION_SEASONS)
    println("Missing recorded seasons: ", collect(missing_seasons))

    # ============================================================
    # PROJECT SOURCE DATASETS INTO EPSG:3577
    # ============================================================

    println("\nProjecting fire polygons...")

    run(`ogr2ogr -f GPKG -t_srs $TARGET_CRS $PROJECTED_FIRES $FIRE_PATH -where $(state_config.fire_filter) -overwrite`)

    println("Projecting state boundary...")

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

    # Align extent to the raster grid
    xmin = floor(xmin / CELL_SIZE) * CELL_SIZE
    ymin = floor(ymin / CELL_SIZE) * CELL_SIZE
    xmax = ceil(xmax / CELL_SIZE) * CELL_SIZE
    ymax = ceil(ymax / CELL_SIZE) * CELL_SIZE

    println("\nRaster extent:")
    println("X: ", xmin, " to ", xmax)
    println("Y: ", ymin, " to ", ymax)

    # ============================================================
    # CREATE STATE MASK RASTER
    # ============================================================

    println("\nCreating ", state, " mask...")

    run(`gdal_rasterize -q -burn 1 -init 0 -ot Byte -of GTiff -tr $CELL_SIZE $CELL_SIZE -te $xmin $ymin $xmax $ymax -co COMPRESS=LZW $PROJECTED_BOUNDARY $MASK_TIF`)

    # ============================================================
    # READ MASK AND INITIALISE ACCUMULATED ARRAY
    # ============================================================

    println("Reading state mask...")

    mask = ArchGDAL.read(MASK_TIF) do dataset
        ArchGDAL.read(ArchGDAL.getband(dataset, 1))
    end

    nrows, ncols = size(mask)

    println("Raster dimensions: ", ncols, " columns × ", nrows, " rows")
    println("Total raster cells: ", nrows * ncols)

    # Each cell stores the number of seasons in which it burned.
    season_count = zeros(UInt16, nrows, ncols)

    # ============================================================
    # RASTERISE EACH FIRE SEASON
    # ============================================================

    println("\nProcessing fire seasons...")

    for year in OBSERVATION_START:OBSERVATION_END

        # Construct state-specific filter
        if state == "NSW"
            season_label = @sprintf("%d-%02d Wildfire", year, mod(year + 1, 100))
            season_filter = "Label = '$season_label'"
        elseif state == "VIC"
            season_label = string(year)
            season_filter = "SEASON = $year AND FIRETYPE = 'Bushfire'"
        elseif state == "SA"
            season_label = string(year)
            season_filter = "FIREYEAR = $year AND INCIDENTTY = 'Bushfire'"
        elseif state == "TAS"
            season_label = "$(year)-$(year + 1)"
            season_filter = "IGN_SEASON = $(year * 10000 + year + 1) AND FIRE_TYPE = 'Bushfire'"
        end


        # Empty seasons contribute zero to the probability calculation.
        if !(year in recorded_seasons)
            continue
        end

        year % 10 == 0 && println("Processing season: ", season_label)

        season_tif = joinpath(TEMP_DIR, "season_$year.tif")

        # Rasterise all fire polygons from this season.
        # Multiple polygons in the same cell still produce a value of 1.
        run(`gdal_rasterize -q -burn 1 -init 0 -ot Byte -of GTiff -tr $CELL_SIZE $CELL_SIZE -te $xmin $ymin $xmax $ymax -where $season_filter -co COMPRESS=LZW $PROJECTED_FIRES $season_tif`)

        # Read seasonal raster
        season_data = ArchGDAL.read(season_tif) do dataset
            ArchGDAL.read(ArchGDAL.getband(dataset, 1))
        end

        # Count each cell at most once per season
        season_count .+= UInt16.(season_data .> 0)

        # Remove temporary raster
        rm(season_tif; force=true)
    end

    # ============================================================
    # CALCULATE ANNUAL PROBABILITY
    # ============================================================

    println("\nCalculating annual probabilities...")

    probability = fill(Float32(-9999), nrows, ncols)

    for i in eachindex(probability)
        if mask[i] > 0
            probability[i] = Float32(season_count[i] / OBSERVATION_SEASONS)
        end
    end

    # ============================================================
    # CREATE OUTPUT GEOTIFF
    # ============================================================

    println("Creating output GeoTIFF...")

    run(`gdal_translate -q -ot Float32 -a_nodata -9999 -co COMPRESS=DEFLATE -co PREDICTOR=3 -co TILED=YES -co BIGTIFF=IF_SAFER $MASK_TIF $OUTPUT_TIF`)

    # Write probability values into output raster
    ArchGDAL.read(OUTPUT_TIF, flags=ArchGDAL.OF_UPDATE) do dataset
        band = ArchGDAL.getband(dataset, 1)
        ArchGDAL.write!(band, probability)
        ArchGDAL.setnodatavalue!(band, -9999.0)
    end

    # ============================================================
    # CALCULATE PROBABILITY STATISTICS
    # ============================================================

    valid_cells = count(mask .> 0)
    burned_cells = count((mask .> 0) .& (season_count .> 0))

    valid = filter(x -> isfinite(x) && 0 <= x <= 1, vec(probability))

    zero_cells = count(==(0), valid)
    nonzero_cells = count(>(0), valid)
    percentage_nonzero = 100 * nonzero_cells / length(valid)

    min_probability = minimum(valid)
    max_probability = maximum(valid)
    mean_probability = mean(valid)
    median_probability = median(valid)
    std_probability = std(valid)

    # ============================================================
    # SUMMARY
    # ============================================================

    println("\n============================================")
    println("FIRE EVENT FREQUENCY RASTER COMPLETE")
    println("============================================")

    println("State: ", state)
    println("Output: ", OUTPUT_TIF)
    println("CRS: ", TARGET_CRS)
    println("Cell size: ", CELL_SIZE, " m")
    println("Raster dimensions: ", ncols, " × ", nrows)
    println("Valid state cells: ", valid_cells)
    println("Cells with recorded fire: ", burned_cells)
    println("Observation period: ", OBSERVATION_START, "-", OBSERVATION_END)
    println("Observation seasons: ", OBSERVATION_SEASONS)
    println("Missing recorded seasons: ", length(missing_seasons))
    println("--------------------------------------------")
    println("PROBABILITY STATISTICS")
    println("--------------------------------------------")
    println("Valid cells: ", length(valid))
    println("Minimum probability: ", min_probability)
    println("Maximum probability: ", max_probability)
    println("Mean probability: ", mean_probability)
    println("Median probability: ", median_probability)
    println("Standard deviation: ", std_probability)
    println("Zero probability cells: ", zero_cells)
    println("Non-zero probability cells: ", nonzero_cells)
    println("Percentage non-zero: ", percentage_nonzero, "%")
    println("--------------------------------------------")
end