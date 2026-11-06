# ============================================================
# BUILD FACILITY-ASSET TABLES
# ============================================================

function _extract_hazard_probability_with_fallback(raster, longitude::Real, latitude::Real; max_distance_m::Real=100.0)
    max_distance_m >= 0 || throw(ArgumentError("Maximum fallback distance must be non-negative"))

    x, y = WGS84_TO_AU_ALBERS(Float64(longitude), Float64(latitude))
    gt = raster.geotransform
    values = raster.values
    nrows, ncols = size(values)

    (iszero(gt[3]) && iszero(gt[5])) || throw(ArgumentError("Rotated rasters are not supported by the fallback extraction"))

    # Calculate the raster cell containing the coordinate.
    col = floor(Int, (x - gt[1]) / gt[2]) + 1
    row = floor(Int, (y - gt[4]) / gt[6]) + 1

    # Check whether a cell contains a valid probability.
    is_valid(row, col) = checkbounds(Bool, values, row, col) && isfinite(values[row, col]) && (raster.nodata === nothing || !isequal(values[row, col], raster.nodata)) && 0.0 <= values[row, col] <= 1.0

    # Return the direct extraction when possible.
    if is_valid(row, col)
        return (probability=Float64(values[row, col]), used_fallback=false, distance_m=0.0)
    end

    # Search nearby cells for the nearest valid pixel.
    search_radius = ceil(Int, max_distance_m / min(abs(gt[2]), abs(gt[6]))) + 1
    best_distance = Inf
    best_probability = missing

    for candidate_row in max(1, row-search_radius):min(nrows, row+search_radius)
        for candidate_col in max(1, col-search_radius):min(ncols, col+search_radius)
            is_valid(candidate_row, candidate_col) || continue

            # Calculate the candidate pixel's geographic bounds.
            x1 = gt[1] + (candidate_col - 1) * gt[2]
            x2 = gt[1] + candidate_col * gt[2]
            y1 = gt[4] + (candidate_row - 1) * gt[6]
            y2 = gt[4] + candidate_row * gt[6]

            xmin, xmax = minmax(x1, x2)
            ymin, ymax = minmax(y1, y2)

            # Calculate distance from the facility to the pixel footprint.
            dx = max(xmin - x, 0.0, x - xmax)
            dy = max(ymin - y, 0.0, y - ymax)
            distance = hypot(dx, dy)

            if distance < best_distance
                best_distance = distance
                best_probability = Float64(values[candidate_row, candidate_col])
            end
        end
    end

    if best_distance <= max_distance_m
        return (probability=best_probability, used_fallback=true, distance_m=best_distance)
    end

    return (probability=missing, used_fallback=false, distance_m=missing)
end

"""
    add_hazard_probabilities!(df::DataFrame, rasters; state::AbstractString, longitude_col=:longitude, latitude_col=:latitude, fallback_distance_m::Real=100.0)

Add hazard probabilities to the given DataFrame `df` based on the provided `rasters` for each hazard. The function will extract the hazard probabilities for each row in the DataFrame using the specified longitude and latitude columns. If a raster cell at the specified coordinates contains a missing or invalid value, it will search nearby cells within `fallback_distance_m` for the nearest valid pixel.
"""
function add_hazard_probabilities!(df::DataFrame, rasters; state::AbstractString, longitude_col=:longitude, latitude_col=:latitude, fallback_distance_m::Real=100.0)
    state = uppercase(strip(state))
    haskey(STATE_HAZARDS, state) || throw(ArgumentError("No hazards configured for state '$state'"))

    required_columns = (longitude_col, latitude_col)
    missing_columns = filter(c -> !(c in propertynames(df)), required_columns)
    isempty(missing_columns) || throw(ArgumentError("Missing coordinate columns: $(collect(missing_columns))"))

    applicable_hazards = STATE_HAZARDS[state]

    for hazard in HAZARDS
        column = Symbol("$(hazard)_probability")

        if hazard in applicable_hazards
            haskey(rasters, hazard) || throw(ArgumentError("Missing $hazard raster for state $state"))

            raster = rasters[hazard]

            extractions = [
                ismissing(lon) || ismissing(lat) ?
                (probability=missing, used_fallback=false, distance_m=missing) :
                _extract_hazard_probability_with_fallback(raster, lon, lat; max_distance_m=fallback_distance_m)
                for (lon, lat) in zip(df[!, longitude_col], df[!, latitude_col])
            ]

            fallback_count = count(result -> result.used_fallback, extractions)
            zero_assigned_count = count(result -> ismissing(result.probability), extractions)

            df[!, column] = [ismissing(result.probability) ? 0.0 : result.probability for result in extractions]

            @info "Hazard probabilities extracted" state=state hazard=hazard total=nrow(df) valid=nrow(df) fallback=fallback_count zero_assigned=zero_assigned_count fallback_distance_m=fallback_distance_m
        else
            df[!, column] = fill(missing, nrow(df))
        end
    end

    return df
end