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
    guidefontsize=12,
    tickfontsize=10,
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
        :facility_id, :state, :facility_name, :scenario, :analysis_period_years, :hazards,
        :fire_occurrence_probability, :flood_occurrence_probability, :normal_coverage_probability, :no_coverage_probability,
        :fire_continuity_probability, :flood_continuity_probability, :fire_cutoff_probability, :flood_cutoff_probability,
        :fire_facility_failure_probability, :flood_facility_failure_probability, :fire_asset_failure_probability, :flood_asset_failure_probability,
        :fire_effective_asset_count, :flood_effective_asset_count, :fire_redundancy_risk, :flood_redundancy_risk,
        :fire_joint_risk_probability, :flood_joint_risk_probability, :fire_redundancy_aware_risk_score, :flood_redundancy_aware_risk_score
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
        :fire_occurrence_probability, :flood_occurrence_probability, :normal_coverage_probability, :no_coverage_probability,
        :fire_continuity_probability, :flood_continuity_probability, :fire_cutoff_probability, :flood_cutoff_probability,
        :fire_facility_failure_probability, :flood_facility_failure_probability, :fire_asset_failure_probability, :flood_asset_failure_probability,
        :fire_redundancy_risk, :flood_redundancy_risk, :fire_joint_risk_probability, :flood_joint_risk_probability,
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

"""
    save_accessibility_latex_table(results::AbstractDataFrame)

Saves a LaTeX table comparing the physical accessibility of evacuation facilities to telecommunications assets, and the percentage of facilities within coverage range by state and scenario.
Used within the paper to present the results of the accessibility analysis.
"""
function save_accessibility_latex_table(results::AbstractDataFrame)
    output_file = joinpath(PLOT_PAPER_DIR, "state_accessibility_comparison.tex")
    required = [:state, :facility_id, :scenario, :nearest_asset_distance_m, :within_range]
    missing_cols = setdiff(required, Symbol.(names(results)))
    isempty(missing_cols) || error("Missing columns: $(join(string.(missing_cols), ", ")).")
    all(state -> haskey(STATE_HAZARDS, state), STATES) || error("STATE_HAZARDS must define every state in STATES.")

    d = select(results, required)
    d.state = uppercase.(strip.(string.(d.state)))
    d.scenario = titlecase.(strip.(string.(d.scenario)))
    d.nearest_asset_distance_m = [ismissing(x) || isnothing(x) ? NaN : x isa Real ? Float64(x) : something(tryparse(Float64, strip(string(x))), NaN) for x in d.nearest_asset_distance_m]
    d = filter(r -> r.state in STATES && r.scenario in titlecase.(string.(SCENARIO_ORDER)) && isfinite(r.nearest_asset_distance_m) && !ismissing(r.within_range), d)
    unique!(d, [:state, :facility_id, :scenario])

    physical = combine(groupby(d, :state), :facility_id => (x -> length(unique(x))) => :num_facilities, :nearest_asset_distance_m => median => :median_distance_m)
    coverage = combine(groupby(d, [:state, :scenario]), :within_range => (x -> 100 * mean(Bool.(x))) => :within_range_pct)
    coverage_wide = unstack(coverage, :state, :scenario, :within_range_pct)

    open(output_file, "w") do io
        println(io, raw"\begin{table}[ht]")
        println(io, raw"\centering")
        println(io, raw"\small")
        println(io, raw"\caption{Physical accessibility of evacuation facilities to telecommunications assets.}")
        println(io, raw"\label{tab:physical_accessibility}")
        println(io, raw"\begin{tabular}{lrr}")
        println(io, raw"\hline")
        println(io, raw"\textbf{State} & \textbf{Facilities} & \textbf{Median nearest-asset distance (m)} \\\\")
        println(io, raw"\hline")

        for state in STATES
            rows = filter(:state => ==(state), physical)
            isempty(rows) && continue
            r = first(rows)
            println(io, "$(state) & $(r.num_facilities) & $(round(r.median_distance_m; digits=1)) \\\\")
        end

        println(io, raw"\hline")
        println(io, raw"\end{tabular}")
        println(io, raw"\end{table}")
        println(io, "")
        println(io, raw"\begin{table}[ht]")
        println(io, raw"\centering")
        println(io, raw"\caption{Percentage of evacuation facilities within telecommunications coverage range by state and scenario.}")
        println(io, raw"\label{tab:scenario_coverage}")
        println(io, raw"\begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}l" * repeat("r", length(SCENARIO_ORDER)) * "}")
        println(io, raw"\hline")

        print(io, raw"\textbf{State}")
        for scenario in SCENARIO_ORDER
            print(io, " & \\textbf{", titlecase(string(scenario)), "}")
        end
        println(io, raw" \\\\")
        println(io, raw"\hline")

        for state in STATES
            rows = filter(:state => ==(state), coverage_wide)
            isempty(rows) && continue
            r = first(rows)

            print(io, state)

            for scenario in SCENARIO_ORDER
                col = Symbol(titlecase(string(scenario)))
                value = col in propertynames(coverage_wide) ? r[col] : missing

                if ismissing(value)
                    print(io, " & --")
                else
                    colour = value < 45 ? "coverageLow" :
                             value < 75 ? "coverageModerate" :
                             value < 90 ? "coverageGood" :
                             "coverageExcellent"

                    formatted = "$(round(value; digits=2))\\%"
                    print(io, " & \\coverage{", colour, "}{", formatted, "}")
                end
            end

            println(io, raw" \\\\")
        end

        println(io, raw"\hline")
        println(io, raw"\end{tabular*}")
        println(io, raw"\vspace{5pt}")

        # Coverage classification legend
        println(io, raw"\noindent\makebox[\textwidth][c]{%")
        println(io, raw"\scriptsize")
        println(io, raw"\tikz[baseline=-0.5ex]\node[fill=coverageLow, minimum width=0.25cm, minimum height=0.18cm, inner sep=0pt] {};%")
        println(io, raw"\hspace{3pt}Low (<45\%)%")
        println(io, raw"\hspace{18pt}%")
        println(io, raw"\tikz[baseline=-0.5ex]\node[fill=coverageModerate, minimum width=0.25cm, minimum height=0.18cm, inner sep=0pt] {};%")
        println(io, raw"\hspace{3pt}Moderate (45--74.99\%)%")
        println(io, raw"\hspace{18pt}%")
        println(io, raw"\tikz[baseline=-0.5ex]\node[fill=coverageGood, minimum width=0.25cm, minimum height=0.18cm, inner sep=0pt] {};%")
        println(io, raw"\hspace{3pt}Good (75--89.99\%)%")
        println(io, raw"\hspace{18pt}%")
        println(io, raw"\tikz[baseline=-0.5ex]\node[fill=coverageExcellent, minimum width=0.25cm, minimum height=0.18cm, inner sep=0pt] {};%")
        println(io, raw"\hspace{3pt}Excellent ($\geq$90\%)%")
        println(io, raw"}")
        println(io, raw"\end{table}")
    end
    @info "Saved accessibility LaTeX tables" output_file
    return nothing
end


"""
    save_baseline_coverage_figures(df::AbstractDataFrame=load_results())

Saves figures comparing the baseline coverage probabilities of evacuation facilities by state and scenario, and the distributions of facility-level coverage probabilities.
Used within the paper to present the results of the baseline coverage analysis.
"""
function save_baseline_coverage_figures(df::AbstractDataFrame=load_results())
    required = [:facility_id, :scenario, :state, :analysis_period_years, :normal_coverage_probability]
    missing_cols = setdiff(required, Symbol.(names(df)))
    isempty(missing_cols) || error("Missing columns: $(join(missing_cols, ", "))")

    d = DataFrame(df)

    # Restrict analysis to one-year results.
    d.analysis_period_years = Int.(d.analysis_period_years)
    filter!(r -> r.analysis_period_years == 1, d)
    isempty(d) && error("No one-year results available for baseline coverage figures.")

    # Normalise categorical columns.
    d.scenario = titlecase.(strip.(string.(d.scenario)))
    d.state = uppercase.(strip.(string.(d.state)))

    # Convert coverage probabilities to Float64.
    d.normal_coverage_probability = [
        ismissing(x) ? NaN :
        x isa Real ? Float64(x) :
        something(tryparse(Float64, strip(string(x))), NaN)
        for x in d.normal_coverage_probability
    ]

    filter!(r -> isfinite(r.normal_coverage_probability) && 0 <= r.normal_coverage_probability <= 1, d)
    isempty(d) && error("No valid one-year coverage probabilities available for plotting.")

    # Retain one result per facility, scenario and state.
    unique!(d, [:facility_id, :scenario, :state])

    scenarios = titlecase.(string.(SCENARIO_ORDER))
    scenario_labels = string.(SCENARIO_ORDER)
    state_colours = [:steelblue, :darkorange, :seagreen, :firebrick]
    scenario_colours = [:steelblue, :darkorange, :seagreen, :firebrick, :mediumpurple, :goldenrod]

    # Identify scenarios by their generation labels.
    scenarios_4g = filter(s -> occursin("4G", s), scenarios)
    scenarios_5g = filter(s -> occursin("5G", s), scenarios)

    """
        geographic_plot(generation_scenarios, generation)
    Plots the mean facility-level coverage probabilities by state for a given set of deployment scenarios and generation (4G or 5G). Returns the plot object.
    """
    function geographic_plot(generation_scenarios, generation)
        p = plot(; xlabel="", ylabel=generation == "4G" ? "Mean facility coverage probability" : "", xlims=(0.7, length(generation_scenarios) + 0.3), ylims=(0, 1), guidefontsize=17, xticks=(1:length(generation_scenarios), [scenario_labels[findfirst(==(s), scenarios)] for s in generation_scenarios]), xrotation=15, legend=:bottomright, grid=:y, size=(750, 650), left_margin=1Plots.mm, bottom_margin=0Plots.mm, right_margin=0Plots.mm, top_margin=1Plots.mm)

        for (j, state) in enumerate(STATES)
            means = Float64[]
            positions = Int[]

            for (i, scenario) in enumerate(generation_scenarios)
                vals = d[(d.scenario .== scenario) .& (d.state .== state), :normal_coverage_probability]
                filter!(isfinite, vals)
                isempty(vals) && continue
                push!(positions, i)
                push!(means, mean(vals))
            end

            isempty(means) && continue
            plot!(p, positions, means; label=state, color=state_colours[mod1(j, length(state_colours))], marker=:circle, markersize=5, linewidth=2)
        end

        return p
    end

    p4g = geographic_plot(scenarios_4g, "4G")
    p5g = geographic_plot(scenarios_5g, "5G")
    p_geographic = plot(p4g, p5g; layout=grid(1, 2), size=(1500, 600), left_margin=8Plots.mm, bottom_margin=8Plots.mm, right_margin=0Plots.mm, top_margin=2Plots.mm)
    xlabel_panel = plot(; framestyle=:none, grid=false, xaxis=false, yaxis=false, bottom_margin=0Plots.mm, top_margin=0Plots.mm, annotations=[(0.5, 0.5, text("Deployment scenario", 17, :center))])
    p_geographic = plot(p_geographic, xlabel_panel; layout=grid(2, 1, heights=[0.97, 0.03]), size=(1500, 600))
    savefig(p_geographic, joinpath(PLOT_PAPER_DIR, "baseline_geographic_comparison.png"))

    # Facility-level ECDF: all 4G and 5G scenarios on one figure.
    p_dist = plot(; xlabel="Facility-level coverage probability", ylabel="Cumulative proportion", xlims=(0, 1), ylims=(0, 1), legend=:bottomright, size=(1300, 600), left_margin=5Plots.mm, bottom_margin=7Plots.mm, right_margin=4Plots.mm, grid=true)

    for (i, scenario) in enumerate(scenarios)
        vals = sort(filter(isfinite, d[d.scenario .== scenario, :normal_coverage_probability]))
        isempty(vals) && continue
        label = scenario_labels[findfirst(==(scenario), scenarios)]
        plot!(p_dist, vals, (1:length(vals)) ./ length(vals); seriestype=:steppost, label=label, color=scenario_colours[mod1(i, length(scenario_colours))], linewidth=2.2)
    end

    savefig(p_dist, joinpath(PLOT_PAPER_DIR, "baseline_facility_coverage_distributions.png"))

    @info "Saved one-year baseline coverage figures" PLOT_PAPER_DIR facilities=length(unique(d.facility_id)) scenarios=length(unique(d.scenario))

    return (geographic=p_geographic, distributions=p_dist)
end

"""
    save_hazard_failure_figures(results=load_results(include_telco=true))
Saves figures comparing the distributions of facility-level and telecommunications asset-level hazard failure probabilities by state and scenario.
Used within the paper to present the results of the hazard failure analysis.
"""
function save_hazard_failure_figures(results=load_results(include_telco=true))
    facility_df = results isa NamedTuple ? results.facilities : results
    telco_df = results isa NamedTuple ? results.telco_assets : nothing

    state_colours = Dict("NSW" => :dodgerblue, "VIC" => :orangered, "SA" => :seagreen, "TAS" => :mediumpurple)
    periods = [1, 5, 10]
    distributions = Dict{String,Plots.Plot}()
    telco_distributions = Dict{String,Plots.Plot}()

    function create_observations(df, probability_columns, asset_column)
        observations = DataFrame(asset_id=eltype(df[!, asset_column])[], state=String[], analysis_period_years=Int[], hazard=String[], probability=Float64[])

        for (hazard, column) in probability_columns
            for row in eachrow(df)
                probability = row[column]
                ismissing(probability) && continue
                probability = try Float64(probability) catch; continue end
                isfinite(probability) && 0 <= probability <= 1 || continue
                push!(observations, (row[asset_column], uppercase(strip(string(row.state))), Int(row.analysis_period_years), hazard, probability))
            end
        end

        return observations
    end

    """
        plot_hazard_distributions(observations, filename_prefix, xlabel)
    Plots the distributions of hazard failure probabilities for each hazard, given a DataFrame of observations containing the columns: :asset_id, :state, :analysis_period_years, :hazard, and :probability. The resulting figures are saved to the PLOT_PAPER_DIR with filenames prefixed by `filename_prefix`. The x-axis label is set to `xlabel`.
    """
    function plot_hazard_distributions(observations, filename_prefix, xlabel)
        figures = Dict{String,Plots.Plot}()

        for hazard in HAZARDS
            panels = Plots.Plot[]

            for period in periods
                hazard_data = filter(row -> row.hazard == hazard && row.analysis_period_years == period, observations)
                p = plot(; title="$period year$(period == 1 ? "" : "s")", xlabel="", ylabel=period == first(periods) ? "Cumulative proportion" : "", xlims=(0, 1), ylims=(0, 1), legend=:bottomright, grid=true)

                if isempty(hazard_data)
                    annotate!(p, 0.5, 0.5, text("No data available", 10))
                else
                    for state in STATES
                        state_data = filter(:state => ==(state), hazard_data)
                        isempty(state_data) && continue
                        all_values = filter(isfinite, state_data.probability)
                        isempty(all_values) && continue
                        zero_fraction = 100 * mean(all_values .== 0.0)
                        values = sort(filter(x -> x > 0, all_values))

                        if isempty(values)
                            plot!(p, Float64[], Float64[]; label="$state ($(round(zero_fraction, digits=1))% zero)", color=get(state_colours, state, :gray), linewidth=2)
                            continue
                        end

                        ecdf_y = collect(1:length(values)) ./ length(values)
                        plot!(p, values, ecdf_y; seriestype=:steppost, linewidth=2, label="$state ($(round(zero_fraction, digits=1))% zero)", color=get(state_colours, state, :gray))
                    end
                end

                push!(panels, p)
            end

            p3 = plot(panels...; layout=grid(1, 3), size=(2000, 600), left_margin=12Plots.mm, right_margin=3Plots.mm, bottom_margin=4Plots.mm, top_margin=10Plots.mm, plot_title="")
            xlabel_panel = plot(; framestyle=:none, grid=false, xaxis=false, yaxis=false, bottom_margin=0Plots.mm, top_margin=0Plots.mm, annotations=[(0.5, 0.5, text(xlabel, 22, :center))])
            figure = plot(p3, xlabel_panel; layout=grid(2, 1, heights=[0.95, 0.05]), size=(2000, 600))
            savefig(figure, joinpath(PLOT_PAPER_DIR, "$(filename_prefix)_$(hazard)_failure_probability_ecdfs.png"))
            figures[hazard] = figure
        end

        return figures
    end

    # Facility-level asset failure probabilities.
    facility_required = [:facility_id, :state, :analysis_period_years, :fire_asset_failure_probability, :flood_asset_failure_probability]
    missing_cols = setdiff(facility_required, Symbol.(names(facility_df)))
    isempty(missing_cols) || error("Facility results missing columns: $(join(missing_cols, ", "))")

    facility_observations = create_observations(facility_df, Dict("fire" => :fire_asset_failure_probability, "flood" => :flood_asset_failure_probability), :facility_id)
    isempty(facility_observations) && @warn "No facility-level hazard failure probabilities available for plotting."
    !isempty(facility_observations) && merge!(distributions, plot_hazard_distributions(facility_observations, "facility", "Mean facility failure probability (non-zero observations)"))

    # Individual telecommunications asset failure probabilities.
    if !isnothing(telco_df)
        telco_required = [:asset_id, :state, :hazard, :analysis_period_years, :failure_probability]
        missing_telco_cols = setdiff(telco_required, Symbol.(names(telco_df)))
        isempty(missing_telco_cols) || error("Telecommunications asset results missing columns: $(join(missing_telco_cols, ", "))")

        telco_observations = create_observations(telco_df, Dict(hazard => :failure_probability for hazard in HAZARDS), :asset_id)
        isempty(telco_observations) && @warn "No individual telecommunications asset failure probabilities available for plotting."
        !isempty(telco_observations) && merge!(telco_distributions, plot_hazard_distributions(telco_observations, "telco_asset", "Individual asset failure probability (non-zero observations)"))
    else
        telco_observations = DataFrame()
        @warn "No telecommunications asset DataFrame supplied; only facility-level figures were generated."
    end

    @info "Saved hazard failure probability figures" PLOT_PAPER_DIR facility_observations=nrow(facility_observations) telco_observations=nrow(telco_observations)

    return (facility_observations=facility_observations, telco_observations=telco_observations, facility_distributions=distributions, telco_distributions=telco_distributions)
end

"""
    save_continuity_cutoff_figures(df::AbstractDataFrame)
Saves figures comparing the continuity and cutoff probabilities of evacuation facilities by hazard and analysis period.
Used within the paper to present the results of the continuity and cutoff probability analysis.
"""
function save_continuity_cutoff_figures(df::AbstractDataFrame)
    required = [:facility_id, :state, :scenario, :analysis_period_years, :normal_coverage_probability, :fire_continuity_probability, :flood_continuity_probability, :fire_cutoff_probability, :flood_cutoff_probability]
    missing_cols = setdiff(required, propertynames(df))
    isempty(missing_cols) || error("Missing required columns: $(join(string.(missing_cols), ", "))")

    d = DataFrame(df)
    d.state = uppercase.(strip.(string.(d.state)))
    d.scenario = titlecase.(strip.(string.(d.scenario)))
    d.analysis_period_years = Int.(d.analysis_period_years)
    filter!(r -> !ismissing(r.normal_coverage_probability) && isfinite(r.normal_coverage_probability) && 0 <= r.normal_coverage_probability <= 1, d)
    unique!(d, [:facility_id, :state, :scenario, :analysis_period_years])

    if isempty(d)
        @warn "No valid continuity and cutoff probabilities available."
        return nothing
    end

    hazards = ("fire", "flood")
    hazard_labels = Dict("fire" => "Fire", "flood" => "Flood")
    hazard_colours = Dict("fire" => :dodgerblue, "flood" => :orangered)
    analysis_periods = sort(unique(d.analysis_period_years))

    # Figure 1: Baseline coverage versus continuity, separated by hazard and analysis period.
    for N in analysis_periods
        period_data = filter(:analysis_period_years => ==(N), d)
        p1 = plot(; xlabel="Baseline coverage", ylabel="Continuity probability", xlims=(0, 1), ylims=(0, 1), legend=:topleft, size=(750, 750), aspect_ratio=:equal, left_margin=0Plots.mm, right_margin=3Plots.mm, top_margin=0Plots.mm, bottom_margin=0Plots.mm, framestyle=:box, dpi=300)
        plot!(p1, [0, 1], [0, 1]; color=:black, linestyle=:dash, linewidth=1.5, label="No reduction from baseline")

        for hazard in hazards
            continuity_col = Symbol("$(hazard)_continuity_probability")
            rows = filter(r -> !ismissing(r[continuity_col]) && isfinite(r[continuity_col]) && 0 <= r[continuity_col] <= 1, period_data)
            isempty(rows) && continue
            scatter!(p1, rows.normal_coverage_probability, rows[!, continuity_col]; label=hazard_labels[hazard], color=hazard_colours[hazard], markersize=3, alpha=0.45, markerstrokewidth=0)
        end

        savefig(p1, joinpath(PLOT_PAPER_DIR, "continuity_vs_baseline_coverage_$(N)_years.png"))
    end

    # Figure 2: ECDFs of continuity and cutoff probabilities, separated by hazard and analysis period.
    for N in analysis_periods
        period_data = filter(:analysis_period_years => ==(N), d)
        p2 = plot(; xlabel="Probability", ylabel="Cumulative proportion", xlims=(0, 1), ylims=(0, 1), legend=:bottomright, size=(750, 750), left_margin=0Plots.mm, bottom_margin=0Plots.mm, top_margin=2Plots.mm, right_margin=3Plots.mm)

        for hazard in hazards
            continuity_col = Symbol("$(hazard)_continuity_probability")
            cutoff_col = Symbol("$(hazard)_cutoff_probability")
            continuity_values = sort(filter(x -> !ismissing(x) && isfinite(x) && 0 <= x <= 1, period_data[!, continuity_col]))
            cutoff_values = sort(filter(x -> !ismissing(x) && isfinite(x) && 0 <= x <= 1, period_data[!, cutoff_col]))

            if !isempty(continuity_values)
                plot!(p2, continuity_values, (1:length(continuity_values)) ./ length(continuity_values); seriestype=:steppost, linewidth=2, label="Continuity — $(hazard_labels[hazard])", color=hazard_colours[hazard])
            end

            if !isempty(cutoff_values)
                plot!(p2, cutoff_values, (1:length(cutoff_values)) ./ length(cutoff_values); seriestype=:steppost, linewidth=2, label="Cutoff — $(hazard_labels[hazard])", color=hazard_colours[hazard], linestyle=:dash)
            end
        end

        savefig(p2, joinpath(PLOT_PAPER_DIR, "continuity_cutoff_distributions_$(N)_years.png"))
    end

    # Figure 3: Facility continuity outcomes by deployment scenario across all states (1 year).
    outcome_order = ["Full continuity", "Partial continuity", "Complete cutoff"]
    outcome_colours = ["#66BB6A", "#FFC107", "#D32F2F"]
    period_data = filter(:analysis_period_years => ==(1), d)

    if isempty(period_data)
        @warn "No results available for the 1-year analysis period."
    else
        hazard_plots = Plots.Plot[]
        shared_scenarios = [s for s in reverse(SCENARIO_ORDER) if s in period_data.scenario]

        for (hazard_idx, hazard) in enumerate(hazards)
            continuity_col = Symbol("$(hazard)_continuity_probability")
            hazard_data = filter(r -> !ismissing(r[continuity_col]) && isfinite(r[continuity_col]) && 0 <= r[continuity_col] <= 1, period_data)

            if isempty(hazard_data)
                p = plot(; title="", framestyle=:none, grid=false)
                annotate!(p, 0.5, 0.5, text("No data available", 12))
                push!(hazard_plots, p)
                continue
            end

            facility_outcomes = select(hazard_data, [:facility_id, :state, :scenario, :normal_coverage_probability, continuity_col])
            rename!(facility_outcomes, continuity_col => :continuity_probability)
            unique!(facility_outcomes, [:facility_id, :state, :scenario])
            facility_outcomes.outcome = [p <= 1e-10 && b > 1e-10 ? "Complete cutoff" : p < b - 1e-10 ? "Partial continuity" : "Full continuity" for (p, b) in zip(facility_outcomes.continuity_probability, facility_outcomes.normal_coverage_probability)]

            scenarios = shared_scenarios
            counts = [count((facility_outcomes.scenario .== s) .& (facility_outcomes.outcome .== outcome)) for s in scenarios, outcome in outcome_order]

            p = plot(; title=uppercasefirst(hazard), xlabel="", ylabel=hazard_idx == 1 ? "Deployment scenario" : "", yticks=(1:length(scenarios), hazard_idx == 1 ? [uppercasefirst(s) for s in scenarios] : fill("", length(scenarios))), ylims=(0.5, length(scenarios) + 0.5), xlims=(0, max(1, maximum(sum(counts; dims=2)) * 1.05)), legend=hazard_idx == 1 ? :topleft : false, grid=:x, left_margin=8Plots.mm, bottom_margin=3Plots.mm, right_margin=4Plots.mm, top_margin=0Plots.mm)

            for (j, outcome) in enumerate(outcome_order)
                left = j == 1 ? zeros(Int, length(scenarios)) : vec(sum(counts[:, 1:(j-1)]; dims=2))
                right = left .+ counts[:, j]

                for i in eachindex(scenarios)
                    right[i] <= left[i] && continue
                    plot!(p, [left[i], right[i], right[i], left[i]], [i - 0.4, i - 0.4, i + 0.4, i + 0.4]; seriestype=:shape, fillcolor=outcome_colours[j], linecolor=:black, linewidth=1, label=i == 1 ? outcome : "")
                end
            end

            push!(hazard_plots, p)
        end

        p_all = plot(hazard_plots...; layout=grid(1, 2), size=(2000, 550), top_margin=4Plots.mm, margins=0Plots.mm)

        # Reduce horizontal spacing.
        plot!(p_all; left_margin=0Plots.mm, right_margin=-5Plots.mm, subplot=1)
        plot!(p_all; left_margin=-8Plots.mm, right_margin=0Plots.mm, subplot=2)

        # Shared horizontal axis label.
        xlabel_panel = plot(; framestyle=:none, grid=false, xaxis=false, yaxis=false, margin=0Plots.mm, annotations=[(0.5, 0.5, text("Number of facilities across all states", 19, :center))])
        p_final = plot(p_all, xlabel_panel; layout=grid(2, 1; heights=[0.94, 0.06]), size=(2000, 550), margin=0Plots.mm)

        savefig(p_final, joinpath(PLOT_PAPER_DIR, "fire_flood_continuity_outcomes_all_states_1_year.png"))
    end

    # Figure 4: Baseline coverage outcomes across all states by deployment scenario (1 year).
    coverage_order = ["Full coverage", "Partial coverage", "No coverage"]
    coverage_colours = ["#66BB6A", "#FFC107", "#D32F2F"]
    period_data = filter(:analysis_period_years => ==(1), d)

    if isempty(period_data)
        @warn "No results available for the 1-year baseline coverage figure."
    else
        facility_coverage = select(period_data, [:facility_id, :state, :scenario, :normal_coverage_probability])
        unique!(facility_coverage, [:facility_id, :state, :scenario])

        facility_coverage.coverage_outcome = [p >= 1.0 - 1e-10 ? "Full coverage" : p <= 1e-10 ? "No coverage" : "Partial coverage" for p in facility_coverage.normal_coverage_probability]

        scenarios = [s for s in reverse(SCENARIO_ORDER) if s in facility_coverage.scenario]
        counts = [count((facility_coverage.scenario .== s) .& (facility_coverage.coverage_outcome .== outcome)) for s in scenarios, outcome in coverage_order]

        p4 = plot(; xlabel="Number of facilities across all states", ylabel="Deployment scenario", yticks=(1:length(scenarios), [uppercasefirst(s) for s in scenarios]), ylims=(0.5, length(scenarios) + 0.5), xlims=(0, max(1, maximum(sum(counts; dims=2)) * 1.05)), legend=:topright, grid=:x, size=(1400, 600), left_margin=8Plots.mm, bottom_margin=10Plots.mm, right_margin=6Plots.mm, top_margin=5Plots.mm)

        for (j, outcome) in enumerate(coverage_order)
            left = j == 1 ? zeros(Int, length(scenarios)) : vec(sum(counts[:, 1:(j-1)]; dims=2))
            right = left .+ counts[:, j]

            for i in eachindex(scenarios)
                right[i] <= left[i] && continue
                plot!(p4, [left[i], right[i], right[i], left[i]], [i - 0.4, i - 0.4, i + 0.4, i + 0.4]; seriestype=:shape, fillcolor=coverage_colours[j], linecolor=:black, linewidth=1, label=i == 1 ? outcome : "")
            end
        end

        savefig(p4, joinpath(PLOT_PAPER_DIR, "baseline_coverage_outcomes_all_states_1_year.png"))
    end

    @info "Saved continuity and cutoff figures"
    return nothing
end

"""
    save_state_risk_comparison_plots(df::AbstractDataFrame)
Saves plots comparing the joint risk probabilities, redundancy-aware risk scores, and no-coverage probabilities by state and hazard for the 1-year analysis period.
Used within the paper to present the results of the state-level risk comparison analysis.
"""
function save_state_risk_comparison_plots(df::AbstractDataFrame)
    required = [:state, :scenario, :analysis_period_years, :fire_joint_risk_probability, :fire_redundancy_aware_risk_score, :flood_joint_risk_probability, :flood_redundancy_aware_risk_score, :no_coverage_probability]
    missing_cols = setdiff(required, propertynames(df))
    isempty(missing_cols) || error("Missing required columns: $(join(string.(missing_cols), ", "))")

    d = DataFrame(df)
    d.state = uppercase.(strip.(string.(d.state)))
    d.scenario = titlecase.(strip.(string.(d.scenario)))
    d.analysis_period_years = Int.(d.analysis_period_years)
    filter!(r -> r.analysis_period_years == 1, d)

    if isempty(d)
        @warn "No results available for the 1-year analysis period."
        return nothing
    end

    combinations = [(state, hazard) for (state, hazards) in STATE_HAZARDS for hazard in hazards]
    panels = Plots.Plot[]

    for (panel_idx, (state, hazard)) in enumerate(combinations)
        joint_col = Symbol("$(hazard)_joint_risk_probability")
        redundancy_col = Symbol("$(hazard)_redundancy_aware_risk_score")
        no_cover_col = :no_coverage_probability

        sub = filter(r -> r.state == state && !ismissing(r[joint_col]) && !ismissing(r[redundancy_col]) && !ismissing(r[no_cover_col]) && isfinite(r[joint_col]) && isfinite(r[redundancy_col]) && isfinite(r[no_cover_col]) && 0 <= r[joint_col] <= 1 && 0 <= r[redundancy_col] <= 1 && 0 <= r[no_cover_col] <= 1, d)

        p = plot(; title="$(state)-$(uppercase(hazard))", xlabel="", ylabel="", xlims=(0, 1.08), xticks=0.0:0.1:1.0, legend=false, left_margin=0Plots.mm, right_margin=0Plots.mm, margin=0Plots.mm, grid=:x)

        if !isempty(sub)
            summary = combine(groupby(sub, :scenario), joint_col => mean => :joint, redundancy_col => mean => :redundancy_aware, no_cover_col => mean => :no_cover)

            scenarios = reverse(filter(s -> s in summary.scenario, SCENARIO_ORDER))
            joint_values = [summary[summary.scenario .== s, :joint][1] for s in scenarios]
            redundancy_values = [summary[summary.scenario .== s, :redundancy_aware][1] for s in scenarios]
            no_cover_values = [summary[summary.scenario .== s, :no_cover][1] for s in scenarios]

            y = collect(eachindex(scenarios))
            show_scenario_labels = panel_idx in (1, 4)
            scenario_ticks = show_scenario_labels ? scenarios : fill("", length(scenarios))

            groupedbar!(p, y, hcat(joint_values, redundancy_values, no_cover_values); bar_position=:dodge, orientation=:horizontal, ylims=(0.5, length(scenarios) + 0.5), yticks=(y, scenario_ticks), label=["Joint risk probability" "Redundancy-aware risk score" "No-cover probability"], color=["#DD82B9" "#A07ECC" "#79B8A9"])

            for (i, (v1, v2, v3)) in enumerate(zip(joint_values, redundancy_values, no_cover_values))
                isfinite(v1) && annotate!(p, min(v1 + 0.01, 1.04), y[i] - 0.27, text(round(v1, digits=2), 12, :left))
                isfinite(v2) && annotate!(p, min(v2 + 0.01, 1.04), y[i], text(round(v2, digits=2), 12, :left))
                isfinite(v3) && annotate!(p, min(v3 + 0.01, 1.04), y[i] + 0.27, text(round(v3, digits=2), 12, :left))
            end
        else
            plot!(p; ylims=(0, 1), yticks=false)
            annotate!(p, 0.5, 0.5, text("No data", 12))
        end

        push!(panels, p)
    end

    # Legend-only sixth panel
    p_legend = plot(; framestyle=:none, grid=false, xaxis=false, yaxis=false, legend=(0.3, 0.45), legendfontsize=15, background_color=:white)
    scatter!(p_legend, [NaN], [NaN]; label="No-cover probability", markershape=:rect, markersize=10, markercolor="#79B8A9", markerstrokecolor="#79B8A9")
    scatter!(p_legend, [NaN], [NaN]; label="Redundancy-aware risk score", markershape=:rect, markersize=10, markercolor="#A07ECC", markerstrokecolor="#A07ECC")
    scatter!(p_legend, [NaN], [NaN]; label="Joint risk probability", markershape=:rect, markersize=10, markercolor="#DD82B9", markerstrokecolor="#DD82B9")

    push!(panels, p_legend)

    # Arrange six panels in 3 columns and 2 rows
    p_all = plot(panels...; layout=grid(2, 3), size=(2200, 1100), bottom_margin=4mm, margin=0mm)

    # modify the margins of each subplot to reduce whitespace and improve alignment
    # Left margins
    plot!(p_all; left_margin=0mm, subplot=1)
    plot!(p_all; left_margin=-8mm, subplot=2)
    plot!(p_all; left_margin=-12mm, subplot=3)
    plot!(p_all; left_margin=0mm, subplot=4)
    plot!(p_all; left_margin=-8mm, subplot=5)
    plot!(p_all; left_margin=-12mm, subplot=6)

    # Right margins
    plot!(p_all; right_margin=0mm, subplot=1)
    plot!(p_all; right_margin=-10mm, subplot=2)
    plot!(p_all; right_margin=0mm, subplot=3)
    plot!(p_all; right_margin=0mm, subplot=4)
    plot!(p_all; right_margin=-10mm, subplot=5)
    plot!(p_all; right_margin=0mm, subplot=6)

    # Vertical spacing
    for i in 1:3
        plot!(p_all; bottom_margin=3mm, subplot=i)
        plot!(p_all; top_margin=0mm, subplot=i+3)
    end

    filename = "fire_flood_risk_comparison_by_state_1_year.png"
    savefig(p_all, joinpath(PLOT_PAPER_DIR, filename))

    @info "Saved combined fire and flood risk comparison plot" PLOT_PAPER_DIR
    return nothing
end

"""
    save_geographic_risk_comparison_maps(results::AbstractDataFrame; facilities=facility_coordinates)
Saves geographic maps comparing the combined risk probability and coverage-aware risk probability for each deployment scenario in the results DataFrame. 
It compares side by side for each metric.
Used within the paper to present the results of the geographic risk comparison analysis.
"""
function save_geographic_risk_comparison_maps(df::AbstractDataFrame; facilities=facility_coordinates)
    state = "NSW"
    analysis_period_years = 1

    required = [:facility_id, :state, :scenario, :analysis_period_years, :fire_joint_risk_probability, :fire_redundancy_aware_risk_score, :flood_joint_risk_probability, :flood_redundancy_aware_risk_score, :no_coverage_probability]
    missing_cols = setdiff(required, propertynames(df))
    isempty(missing_cols) || error("Missing required columns: $(join(string.(missing_cols), ", "))")

    uppercase(state) in keys(STATE_HAZARDS) || error("No hazards configured for state $state.")

    d = DataFrame(df)
    d.state = uppercase.(strip.(string.(d.state)))
    d.scenario = strip.(string.(d.scenario))
    d.analysis_period_years = Int.(d.analysis_period_years)
    filter!(r -> r.analysis_period_years == analysis_period_years, d)

    if isempty(d)
        @warn "No results available for the $(analysis_period_years)-year analysis period."
        return nothing
    end

    state = uppercase(state)
    state_data = filter(:state => ==(state), d)

    if isempty(state_data)
        @warn "No results available for state $state."
        return nothing
    end

    scenarios = [s for s in SCENARIO_ORDER if s in state_data.scenario]
    isempty(scenarios) && error("No coverage scenarios available for $state.")

    hazards = STATE_HAZARDS[state]

    if !(:latitude in propertynames(state_data) && :longitude in propertynames(state_data))
        coord_cols = [:facility_id, :latitude, :longitude]
        coords = unique(select(facilities, coord_cols), :facility_id)
        state_data = leftjoin(state_data, coords; on=:facility_id)
    end

    :latitude in propertynames(state_data) || error("Missing latitude column.")
    :longitude in propertynames(state_data) || error("Missing longitude column.")

    to_float(x) = ismissing(x) || isnothing(x) ? NaN : x isa Real ? Float64(x) : something(tryparse(Float64, strip(string(x))), NaN)
    foreach(col -> state_data[!, col] = to_float.(state_data[!, col]), (:latitude, :longitude))
    filter!(r -> isfinite(r.latitude) && isfinite(r.longitude) && -90 <= r.latitude <= 90 && -180 <= r.longitude <= 180, state_data)

    if isempty(state_data)
        @warn "No valid facility coordinates available for $state."
        return nothing
    end

    boundary = load_state_boundary(Symbol(state))
    boundary === nothing && error("No state boundary configured for $state.")

    for hazard in hazards
        metrics = [
            (Symbol("$(hazard)_joint_risk_probability"), "Joint risk probability"),
            (Symbol("$(hazard)_redundancy_aware_risk_score"), "Redundancy-aware risk score"),
            (:no_coverage_probability, "No coverage probability")
        ]

        for scenario in scenarios
            sub = filter(:scenario => ==(scenario), state_data)
            isempty(sub) && continue

            d_scenario = unique(select(sub, vcat([:facility_id, :latitude, :longitude], first.(metrics))), :facility_id)
            foreach(col -> d_scenario[!, col] = to_float.(d_scenario[!, col]), first.(metrics))

            xmin, xmax = extrema(d_scenario.longitude)
            ymin, ymax = extrema(d_scenario.latitude)
            xpad, ypad = max((xmax - xmin) * 0.05, 0.05), max((ymax - ymin) * 0.05, 0.05)
            xmin, xmax, ymin, ymax = xmin - xpad, xmax + xpad, ymin - ypad, ymax + ypad

            panels = Plots.Plot[]

            for (i, (metric, label)) in enumerate(metrics)
                dm = filter(r -> isfinite(r[metric]) && 0 <= r[metric] <= 1, d_scenario)

                p = plot(; xlabel=i == 2 ? "Longitude (°)" : "", ylabel=i == 1 ? "Latitude (°)" : "", yticks=i == 1 ? :auto : false, title=label, title_location=:center, xlims=(xmin, xmax), ylims=(ymin, ymax), aspect_ratio=:equal, legend=false, grid=true, framestyle=:box, margin=0Plots.mm)

                add_geojson_boundary!(p, boundary; color=:grey50, linewidth=0.8, fill_color=:lightgrey, fill_alpha=0.25)

                if !isempty(dm)
                    scatter!(p, dm.longitude, dm.latitude; marker_z=dm[!, metric], color=:viridis, clims=(0, 1), markersize=5, markerstrokewidth=0.3, markerstrokecolor=:black, colorbar=false, label=false)
                else
                    annotate!(p, 0.5, 0.5, text("No valid data", 12))
                end

                push!(panels, p)
            end

            # Shared colorbar panel
            cb = plot([0.0], [0.0]; seriestype=:scatter, marker_z=[0.0], color=:viridis, clims=(0, 1), markersize=0, markeralpha=0, colorbar=true, colorbar_title="Probability", xlims=(0, 1), ylims=(0, 1), xticks=false, yticks=false, framestyle=:none, grid=false, legend=false, margin=0Plots.mm)

            colorbar_width = 0.11
            map_width = (1 - colorbar_width) / 3
            p_all = plot(panels..., cb; layout=Plots.grid(1, 4; widths=[map_width, map_width, map_width, colorbar_width]), size=(2800, 800), bottom_margin=4Plots.mm, left_margin=50Plots.mm)

            # modify the margins of each subplot to reduce whitespace and improve alignment
            # Left margins
            plot!(p_all; left_margin=20Plots.mm, subplot=1)
            plot!(p_all; left_margin=-1Plots.mm, subplot=2)
            plot!(p_all; left_margin=-1Plots.mm, subplot=3)
            plot!(p_all; left_margin=-1Plots.mm, subplot=4)

            # Right margins
            plot!(p_all; right_margin=0Plots.mm, subplot=1)
            plot!(p_all; right_margin=0Plots.mm, subplot=2)
            plot!(p_all; right_margin=-10Plots.mm, subplot=3)
            plot!(p_all; right_margin=-10Plots.mm, subplot=4)

            for i in 1:4
                plot!(p_all; bottom_margin=3Plots.mm, subplot=i)
                plot!(p_all; top_margin=0Plots.mm, subplot=i)
            end

            filename = "$(lowercase(state))_$(lowercase(hazard))_$(replace(scenario, " " => "_"))_$(analysis_period_years)_year_geographic_risk_comparison.png"
            savefig(p_all, joinpath(PLOT_PAPER_DIR, filename))

            @info "Saved geographic risk comparison map" state hazard scenario analysis_period_years filename
        end
    end

    @info "Saved geographic risk comparison maps" state scenarios hazards analysis_period_years
    return nothing
end

"""
    save_redundancy_analysis_plots(df::AbstractDataFrame)
Saves plots comparing the mean effective asset count and the proportion of facilities achieving at least three effective assets by deployment scenario and hazard for the 1-year analysis period.
"""
function save_redundancy_analysis_plots(df::AbstractDataFrame)
    required = [:state, :scenario, :analysis_period_years, :num_candidate_assets, :fire_effective_asset_count, :flood_effective_asset_count, :fire_redundancy_risk, :flood_redundancy_risk]
    missing_cols = setdiff(required, propertynames(df))
    isempty(missing_cols) || error("Missing required columns: $(join(string.(missing_cols), ", "))")

    d = DataFrame(df)
    d.state = uppercase.(strip.(string.(d.state)))
    d.scenario = titlecase.(strip.(string.(d.scenario)))
    d.analysis_period_years = Int.(d.analysis_period_years)
    filter!(r -> r.analysis_period_years == 1 && r.num_candidate_assets > 0, d)

    if isempty(d)
        @warn "No facilities with candidate assets available for redundancy analysis."
        return nothing
    end

    hazards = ("fire", "flood")
    hazard_colours = ["#DD82B9", "#A07ECC"]
    hazard_labels = ["Fire", "Flood"]
    scenarios = [s for s in SCENARIO_ORDER if s in d.scenario]
    safe_mean = x -> (v=Float64.(collect(skipmissing(x))); isempty(v) ? missing : mean(v))
    figures = Dict{String,Plots.Plot}()

    # Figure 1: Mean hazard-dependent effective asset count.
    count_cols = [:fire_effective_asset_count, :flood_effective_asset_count]
    count_summary = combine(groupby(d, :scenario), [col => safe_mean => Symbol("mean_$(col)") for col in count_cols]...)
    count_values = hcat([count_summary[count_summary.scenario .== s, :mean_fire_effective_asset_count][1] for s in scenarios], [count_summary[count_summary.scenario .== s, :mean_flood_effective_asset_count][1] for s in scenarios])
    p1 = groupedbar(1:length(scenarios), count_values; bar_position=:dodge, orientation=:vertical, xticks=(1:length(scenarios), scenarios), ylabel="Mean effective asset count", xlabel="Deployment scenario", label=reshape(hazard_labels, 1, 2), color=reshape(hazard_colours, 1, 2), ylims=(0, max(3.5, maximum(skipmissing(vec(count_values))) * 1.1)), legend=:topright, grid=:y, size=(1800, 650), bottom_margin=10Plots.mm, left_margin=10Plots.mm)
    hline!(p1, [3]; color=:black, linestyle=:dash, linewidth=1.5, label="Redundancy threshold (3)")
    savefig(p1, joinpath(PLOT_PAPER_DIR, "redundancy_effective_asset_count_1_year.png"))
    figures["effective_asset_count"] = p1

    # Figure 3: Proportion of facilities achieving at least three effective assets.
    threshold = 3.0
    proportions = DataFrame(scenario=String[], hazard=String[], proportion=Float64[], num_facilities=Int[])
    for scenario in scenarios, (j, hazard) in enumerate(hazards)
        col = count_cols[j]
        values = Float64.(collect(skipmissing(d[d.scenario .== scenario, col])))
        isempty(values) && continue
        push!(proportions, (scenario, hazard, mean(values .>= threshold), length(values)))
    end
    proportion_values = hcat([proportions[proportions.scenario .== s, :proportion][findfirst(==("fire"), proportions[proportions.scenario .== s, :hazard])] for s in scenarios], [proportions[proportions.scenario .== s, :proportion][findfirst(==("flood"), proportions[proportions.scenario .== s, :hazard])] for s in scenarios])
    p3 = groupedbar(1:length(scenarios), proportion_values .* 100; bar_position=:dodge, xticks=(1:length(scenarios), scenarios), ylabel="threshold met (%)", xlabel="Deployment scenario", label=reshape(hazard_labels, 1, 2), color=reshape(hazard_colours, 1, 2), ylims=(0, 76), legend=:topright, grid=:y, size=(1800, 650), bottom_margin=10Plots.mm, left_margin=10Plots.mm)
    savefig(p3, joinpath(PLOT_PAPER_DIR, "redundancy_threshold_achievement_1_year.png"))
    figures["redundancy_threshold_achievement"] = p3

    # Figure 2: Distribution of hazard-dependent redundancy risk.
    risk_cols = [:fire_redundancy_risk, :flood_redundancy_risk]
    p2 = plot(; xlabel="Deployment scenario", ylabel="Redundancy risk score", xticks=(1:length(scenarios), scenarios), xlims=(0.5, length(scenarios) + 0.5), ylims=(0, 1.05), legend=:bottomright, grid=:y, size=(1600, 650), bottom_margin=10Plots.mm, left_margin=8Plots.mm)
    for (j, hazard) in enumerate(hazards)
        col = risk_cols[j]
        for (i, scenario) in enumerate(scenarios)
            values = filter(isfinite, Float64.(collect(skipmissing(d[d.scenario .== scenario, col]))))
            isempty(values) && continue
            boxplot!(p2, fill(i + (j == 1 ? -0.16 : 0.16), length(values)), values; bar_width=0.28, color=hazard_colours[j], label=i == 1 ? hazard_labels[j] : "", outliers=true)
        end
    end
    savefig(p2, joinpath(PLOT_PAPER_DIR, "redundancy_risk_distributions_1_year.png"))
    figures["redundancy_risk_distribution"] = p2


    @info "Saved three redundancy analysis figures" PLOT_PAPER_DIR num_facilities=nrow(d) scenarios=scenarios
    return figures
end

"""
    save_distance_coverage_plot(; max_distance_m=12500.0, step_m=5.0)
Saves a plot of coverage probability versus distance from the evacuation facility to the telecom asset for each deployment scenario, with vertical lines indicating the nominal distance for each scenario.
"""
function save_distance_coverage_plot(; max_distance_m=12500.0, step_m=5.0)
    distances = collect(0.0:step_m:max_distance_m)

    p = plot(; xlabel="Distance from evacuation facility to telecom asset (m)", ylabel="Coverage probability", title="Distance versus coverage probability", xlims=(0, max_distance_m), xticks=0:2500:max_distance_m, xformatter=:plain, ylims=(0, 1), legend=:topright, size=(1800, 800), margin=10Plots.mm)

    hline!(p, [MIN_COVERAGE_PROBABILITY]; label="Minimum candidate coverage probability", linestyle=:dot, color=:black, linewidth=1.5)

    for (scenario, scenario_config) in COVERAGE_SCENARIOS
        config = CoverageScenario(scenario, scenario_config.nominal_distance_m, scenario_config.pathloss_exponent, scenario_config.shadow_fading_std_db)
        nominal = config.nominal_distance_m
        probabilities = coverage_probability.(distances, Ref(config))
        plot!(p, distances, probabilities; label=scenario, linewidth=2.75)
        nominal <= max_distance_m && vline!(p, [nominal]; label="$(scenario) nominal distance", linestyle=:dash, alpha=0.65, linewidth=1.5)
    end

    savefig(p, joinpath(PLOT_PAPER_DIR, "distance_vs_coverage_probability.png"))
    return p
end

function run_latex()
    results = load_results(include_telco=true)
    df = results.facilities
    telco_df = results.telco_assets
    save_geographic_risk_comparison_maps(df)
    save_accessibility_latex_table(df)
    save_distance_coverage_plot()
    save_baseline_coverage_figures(df)
    save_hazard_failure_figures((facilities=df, telco_assets=telco_df))
    save_continuity_cutoff_figures(df)
    save_state_risk_comparison_plots(df)
    save_redundancy_analysis_plots(df)

end

run_latex()