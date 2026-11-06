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


"""
    analysis = analyse_multi_hazard(facilities::AbstractDataFrame, sites::AbstractDataFrame; asset_conditional_failure_probabilities::AbstractDict, facility_conditional_failure_probabilities::AbstractDict, config::ModelConfig=ModelConfig(), analysis_periods=ANALYSIS_PERIODS)

Run a multi-hazard analysis for the given facilities and telecommunications sites. The function calculates the risk of failure for each facility based on its associated assets, hazard exposures, and a telecommunications coverage scenario. It returns a DataFrame containing the analysis results for each facility across the specified analysis periods.
"""
function analyse_multi_hazard(facilities::AbstractDataFrame, sites::AbstractDataFrame; asset_conditional_failure_probabilities::AbstractDict, facility_conditional_failure_probabilities::AbstractDict, config::ModelConfig=ModelConfig(), analysis_periods=ANALYSIS_PERIODS)

    # Validate input columns
    required_facility_columns = (:facility_id, :state, :name, :longitude, :latitude, :fire_probability, :flood_probability)
    required_site_columns = (:asset_id, :longitude, :latitude, :fire_probability, :flood_probability)

    missing_facility = filter(c -> !(c in propertynames(facilities)), required_facility_columns)
    missing_site = filter(c -> !(c in propertynames(sites)), required_site_columns)

    isempty(missing_facility) || throw(ArgumentError("Missing facility columns: $(collect(missing_facility))"))
    isempty(missing_site) || throw(ArgumentError("Missing telecommunications site columns: $(collect(missing_site))"))

    available_states = unique(uppercase.(strip.(string.(facilities.state))))

    for state in available_states
        haskey(STATE_HAZARDS, state) || throw(ArgumentError("No hazards configured for state '$state'"))
    end

    all_hazards = unique(h for state in available_states for h in STATE_HAZARDS[state])
    all(h -> h in HAZARDS, all_hazards) || throw(ArgumentError("STATE_HAZARDS contains a hazard not defined in HAZARDS"))

    # Validate conditional failure probabilities
    for hazard in all_hazards
        haskey(asset_conditional_failure_probabilities, hazard) || throw(ArgumentError("Missing conditional asset failure probability for '$hazard'"))
        haskey(facility_conditional_failure_probabilities, hazard) || throw(ArgumentError("Missing conditional facility failure probability for '$hazard'"))

        _validate_hazard_probability(asset_conditional_failure_probabilities[hazard], hazard, "Conditional asset failure probability")
        _validate_hazard_probability(facility_conditional_failure_probabilities[hazard], hazard, "Conditional facility failure probability")
    end

    # Define spatial hazard probability columns
    hazard_probability_columns = Dict(h => Symbol("$(h)_probability") for h in all_hazards)

    # Validate spatial hazard probabilities for applicable states
    for state in available_states
        state_hazards = STATE_HAZARDS[state]

        state_facilities = filter(row -> uppercase(strip(string(row.state))) == state, facilities)
        state_sites = filter(row -> uppercase(strip(string(row.state))) == state, sites)

        for hazard in state_hazards
            column = hazard_probability_columns[hazard]

            for (name, df) in (("facilities", state_facilities), ("sites", state_sites))
                column in propertynames(df) || throw(ArgumentError("Missing $column column in $name DataFrame for $state"))

                missing_count = count(ismissing, df[!, column])
                missing_count == 0 || throw(ArgumentError("$missing_count missing $hazard probabilities in $name DataFrame for $state"))

                all(p -> 0 <= p <= 1, df[!, column]) || throw(ArgumentError("Invalid $hazard probabilities in $name DataFrame for $state"))
            end
        end
    end

    # Prepare coverage scenarios
    scenarios = [
        (name, CoverageScenario(name, scenario.nominal_distance_m, scenario.pathloss_exponent, scenario.shadow_fading_std_db))
        for (name, scenario) in COVERAGE_SCENARIOS
    ]

    thresholds = [_coverage_distance_threshold(scenario, config) for (_, scenario) in scenarios]

    facility_xy = [_project_xy((r.longitude, r.latitude)) for r in eachrow(facilities)]
    site_xy = [_project_xy((r.longitude, r.latitude)) for r in eachrow(sites)]

    nearby_by_facility = [Tuple{Int,Float64}[] for _ in eachindex(facility_xy)]
    nearest_distance_by_facility = fill(Inf, length(facility_xy))

    for (fi, (fx, fy)) in enumerate(facility_xy), (si, (sx, sy)) in enumerate(site_xy)
        distance = hypot(fx - sx, fy - sy)
        nearest_distance_by_facility[fi] = min(nearest_distance_by_facility[fi], distance)
        distance <= maximum(thresholds) && push!(nearby_by_facility[fi], (si, distance))
    end

    # Initialise output collections
    results = NamedTuple[]
    candidate_asset_rows = NamedTuple[]
    facility_probability_rows = NamedTuple[]
    telco_failure_rows = NamedTuple[]

    # Calculate failure probabilities for all telecommunications assets, independently of facility coverage.
    for site in eachrow(sites)
        state = uppercase(strip(string(site.state)))

        for hazard in STATE_HAZARDS[state]
            column = hazard_probability_columns[hazard]
            occurrence_probability = site[column]
            conditional_failure_probability = asset_conditional_failure_probabilities[hazard]

            for N in analysis_periods
                failure_probability = hazard_failure_probability(occurrence_probability, conditional_failure_probability, N)

                push!(telco_failure_rows, (
                    asset_id=site.asset_id,
                    state=state,
                    longitude=site.longitude,
                    latitude=site.latitude,
                    hazard=hazard,
                    analysis_period_years=N,
                    annual_occurrence_probability=occurrence_probability,
                    conditional_failure_probability=conditional_failure_probability,
                    failure_probability=failure_probability
                ))
            end
        end
    end

    # Run analysis across scenarios and facilities
    for ((scenario_name, scenario), threshold) in zip(scenarios, thresholds)

        for (fi, facility) in enumerate(eachrow(facilities))

            state = uppercase(strip(string(facility.state)))
            hazard_names = collect(STATE_HAZARDS[state])

            facility_hazard_probabilities = Dict(
                h => facility[hazard_probability_columns[h]]
                for h in hazard_names
            )

            asset_probability_columns = Dict(
                h => hazard_probability_columns[h]
                for h in hazard_names
            )

            # Build nearby facility-asset table
            nearby = NamedTuple[]

            for (si, distance) in nearby_by_facility[fi]
                distance <= threshold || continue

                site = sites[si, :]

                probability_data = (;
                    (column => site[column] for column in values(asset_probability_columns))...
                )

                push!(nearby, merge(
                    (
                        facility_id=facility.facility_id,
                        asset_id=site.asset_id,
                        distance=distance,
                    ),
                    probability_data
                ))
            end

            assets = isempty(nearby) ?
                     DataFrame(
                facility_id=eltype(facilities.facility_id)[],
                asset_id=eltype(sites.asset_id)[],
                distance=Float64[]
            ) : DataFrame(nearby)

            for column in values(asset_probability_columns)
                column in propertynames(assets) || (assets[!, column] = eltype(sites[!, column])[])
            end

            # Identify candidate assets
            candidates = get_candidate_assets(assets, scenario; config=config)

            # Store annual spatial hazard occurrence probabilities
            push!(facility_probability_rows, merge(
                (
                    facility_id=facility.facility_id,
                    state=state,
                    facility_name=String(facility.name),
                    scenario=scenario_name,
                    hazards=join(hazard_names, ";"),
                ),
                (;
                    (column => facility[column] for column in values(asset_probability_columns))...
                )
            ))

            # Store candidate asset information
            for row in eachrow(candidates)
                probability_data = (;
                    (column => row[column] for column in values(asset_probability_columns))...
                )

                push!(candidate_asset_rows, merge(
                    (
                        facility_id=facility.facility_id,
                        state=state,
                        asset_id=row.asset_id,
                        distance=row.distance,
                        coverage_probability=row.coverage_probability,
                        scenario=scenario_name,
                        hazards=join(hazard_names, ";"),
                    ),
                    probability_data
                ))
            end

            # Evaluate each analysis period
            for N in analysis_periods

                result = analyse_facility(
                    facility.facility_id,
                    assets,
                    asset_probability_columns,
                    facility_hazard_probabilities,
                    scenario;
                    config=config,
                    analysis_period_years=N,
                    asset_conditional_failure_probabilities=asset_conditional_failure_probabilities,
                    facility_conditional_failure_probabilities=facility_conditional_failure_probabilities,
                )

                nearest_distance = nearest_distance_by_facility[fi]

                push!(results, (
                    facility_id=result.facility_id,
                    state=state,
                    facility_name=String(facility.name),
                    scenario=result.scenario,
                    analysis_period_years=N,
                    hazards=join(hazard_names, ";"),
                    fire_occurrence_probability=ismissing(get(facility_hazard_probabilities, "fire", missing)) ? missing : 1.0 - (1.0 - facility_hazard_probabilities["fire"])^N,
                    flood_occurrence_probability=ismissing(get(facility_hazard_probabilities, "flood", missing)) ? missing : 1.0 - (1.0 - facility_hazard_probabilities["flood"])^N,
                    num_candidate_assets=result.num_candidate_assets,
                    nearest_asset_distance_m=nearest_distance,
                    within_range=nearest_distance <= threshold,
                    normal_coverage_probability=result.normal_coverage_probability,
                    no_coverage_probability=result.no_coverage_probability,
                    fire_continuity_probability=result.fire_continuity_probability,
                    flood_continuity_probability=result.flood_continuity_probability,
                    fire_cutoff_probability=result.fire_cutoff_probability,
                    flood_cutoff_probability=result.flood_cutoff_probability,
                    fire_facility_failure_probability=result.fire_facility_failure_probability,
                    flood_facility_failure_probability=result.flood_facility_failure_probability,
                    fire_asset_failure_probability=result.fire_asset_failure_probability,
                    flood_asset_failure_probability=result.flood_asset_failure_probability,
                    fire_effective_asset_count=result.fire_effective_asset_count,
                    flood_effective_asset_count=result.flood_effective_asset_count,
                    fire_redundancy_risk=result.fire_redundancy_risk,
                    flood_redundancy_risk=result.flood_redundancy_risk,
                    fire_joint_risk_probability=result.fire_joint_risk_probability,
                    flood_joint_risk_probability=result.flood_joint_risk_probability,
                    fire_redundancy_aware_risk_score=result.fire_redundancy_aware_risk_score,
                    flood_redundancy_aware_risk_score=result.flood_redundancy_aware_risk_score,
                ))
            end
        end
    end

    # Convert results to DataFrames
    result_df = isempty(results) ? DataFrame() : DataFrame(results)
    telco_failure_df = isempty(telco_failure_rows) ? DataFrame() : DataFrame(telco_failure_rows)
    CSV.write(joinpath(OUTPUT_DIR, "multi_hazard_telco_asset_failures.csv"), telco_failure_df)
    return result_df
end


function plot_hazard_raster_facilities(raster, facilities::AbstractDataFrame, state::AbstractString, hazard::AbstractString, longitude_col=:longitude, latitude_col=:latitude, probability_col=Symbol("$(hazard)_probability"), fallback_col=nothing)

    gt = raster.geotransform
    values = raster.values
    nrows, ncols = size(values)

    # Generate projected pixel-centre coordinates.
    x_coords = [gt[1] + (j - 0.5) * gt[2] for j in 1:ncols]
    y_coords = [gt[4] + (i - 0.5) * gt[6] for i in 1:nrows]

    # Mask NoData and invalid probability values.
    valid_mask = map(values) do value
        isfinite(value) && (raster.nodata === nothing || !isequal(value, raster.nodata)) && 0.0 <= value <= 1.0
    end

    raster_values = Float64.(values)
    raster_values[.!valid_mask] .= NaN

    # Reverse rows to display increasing northing upwards.
    raster_values = reverse(raster_values, dims=1)

    p = heatmap(
        x_coords,
        reverse(y_coords),
        raster_values;
        xlabel="Easting (m)",
        ylabel="Northing (m)",
        title="$state $hazard probability raster and facilities",
        colorbar_title="Hazard probability",
        aspect_ratio=:equal,
        legend=:outertopright,
        size=(1100, 850),
    )

    # Transform facility coordinates into EPSG:3577.
    facility_x = Float64[]
    facility_y = Float64[]
    facility_status = Symbol[]

    for row in eachrow(facilities)
        if ismissing(row[longitude_col]) || ismissing(row[latitude_col])
            continue
        end

        x, y = WGS84_TO_AU_ALBERS(Float64(row[longitude_col]), Float64(row[latitude_col]))
        push!(facility_x, x)
        push!(facility_y, y)

        if fallback_col !== nothing && fallback_col in propertynames(facilities) && row[fallback_col] === true
            push!(facility_status, :fallback)
        elseif ismissing(row[probability_col])
            push!(facility_status, :missing)
        else
            push!(facility_status, :valid)
        end
    end

    # Overlay facilities.
    for (status, colour, label) in (
        (:valid, :green, "Direct extraction"),
        (:fallback, :orange, "50 m fallback"),
        (:missing, :red, "Missing probability"),
    )
        indices = findall(==(status), facility_status)

        isempty(indices) && continue

        scatter!(
            p,
            facility_x[indices],
            facility_y[indices];
            color=colour,
            markersize=4,
            markerstrokewidth=0,
            label="$label ($(length(indices)))",
        )
    end

    output_path = joinpath(PLOT_DIR, "$(lowercase(state))_$(lowercase(hazard))_raster_facilities.png")
    savefig(p, output_path)

    @info "Hazard raster facility plot saved" state=state hazard=hazard path=output_path

    return p
end

"""
    run_spatial_analysis(; asset_conditional_failure_probabilities::AbstractDict, facility_conditional_failure_probabilities::AbstractDict)

Run the multi-hazard spatial analysis framework for telecommunications sites and evacuation facilities. The function loads the necessary datasets, extracts hazard probabilities, evaluates coverage scenarios, and computes failure probabilities for each facility based on its associated assets. It returns a tuple containing DataFrames for facilities, sites, consolidated results, and summary statistics.
"""
function run_spatial_analysis(; asset_conditional_failure_probabilities::AbstractDict, facility_conditional_failure_probabilities::AbstractDict)
    @info "Loading telecommunications sites"
    all_sites = load_telco_sites()
    sites = Dict(
        state => filter(row -> row.state == state, all_sites)
        for state in STATES
    )

    @info "Loading evacuation facilities"
    facilities = Dict(
        state => load_evacuation_facilities(EVACUATION_PATHS[Symbol(state)], state)
        for state in STATES
    )

    @info "Loading hazard rasters and extracting probabilities"
    for state in STATES
        hazard_data = load_hazard_rasters(state)
        add_hazard_probabilities!(sites[state], hazard_data; state=state)
        add_hazard_probabilities!(facilities[state], hazard_data; state=state)
        for hazard in keys(hazard_data)
            plot_hazard_raster_facilities(
                hazard_data[hazard],
                facilities[state],
                state,
                hazard,
            )
        end

        @info "Hazard probabilities extracted" state=state
    end

    # Combine facilities and telecommunications sites across all states
    @info "Combining spatial datasets"
    all_facilities = vcat(
        (facilities[state] for state in STATES)...;
        cols=:union,
    )

    all_sites_combined = vcat(
        (sites[state] for state in STATES)...;
        cols=:union,
    )

    @info "Running multi-hazard analysis" facilities=nrow(all_facilities) sites=nrow(all_sites_combined)
    all_results = analyse_multi_hazard(
        all_facilities,
        all_sites_combined;
        config=MODEL_CONFIG,
        asset_conditional_failure_probabilities=asset_conditional_failure_probabilities,
        facility_conditional_failure_probabilities=facility_conditional_failure_probabilities,
    )

    # Export facility coordinates
    @info "Exporting facility coordinates"
    facility_coordinates = select(
        all_facilities,
        :facility_id,
        :latitude,
        :longitude,
    )
    CSV.write(joinpath(OUTPUT_DIR, "facility_coordinates.csv"), facility_coordinates)

    # Export telecommunications asset coordinates
    @info "Exporting telecommunications asset coordinates"
    asset_coordinates = select(
        all_sites_combined,
        :asset_id,
        :latitude,
        :longitude,
        :name,
        :state,
    )
    CSV.write(joinpath(OUTPUT_DIR, "telecom_asset_coordinates.csv"), asset_coordinates)

    # Export consolidated results
    @info "Exporting consolidated results"

    CSV.write(joinpath(OUTPUT_DIR, "all_results.csv"), all_results)

    # Generate summary statistics
    @info "Generating summary statistics"
    summary = combine(
        groupby(all_results, [:state, :scenario, :analysis_period_years, :hazards]),
        nrow => :num_facilities,
        :normal_coverage_probability => mean => :mean_normal_coverage_probability,
        :no_coverage_probability => mean => :mean_no_coverage_probability,
        :fire_continuity_probability => mean => :mean_fire_continuity_probability,
        :flood_continuity_probability => mean => :mean_flood_continuity_probability,
        :fire_cutoff_probability => mean => :mean_fire_cutoff_probability,
        :flood_cutoff_probability => mean => :mean_flood_cutoff_probability,
        :fire_facility_failure_probability => mean => :mean_fire_facility_failure_probability,
        :flood_facility_failure_probability => mean => :mean_flood_facility_failure_probability,
        :fire_asset_failure_probability => mean => :mean_fire_asset_failure_probability,
        :flood_asset_failure_probability => mean => :mean_flood_asset_failure_probability,
        :fire_effective_asset_count => x -> mean(skipmissing(x)) => :mean_fire_effective_asset_count,
        :flood_effective_asset_count => x -> mean(skipmissing(x)) => :mean_flood_effective_asset_count,
        :fire_redundancy_risk => x -> mean(skipmissing(x)) => :mean_fire_redundancy_risk,
        :flood_redundancy_risk => x -> mean(skipmissing(x)) => :mean_flood_redundancy_risk,
        :fire_joint_risk_probability => mean => :mean_fire_joint_risk_probability,
        :flood_joint_risk_probability => mean => :mean_flood_joint_risk_probability,
        :fire_redundancy_aware_risk_score => x -> mean(skipmissing(x)) => :mean_fire_redundancy_aware_risk_score,
        :flood_redundancy_aware_risk_score => x -> mean(skipmissing(x)) => :mean_flood_redundancy_aware_risk_score,
    )
    CSV.write(joinpath(OUTPUT_DIR, "summary_by_state_scenario_hazards.csv"), summary)

    @info "Multi-hazard spatial analysis complete" output_directory=OUTPUT_DIR rows=nrow(all_results)

    return (facilities=all_facilities, sites=all_sites_combined, all=all_results, summary=summary)
end