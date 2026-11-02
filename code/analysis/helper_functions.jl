struct PolygonSpatialIndex{T,P}
    tree::T
    polygons::P
end

struct EarthquakeContour
    geometry
    pga::Float64
end

struct LineSpatialIndex
    contours::Vector{EarthquakeContour}
end

function build_line_index(contours::Vector{EarthquakeContour})
    isempty(contours) && error("Cannot build earthquake line index: no contours provided")
    return LineSpatialIndex(contours)
end

# ============================================================
# GENERIC HELPERS
# ============================================================

# EPSG:9473 is GDA2020 / Australian Albers, suitable for metre-based distance calculations across NSW, VIC and SA. GeoJSON coordinates are assumed to be longitude/latitude in WGS84 (EPSG:4326).
const WGS84_TO_AU_ALBERS = Proj.Transformation("EPSG:4326", "EPSG:9473"; always_xy=true)

_json(path::AbstractString) = JSON3.read(read(path, String))

_get(obj, key::Symbol, default=nothing) = hasproperty(obj, key) ? getproperty(obj, key) : default
_get_or(obj, key::Symbol, default) = something(_get(obj, key), default)

_number_or_nothing(::Nothing) = nothing
_number_or_nothing(x) = (v = tryparse(Float64, strip(string(x))); v !== nothing && isfinite(v) ? v : nothing)

_carrier_string(value) = string(value)
_carrier_string(value::AbstractVector) = join(_carrier_string.(value), ';')

_records(raw) = hasproperty(raw, :features) ? raw.features : raw
_properties(site) = _get(site, :properties, site)

_source_id(feature, props, i) = string(_get_or(feature, :id, _get_or(props, :fid, i)))
_facility_name(props, id) = string(_get_or(props, :title, _get_or(props, :lrr, _get_or(props, :name, "Facility $id"))))

_valid_coordinates(coords) = coords !== nothing && length(coords) >= 2 && all(x -> _number_or_nothing(x) !== nothing, coords[1:2])

# ============================================================
# LOAD FACILITY AND SITE DATA
# ============================================================

function _site_coordinates(site, props)
    coords = _get(site, :geometry) === nothing ? nothing : site.geometry.coordinates

    _valid_coordinates(coords) || (coords = nothing)

    lon = something(_number_or_nothing(_get(props, :longitude, nothing)), coords === nothing ? nothing : Float64(coords[1]))
    lat = something(_number_or_nothing(_get(props, :latitude, nothing)), coords === nothing ? nothing : Float64(coords[2]))

    return lat, lon
end

"""
    load_telco_sites(path::AbstractString=TELCO_SITES_PATH)

Load telecom site data from a JSON file and return a DataFrame with the relevant information.
"""
function load_telco_sites(path::AbstractString=TELCO_SITES_PATH)
    records = _records(_json(path))
    rows = NamedTuple[]
    sizehint!(rows, length(records))

    for (i, site) in enumerate(records)
        props = _properties(site)
        lat, lon = _site_coordinates(site, props)
        (lat === nothing || lon === nothing) && continue

        id = string(_get_or(props, :site_id, _get_or(site, :id, i)))

        push!(rows, (
            asset_id=id,
            latitude=lat,
            longitude=lon,
            name=string(_get(props, :name, "")),
            state=_state_code(_get(props, :state, "")),
            carriers=_carrier_string(_get(props, :carrier, nothing)),
        ))
    end

    isempty(rows) && error("No telecom sites with valid coordinates were loaded from $path")

    df = DataFrame(rows)
    unique!(df, :asset_id)
    return df
end

"""
    load_evacuation_facilities(path::AbstractString, state_code::AbstractString)

Load evacuation facility data from a GeoJSON file and return a DataFrame with the relevant information.
"""
function load_evacuation_facilities(path::AbstractString, state_code::AbstractString)
    data = _json(path)
    hasproperty(data, :features) || error("Expected a GeoJSON FeatureCollection in $path")

    state = _state_code(state_code)
    rows = NamedTuple[]
    sizehint!(rows, length(data.features))

    for (i, feature) in enumerate(data.features)
        coords = feature.geometry.coordinates
        _valid_coordinates(coords) || continue

        lon, lat = Float64(coords[1]), Float64(coords[2])
        props = feature.properties
        source_id = _source_id(feature, props, i)

        push!(rows, (
            facility_id="$(state)-$(source_id)",
            source_id=source_id,
            name=_facility_name(props, source_id),
            state=state,
            latitude=lat,
            longitude=lon,
        ))
    end

    isempty(rows) && error("No point evacuation facilities loaded from $path")

    df = DataFrame(rows)
    unique!(df, :facility_id)
    return df
end