# ============================================================
# MODEL STRUCTURES
# ============================================================

"""
Coverage scenario defined by its nominal coverage distance, path-loss exponent and shadow-fading standard deviation.
Distances are in metres and shadow fading is in dB.
"""
struct CoverageScenario
    name::String
    nominal_distance_m::Float64
    pathloss_exponent::Float64
    shadow_fading_std_db::Float64

    function CoverageScenario(name::AbstractString, nominal_distance_m::Real, pathloss_exponent::Real, shadow_fading_std_db::Real)
        nominal_distance_m > 0 || throw(ArgumentError("nominal_distance_m must be positive"))
        pathloss_exponent > 0 || throw(ArgumentError("pathloss_exponent must be positive"))
        shadow_fading_std_db > 0 || throw(ArgumentError("shadow_fading_std_db must be positive"))
        new(String(name), Float64(nominal_distance_m), Float64(pathloss_exponent), Float64(shadow_fading_std_db))
    end
end

"""
    coverage_scenario(name)

Create a CoverageScenario using a named entry in COVERAGE_SCENARIOS.
"""
function coverage_scenario(name::AbstractString)
    key = titlecase(strip(name))
    haskey(COVERAGE_SCENARIOS, key) || throw(ArgumentError("Unknown coverage scenario: $name"))

    params = COVERAGE_SCENARIOS[key]
    return CoverageScenario(key, params.nominal_distance_m, params.pathloss_exponent, params.shadow_fading_std_db)
end

scenarios = [(name, coverage_scenario(name)) for name in SCENARIO_ORDER]

"""
Configuration for the probabilistic telecommunications resilience model.
Values are populated from the constants defined in the configuration section.
"""
struct ModelConfig
    minimum_coverage_probability::Float64

    function ModelConfig()
        0 < MIN_COVERAGE_PROBABILITY < 1 || throw(ArgumentError("MIN_COVERAGE_PROBABILITY must be in (0, 1)"))
        new(MIN_COVERAGE_PROBABILITY)
    end
end

const MODEL_CONFIG = ModelConfig()

"""
    coverage_probability(distance_m, scenario)

Calculate telecommunications coverage probability using a log-distance
path-loss model with log-normal shadowing.

pₑₜ(s) = Φ(10nₛ log₁₀(Dₛᵐᵒᵐ / dₑₜ) / σₛ).
"""
function coverage_probability(distance_m::Real, scenario::CoverageScenario)
    distance_m >= 0 || throw(ArgumentError("Distance cannot be negative"))
    iszero(distance_m) && return 1.0

    z = 10 * scenario.pathloss_exponent * log10(scenario.nominal_distance_m / distance_m) / scenario.shadow_fading_std_db

    return cdf(Normal(), z)
end

function _coverage_distance_threshold(scenario::CoverageScenario, config::ModelConfig)
    p = config.minimum_coverage_probability
    0.0 < p < 1.0 || throw(ArgumentError("minimum_coverage_probability must be between 0 and 1"))

    z = quantile(Normal(), p)
    return scenario.nominal_distance_m * 10.0^(-scenario.shadow_fading_std_db * z / (10 * scenario.pathloss_exponent))
end

"""
    usable_coverage_probability(p_et, q_th)

The probability that a telecommunications asset is usable under the specified hazard, given its normal-condition coverage probability pₑₜ(s) and the conditional failure probability qₜₕ of the asset under the hazard. The usable coverage probability is defined as pₑₜ(s) * (1 - qₜₕ).
"""
usable_coverage_probability(p_et::Real, q_th::Real) = (0 <= p_et <= 1 && 0 <= q_th <= 1) ? Float64(p_et * (1 - q_th)) : throw(ArgumentError("Probabilities must be in [0, 1]"))

"""
    get_candidate_assets(assets, scenario; config=ModelConfig())

Filter rows using pₑₜ(s) ≥ ε. `assets` must contain `asset_id`, `distance`, and `hazard_exposure`; distances are in metres. Returns a copy with a `coverage_probability` column added.
"""
function get_candidate_assets(assets::AbstractDataFrame, scenario::CoverageScenario; config::ModelConfig=ModelConfig())
    required = (:asset_id, :distance)
    missing = filter(c -> !(c in propertynames(assets)), required)
    isempty(missing) || throw(ArgumentError("Missing asset columns: $(collect(missing))"))
    result = DataFrame(assets)
    result.coverage_probability = [coverage_probability(d, scenario) for d in result.distance]
    filter!(row -> row.coverage_probability >= config.minimum_coverage_probability, result)
    return result
end

function _validate_hazard_probability(probability::Real, hazard_type::AbstractString, probability_type::AbstractString)
    lowercase(strip(hazard_type)) in HAZARDS || throw(ArgumentError("Unsupported hazard type '$hazard_type'"))
    0 <= probability <= 1 || throw(ArgumentError("$probability_type must be in [0, 1]"))
    return Float64(probability)
end

"""
    hazard_failure_probability(occurrence_probability, conditional_failure_probability, analysis_period_years)

Calculate the N-year failure probability of a facility or asset due to a hazard, given the hazard occurrence probability, the conditional failure probability of the facility or asset given the hazard, and the analysis period in years. The formula is:
p_failure = 1 - (1 - p_occurrence * p_conditional_failure)^N
"""
function hazard_failure_probability(occurrence_probability::Real, conditional_failure_probability::Real, analysis_period_years::Integer)
    analysis_period_years > 0 || throw(ArgumentError("Analysis period must be positive"))
    p = Float64(occurrence_probability)
    q = Float64(conditional_failure_probability)
    0.0 <= p <= 1.0 || throw(ArgumentError("Hazard occurrence probability must be in [0, 1]"))
    0.0 <= q <= 1.0 || throw(ArgumentError("Conditional failure probability must be in [0, 1]"))
    return clamp(1.0 - (1.0 - p * q)^analysis_period_years, 0.0, 1.0)
end

"""
    single_hazard_asset_failure_probability(occurrence_probability, conditional_failure_probability, hazard_type; analysis_period_years=1)

Calculate the N-year failure probability of an asset due to a single hazard, given the hazard occurrence probability, the conditional failure probability of the asset given the hazard, and the analysis period in years.
"""
function single_hazard_asset_failure_probability(occurrence_probability::Real, conditional_failure_probability::Real, hazard_type::AbstractString; analysis_period_years::Integer=1)
    p = _validate_hazard_probability(occurrence_probability, hazard_type, "Hazard occurrence probability")
    return hazard_failure_probability(p, conditional_failure_probability, analysis_period_years)
end

"""
    multi_hazard_asset_failure_probabilities(exposures, conditional_failure_probabilities; analysis_period_years=1)

Calculate the N-year failure probabilities of an asset due to multiple hazards, given a dictionary of hazard occurrence probabilities and a dictionary of conditional failure probabilities for each hazard, and the analysis period in years.
Returns a dictionary mapping hazard names to failure probabilities.
"""
function multi_hazard_asset_failure_probabilities(exposures::AbstractDict, conditional_failure_probabilities::AbstractDict; analysis_period_years::Integer=1)
    analysis_period_years > 0 || throw(ArgumentError("Analysis period must be positive"))

    return Dict(
        lowercase(strip(string(hazard))) => single_hazard_asset_failure_probability(
            probability,
            conditional_failure_probabilities[lowercase(strip(string(hazard)))],
            string(hazard);
            analysis_period_years=analysis_period_years
        )
        for (hazard, probability) in exposures
    )
end

"""
    normal_coverage_probability(assets, scenario)

Calculate normal-condition coverage using the candidate assets and coverage scenario.
"""
normal_coverage_probability(assets::AbstractDataFrame, scenario::CoverageScenario) =
    isempty(assets) ? 0.0 :
    1.0 - prod(1.0 .- coverage_probability.(assets.distance, Ref(scenario)))

"""
    facility_failure_probability(hazard_type, config::ModelConfig=MODEL_CONFIG)

Calculate the unconditional failure probability of a facility due to a hazard, given the hazard type and model configuration. The failure probability is based on the conditional failure probability of the facility given the hazard and the hazard occurrence probability.
"""
function facility_continuity_probability(assets::AbstractDataFrame, asset_exposure_columns::AbstractDict, scenario::CoverageScenario; config::ModelConfig=ModelConfig(), analysis_period_years::Integer=1)
    analysis_period_years > 0 || throw(ArgumentError("Analysis period must be positive"))

    hazards = lowercase.(strip.(string.(collect(keys(asset_exposure_columns)))))
    isempty(assets) && return Dict(hazard => 0.0 for hazard in hazards)

    continuity = Dict{String,Float64}()

    for (hazard, column) in asset_exposure_columns
        hazard_name = lowercase(strip(string(hazard)))
        hazard_name in HAZARDS || throw(ArgumentError("Unsupported hazard type '$hazard'"))

        usable_probabilities = Float64[]

        for row in eachrow(assets)
            ismissing(row[column]) && continue

            p_hazard = _validate_hazard_probability(row[column], hazard_name, "Hazard occurrence probability")
            p_hazard == 0.0 && continue

            q_n = hazard_failure_probability(p_hazard, asset_failure_probability(hazard_name, nothing, config), analysis_period_years)
            p_coverage = coverage_probability(row.distance, scenario)

            push!(usable_probabilities, p_coverage * (1.0 - q_n))
        end

        continuity[hazard_name] = isempty(usable_probabilities) ? 1.0 : 1.0 - prod(1.0 .- usable_probabilities)
    end

    return continuity
end

"""
    facility_cutoff_probability(assets, asset_exposure_columns, scenario; config=ModelConfig())

Calculate the probability that a facility experiences a telecommunications cutoff due to hazards, given the candidate assets, their hazard exposure columns, and the coverage scenario. The cutoff probability is defined as 1 - continuity probability, where continuity probability is the probability that at least one asset remains usable under each hazard.
"""
function facility_cutoff_probability(assets::AbstractDataFrame, asset_exposure_columns::AbstractDict, scenario::CoverageScenario; config::ModelConfig=ModelConfig())
    return 1.0 - facility_continuity_probability(assets, asset_exposure_columns, scenario; config=config)
end


"""
    facility_risk_probability(assets, asset_exposure_columns, facility_hazard_exposures, scenario; config=ModelConfig(), analysis_period_years=1)

Calculate the risk probabilities of a facility due to hazards, given the candidate assets, their hazard exposure columns, the facility's hazard exposures, and the coverage scenario. The risk probability is defined as the product of the facility failure probability and the cutoff probability for each hazard.
"""
function facility_risk_probability(assets::AbstractDataFrame, asset_exposure_columns::AbstractDict, facility_hazard_exposures::AbstractDict, scenario::CoverageScenario; config::ModelConfig=ModelConfig(), analysis_period_years::Integer=1)
    analysis_period_years > 0 || throw(ArgumentError("Analysis period must be positive"))
    continuity = facility_continuity_probability(assets, asset_exposure_columns, scenario; config=config, analysis_period_years=analysis_period_years,)
    risks = Dict{String,Float64}()

    for (hazard, exposure) in facility_hazard_exposures
        hazard_name = lowercase(strip(string(hazard)))
        p_hazard = _validate_hazard_probability(exposure, hazard_name, "Hazard occurrence probability")

        a_n = hazard_failure_probability(p_hazard, facility_failure_probability(hazard_name, config), analysis_period_years,)

        p_cut = 1.0 - get(continuity, hazard_name, 0.0)
        risks[hazard_name] = a_n * p_cut
    end

    return risks
end

"""
    facility_redundancy_aware_risk_probability(assets, asset_exposure_columns, facility_hazard_exposures, scenario; config=ModelConfig(), analysis_period_years=1)

Calculate the risk probabilities of a facility due to hazards, considering redundancy in the candidate assets. The risk probability is defined as the product of the facility failure probability and the redundancy-aware cutoff probability for each hazard.
"""
function facility_redundancy_aware_risk_probability(assets::AbstractDataFrame, asset_exposure_columns::AbstractDict, facility_hazard_exposures::AbstractDict, scenario::CoverageScenario; config::ModelConfig=ModelConfig(), analysis_period_years::Integer=1)
    analysis_period_years > 0 || throw(ArgumentError("Analysis period must be positive"))
    risks = Dict{String,Union{Missing,Float64}}()
    isempty(assets) && return Dict(lowercase(strip(string(hazard))) => missing for hazard in keys(facility_hazard_exposures))

    for (hazard, exposure) in facility_hazard_exposures
        hazard_name = lowercase(strip(string(hazard)))
        p_hazard = _validate_hazard_probability(exposure, hazard_name, "Hazard occurrence probability")
        a_n = hazard_failure_probability(p_hazard, facility_failure_probability(hazard_name, config), analysis_period_years)
        n_eff = 0.0

        if haskey(asset_exposure_columns, hazard_name)
            column = asset_exposure_columns[hazard_name]
            for row in eachrow(assets)
                asset_exposure = row[column]
                ismissing(asset_exposure) && continue
                p_asset_hazard = _validate_hazard_probability(asset_exposure, hazard_name, "Asset hazard occurrence probability")
                q_n = hazard_failure_probability(p_asset_hazard, asset_failure_probability(hazard_name, config), analysis_period_years)
                n_eff += coverage_probability(row.distance, scenario) * (1.0 - q_n)
            end
        end

        redundancy_risk = max(0.0, 1.0 - n_eff / 3.0)
        risks[hazard_name] = 1.0 - (1.0 - a_n) * (1.0 - redundancy_risk)
    end

    return risks
end

"""
    facility_no_coverage_probability(assets, scenario)

Calculate the probability that a facility has no coverage due to hazards, given the candidate assets and the coverage scenario. The no-coverage probability is defined as the product of (1 - pₑₜ(s)) for all candidate assets, where pₑₜ(s) is the normal-condition coverage probability of each asset under the scenario.
"""
function facility_no_coverage_probability(assets::AbstractDataFrame, scenario::CoverageScenario)
    return prod((1.0 - coverage_probability(row.distance, scenario) for row in eachrow(assets)); init=1.0)
end