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