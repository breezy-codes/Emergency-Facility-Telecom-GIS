const RESULTS_PATH = joinpath(ANALYSIS_DIR, "all_results.csv")

const METRICS = [
    (:normal_coverage_probability, "Normal coverage probability"),
    (:no_coverage_probability, "No coverage probability"),
    (:fire_continuity_probability, "Fire continuity probability"),
    (:flood_continuity_probability, "Flood continuity probability"),
    (:fire_cutoff_probability, "Fire cutoff probability"),
    (:flood_cutoff_probability, "Flood cutoff probability"),
    (:fire_facility_failure_probability, "Fire facility failure probability"),
    (:flood_facility_failure_probability, "Flood facility failure probability"),
    (:fire_asset_failure_probability, "Fire asset failure probability"),
    (:flood_asset_failure_probability, "Flood asset failure probability"),
    (:fire_joint_risk_probability, "Fire joint risk probability"),
    (:flood_joint_risk_probability, "Flood joint risk probability"),
    (:fire_redundancy_aware_risk_score, "Fire redundancy-aware risk score"),
    (:flood_redundancy_aware_risk_score, "Flood redundancy-aware risk score"),
]

mkpath(PLOT_PAPER_DIR)
default(
    fontfamily="sans-serif",
    markersize=4,
    titlefontsize=14,
    guidefontsize=12,       # Axis labels
    tickfontsize=10,        # Axis tick labels
    legendfontsize=7,
    legendtitlefontsize=10,
    grid=true,
    framestyle=:box,
    dpi=300,
)

Plots.scalefontsizes(1.8)

facility_coordinates = joinpath(ANALYSIS_DIR, "facility_coordinates.csv")
telecom_asset_coordinates = joinpath(ANALYSIS_DIR, "telecom_asset_coordinates.csv")
facility_coordinates = CSV.read(facility_coordinates, DataFrame)
telecom_asset_coordinates = CSV.read(telecom_asset_coordinates, DataFrame)

function load_results(; include_telco=false)
    combined_path = joinpath(ANALYSIS_DIR, "all_results.csv")
    isfile(combined_path) || error("Results CSV not found: $combined_path")

    df = CSV.read(combined_path, DataFrame)

    # Validate required columns.
    required = [
        :facility_id, :state, :facility_name, :scenario,
        :analysis_period_years, :hazards,
        :fire_occurrence_probability, :flood_occurrence_probability,
        :normal_coverage_probability, :no_coverage_probability,
        :fire_continuity_probability, :flood_continuity_probability,
        :fire_cutoff_probability, :flood_cutoff_probability,
        :fire_facility_failure_probability, :flood_facility_failure_probability,
        :fire_asset_failure_probability, :flood_asset_failure_probability,
        :fire_effective_asset_count, :flood_effective_asset_count,
        :fire_redundancy_risk, :flood_redundancy_risk,
        :fire_joint_risk_probability, :flood_joint_risk_probability,
        :fire_redundancy_aware_risk_score, :flood_redundancy_aware_risk_score
    ]

    missing_columns = setdiff(required, Symbol.(names(df)))
    isempty(missing_columns) || error("Results CSV missing columns: $(join(missing_columns, ", "))")

    # Normalise categorical columns.
    df.scenario = titlecase.(strip.(string.(df.scenario)))
    df.state = uppercase.(strip.(string.(df.state)))
    df.hazards = [join(sort(strip.(split(string(h), ";"))), ";") for h in df.hazards]

    # Convert analysis periods to integers.
    df.analysis_period_years = [ismissing(x) ? throw(ArgumentError("Missing analysis period in results")) : x isa Integer ? Int(x) : something(tryparse(Int, strip(string(x))), throw(ArgumentError("Invalid analysis period: $x"))) for x in df.analysis_period_years]

    # Convert configured metrics and probability columns to Float64.
    probability_metrics = [
        :fire_occurrence_probability, :flood_occurrence_probability,
        :normal_coverage_probability, :no_coverage_probability,
        :fire_continuity_probability, :flood_continuity_probability,
        :fire_cutoff_probability, :flood_cutoff_probability,
        :fire_facility_failure_probability, :flood_facility_failure_probability,
        :fire_asset_failure_probability, :flood_asset_failure_probability,
        :fire_redundancy_risk, :flood_redundancy_risk,
        :fire_joint_risk_probability, :flood_joint_risk_probability,
        :fire_redundancy_aware_risk_score, :flood_redundancy_aware_risk_score
    ]

    count_metrics = [
        :fire_effective_asset_count, :flood_effective_asset_count
    ]

    configured_metrics = collect(first.(METRICS))
    numeric_metrics = unique(vcat(configured_metrics, probability_metrics, count_metrics))

    for metric in numeric_metrics
        if metric in propertynames(df)
            df[!, metric] = [ismissing(x) ? NaN : x isa Real ? Float64(x) : something(tryparse(Float64, strip(string(x))), NaN) for x in df[!, metric]]
        elseif metric in configured_metrics
            error("Results CSV missing metric column: $metric")
        end
    end

    # Validate probability and risk score ranges.
    for metric in probability_metrics
        metric in propertynames(df) || continue
        all(x -> isnan(x) || (isfinite(x) && 0 <= x <= 1), df[!, metric]) || throw(ArgumentError("Invalid probabilities or risk scores in column: $metric"))
    end

    # Validate effective asset counts.
    for metric in count_metrics
        all(x -> isnan(x) || (isfinite(x) && x >= 0), df[!, metric]) || throw(ArgumentError("Invalid effective asset counts in column: $metric"))
    end

    # Validate state configuration.
    invalid_states = setdiff(unique(df.state), collect(keys(STATE_HAZARDS)))
    isempty(invalid_states) || error("Results contain states not configured in STATE_HAZARDS: $(join(invalid_states, ", "))")

    # Validate hazard configuration against result rows.
    for row in eachrow(df)
        expected_hazards = join(sort(collect(STATE_HAZARDS[row.state])), ";")
        actual_hazards = row.hazards
        actual_hazards == expected_hazards || @warn "Result hazards differ from STATE_HAZARDS" state=row.state actual=actual_hazards expected=expected_hazards
    end

    # Detect duplicate facility/scenario/period combinations.
    key = [:facility_id, :scenario, :analysis_period_years]
    duplicate_count = nrow(df) - nrow(unique(df, key))
    duplicate_count > 0 && @warn "Duplicate facility/scenario/period rows found" duplicate_count

    @info "Loaded facility results" path=combined_path rows=nrow(df) facilities=length(unique(df.facility_id)) periods=sort(unique(df.analysis_period_years))

    # Return facility results only unless telecommunications assets are requested.
    include_telco || return df

    telco_path = joinpath(OUTPUT_DIR, "multi_hazard_telco_asset_failures.csv")
    isfile(telco_path) || error("Telecommunications asset results CSV not found: $telco_path")

    telco = CSV.read(telco_path, DataFrame)

    # Validate telecommunications asset columns.
    telco_required = [:asset_id, :state, :hazard, :analysis_period_years, :annual_occurrence_probability, :conditional_failure_probability, :failure_probability]
    missing_telco_columns = setdiff(telco_required, Symbol.(names(telco)))
    isempty(missing_telco_columns) || error("Telecommunications asset CSV missing columns: $(join(missing_telco_columns, ", "))")

    # Normalise categorical columns.
    telco.state = uppercase.(strip.(string.(telco.state)))
    telco.hazard = lowercase.(strip.(string.(telco.hazard)))

    # Convert analysis periods to integers.
    telco.analysis_period_years = [ismissing(x) ? throw(ArgumentError("Missing asset analysis period")) : x isa Integer ? Int(x) : something(tryparse(Int, strip(string(x))), throw(ArgumentError("Invalid asset analysis period: $x"))) for x in telco.analysis_period_years]

    # Convert probability columns to Float64.
    telco_probability_columns = [:annual_occurrence_probability, :conditional_failure_probability, :failure_probability]

    for column in telco_probability_columns
        telco[!, column] = [ismissing(x) ? NaN : x isa Real ? Float64(x) : something(tryparse(Float64, strip(string(x))), NaN) for x in telco[!, column]]
        all(x -> isfinite(x) && 0 <= x <= 1, telco[!, column]) || throw(ArgumentError("Invalid probabilities in telecommunications asset column: $column"))
    end

    # Validate asset states and hazards.
    invalid_telco_states = setdiff(unique(telco.state), collect(keys(STATE_HAZARDS)))
    isempty(invalid_telco_states) || error("Telecommunications assets contain unconfigured states: $(join(invalid_telco_states, ", "))")

    for row in eachrow(telco)
        row.hazard in STATE_HAZARDS[row.state] || throw(ArgumentError("Hazard $(row.hazard) is not configured for state $(row.state)"))
    end

    # Detect duplicate asset/hazard/period combinations.
    telco_key = [:asset_id, :hazard, :analysis_period_years]
    telco_duplicates = nrow(telco) - nrow(unique(telco, telco_key))
    telco_duplicates > 0 && @warn "Duplicate telecommunications asset/hazard/period rows found" duplicate_count=telco_duplicates

    @info "Loaded telecommunications asset results" path=telco_path rows=nrow(telco) assets=length(unique(telco.asset_id)) periods=sort(unique(telco.analysis_period_years))

    return (facilities=df, telco_assets=telco)
end