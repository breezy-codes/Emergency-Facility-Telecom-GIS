using Distributions
using DataFrames
using Proj
using GeoInterface
using LibSpatialIndex
using LibGEOS
using JSON3
using CSV
using Statistics
using Plots
using StatsPlots
using Measures

include("config.jl")
include("analysis/helper_functions.jl")

include("analysis/probability_model.jl")
include("analysis/spatial_analysis.jl")

include("analysis/plot_results.jl")
include("analysis/paper_results.jl")

# The following 2 lines prevent it from showing popup windows for each plot.
ENV["GKSwstype"] = "nul"  # Use the GR backend for plotting
gr()  # Set the GR backend for plotting


"""
    analyse_facility(facility_id, assets::AbstractDataFrame, asset_exposure_columns::AbstractDict, facility_hazard_exposures::AbstractDict, scenario::CoverageScenario; config::ModelConfig=ModelConfig(), analysis_period_years::Integer=1, asset_conditional_failure_probabilities::AbstractDict, facility_conditional_failure_probabilities::AbstractDict)

Analyse the risk for a single facility given its associated assets, hazard exposures, and a telecommunications coverage scenario. Returns a named tuple containing the analysis results.
"""
function analyse_facility(facility_id, assets::AbstractDataFrame, asset_exposure_columns::AbstractDict, facility_hazard_exposures::AbstractDict, scenario::CoverageScenario; config::ModelConfig=ModelConfig(), analysis_period_years::Integer=1, asset_conditional_failure_probabilities::AbstractDict, facility_conditional_failure_probabilities::AbstractDict)
    analysis_period_years > 0 || throw(ArgumentError("Analysis period must be positive"))

    candidates = get_candidate_assets(assets, scenario; config=config)
    p_cov = normal_coverage_probability(candidates, scenario)
    p_no_cov = facility_no_coverage_probability(candidates, scenario)

    hazard_asset_failures = Dict(lowercase(strip(string(hazard))) => [single_hazard_asset_failure_probability(row[column], asset_conditional_failure_probabilities[lowercase(strip(string(hazard)))], string(hazard); analysis_period_years=analysis_period_years) for row in eachrow(candidates)] for (hazard, column) in asset_exposure_columns)

    continuity = Dict(hazard => (isempty(failures) ? 0.0 : 1.0 - prod(1.0 .- [coverage_probability(row.distance, scenario) * (1.0 - failure_probability) for (row, failure_probability) in zip(eachrow(candidates), failures)])) for (hazard, failures) in hazard_asset_failures)

    facility_failures = Dict(lowercase(strip(string(hazard))) => hazard_failure_probability(occurrence_probability, facility_conditional_failure_probabilities[lowercase(strip(string(hazard)))], analysis_period_years) for (hazard, occurrence_probability) in facility_hazard_exposures)

    asset_failure_means = Dict(hazard => (isempty(failures) ? missing : mean(failures)) for (hazard, failures) in hazard_asset_failures)

    cutoff_probabilities = Dict(hazard => 1.0 - probability for (hazard, probability) in continuity)

    joint_risks = Dict(hazard => facility_failures[hazard] * cutoff_probabilities[hazard] for hazard in keys(facility_failures))

    effective_asset_counts = Dict(hazard => (isempty(candidates) ? missing : sum((coverage_probability(row.distance, scenario) * (1.0 - failure_probability) for (row, failure_probability) in zip(eachrow(candidates), get(hazard_asset_failures, hazard, Float64[]))); init=0.0)) for hazard in keys(facility_failures))

    redundancy_risks = Dict(hazard => (ismissing(effective_count) ? missing : max(0.0, 1.0 - effective_count / 3.0)) for (hazard, effective_count) in effective_asset_counts)

    redundancy_aware_risks = Dict(hazard => (ismissing(redundancy_risks[hazard]) ? missing : 1.0 - (1.0 - facility_failures[hazard]) * (1.0 - redundancy_risks[hazard])) for hazard in keys(facility_failures))
    p_cont = Dict(hazard => probability for (hazard, probability) in continuity)

    return (
        facility_id=facility_id,
        scenario=scenario.name,
        analysis_period_years=analysis_period_years,
        num_candidate_assets=nrow(candidates),
        normal_coverage_probability=p_cov,
        no_coverage_probability=p_no_cov,
        fire_continuity_probability=get(p_cont, "fire", missing),
        flood_continuity_probability=get(p_cont, "flood", missing),
        fire_cutoff_probability=get(cutoff_probabilities, "fire", missing),
        flood_cutoff_probability=get(cutoff_probabilities, "flood", missing),
        fire_facility_failure_probability=get(facility_failures, "fire", missing),
        flood_facility_failure_probability=get(facility_failures, "flood", missing),
        fire_asset_failure_probability=get(asset_failure_means, "fire", missing),
        flood_asset_failure_probability=get(asset_failure_means, "flood", missing),
        fire_effective_asset_count=get(effective_asset_counts, "fire", missing),
        flood_effective_asset_count=get(effective_asset_counts, "flood", missing),
        fire_redundancy_risk=get(redundancy_risks, "fire", missing),
        flood_redundancy_risk=get(redundancy_risks, "flood", missing),
        fire_joint_risk_probability=get(joint_risks, "fire", missing),
        flood_joint_risk_probability=get(joint_risks, "flood", missing),
        fire_redundancy_aware_risk_score=get(redundancy_aware_risks, "fire", missing),
        flood_redundancy_aware_risk_score=get(redundancy_aware_risks, "flood", missing)
    )
end