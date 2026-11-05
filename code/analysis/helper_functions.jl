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

# ============================================================
# GENERIC HELPERS
# ============================================================

# GeoJSON coordinates are assumed to be longitude/latitude in WGS84 (EPSG:4326).
# All projected spatial calculations use GDA94 / Australian Albers (EPSG:3577).
const TARGET_CRS = "EPSG:3577"
const WGS84_TO_AU_ALBERS = Proj.Transformation("EPSG:4326", TARGET_CRS; always_xy=true)

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
    isfile(path) || error("Telecom sites file not found: $path")
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

    for state in STATES
        any(==(state), df.state) || error("No telecom sites found for state $state in $path")
    end
    return df
end

"""
    load_evacuation_facilities(path::AbstractString, state_code::AbstractString)

Load evacuation facility data from a GeoJSON file and return a DataFrame with the relevant information.
"""
function load_evacuation_facilities(path::AbstractString, state_code::AbstractString)
    isfile(path) || error("Evacuation facility file not found: $path")
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

    isempty(rows) && error("No $state evacuation facilities with valid coordinates loaded from $path")

    df = DataFrame(rows)
    unique!(df, :facility_id)
    return df
end

# ============================================================
# BOUNDARY POLYGONS
# ============================================================
_project_xy(coord) = WGS84_TO_AU_ALBERS(Float64(coord[1]), Float64(coord[2]))
_geometry_type(geom) = Symbol(string(geom.type))
_boundary_polygons(geometry) = _boundary_polygons(Val(_geometry_type(geometry)), geometry.coordinates)
_boundary_polygons(::Val{:Polygon}, coords) = (coords,)
_boundary_polygons(::Val{:MultiPolygon}, coords) = coords

_ring_coordinates(ring) = ([Float64(point[1]) for point in ring], [Float64(point[2]) for point in ring])

function _plot_boundary_polygon!(p, polygon; color=:grey30, linewidth=0.8, fill_color=:lightgrey, fill_alpha=0.25)
    isempty(polygon) && return p
    exterior = first(polygon)
    length(exterior) < 5000 && return p

    lon, lat = _ring_coordinates(exterior)
    plot!(p, Shape(lon, lat); fillcolor=fill_color, fillalpha=fill_alpha, linecolor=color, linewidth=linewidth, label=false)

    for ring in Iterators.drop(polygon, 1)
        isempty(ring) && continue
        ring_lon, ring_lat = _ring_coordinates(ring)
        plot!(p, ring_lon, ring_lat; color=color, linewidth=linewidth, label=false)
    end

    return p
end

"""
    add_geojson_boundary!(p, geojson; color=:grey30, linewidth=0.8, fill_color=:lightgrey, fill_alpha=0.25)

Add the boundary polygons from a GeoJSON object to the given plot `p`. The function iterates over the features in the GeoJSON, extracts the polygon geometries, and plots them with the specified styling options. The `color`, `linewidth`, `fill_color`, and `fill_alpha` parameters control the appearance of the boundary lines and filled areas. The function returns the modified plot `p`.
"""
function add_geojson_boundary!(p, geojson; color=:grey30, linewidth=0.8, fill_color=:lightgrey, fill_alpha=0.25)
    for feature in geojson.features
        geometry = feature.geometry
        geometry === nothing && continue

        for polygon in _boundary_polygons(geometry)
            _plot_boundary_polygon!(p, polygon; color=color, linewidth=linewidth, fill_color=fill_color, fill_alpha=fill_alpha)
        end
    end

    return p
end

# ============================================================
# HAZARD RASTER LOADING
# ============================================================

function load_hazard_raster(path::AbstractString)
    isfile(path) || error("Hazard raster not found: $path")

    return ArchGDAL.read(path) do dataset
        ArchGDAL.nraster(dataset) == 1 || error("Expected a single-band raster: $path")

        band = ArchGDAL.getband(dataset, 1)
        values = permutedims(ArchGDAL.read(band))

        @info "Raster dimensions" array_size=size(values) width=ArchGDAL.width(dataset) height=ArchGDAL.height(dataset)

        size(values) == (ArchGDAL.height(dataset), ArchGDAL.width(dataset)) ||
            error("Unexpected raster array dimensions: $(size(values))")

        (
            values=values,
            geotransform=ArchGDAL.getgeotransform(dataset),
            projection=ArchGDAL.getproj(dataset),
            nodata=ArchGDAL.getnodatavalue(band),
        )
    end
end

function load_hazard_rasters(state::AbstractString)
    rasters = Dict{String,Any}()

    config = Dict(
        "fire" => (
            path = joinpath(BUSHFIRE_DIR, "$(lowercase(state))_annual_fire_probability_250m.tif"),
            threshold = nothing,
        ),
        "flood" => (
            path = state == "TAS" ? joinpath(FLOOD_VIC_PATH, "tas_flood_event_frequency_250m.tif") : nothing,
            threshold = 1.0,
        ),
    )

    for (hazard, settings) in config
        settings.path === nothing && continue
        isfile(settings.path) || error("Required $hazard raster not found: $(settings.path)")

        rasters[hazard] = load_hazard_raster(settings.path)
        @info "Hazard raster loaded" hazard=hazard state=state
    end

    return rasters
end

# ============================================================
# HAZARD PROBABILITY EXTRACTION
# ============================================================

"""
    extract_hazard_probability(raster, longitude, latitude)

Extract the hazard probability at a geographic coordinate.

Returns `missing` if the coordinate falls outside the raster,
corresponds to a NoData cell, or contains an invalid value.
"""
function extract_hazard_probability(raster, longitude::Real, latitude::Real)
    x, y = WGS84_TO_AU_ALBERS(Float64(longitude), Float64(latitude))

    gt = raster.geotransform
    dx, dy = x - gt[1], y - gt[4]

    determinant = gt[2] * gt[6] - gt[3] * gt[5]
    iszero(determinant) && error("Invalid raster geotransform")

    col = floor(Int, (gt[6] * dx - gt[3] * dy) / determinant) + 1
    row = floor(Int, (-gt[5] * dx + gt[2] * dy) / determinant) + 1

    values = raster.values
    checkbounds(Bool, values, row, col) || return missing

    value = values[row, col]

    (value === missing || !isfinite(value)) && return missing
    raster.nodata !== nothing && isequal(value, raster.nodata) && return missing

    return 0.0 <= value <= 1.0 ? Float64(value) : missing
end

"""
    add_hazard_probabilities!(df, rasters)

Extract available hazard probabilities for every location in a DataFrame.

Adds one column per hazard, named `<hazard>_probability`.
Missing values indicate unavailable raster data or locations outside the raster.
"""
function add_hazard_probabilities!(df::DataFrame, rasters; longitude_col=:longitude, latitude_col=:latitude)
    for hazard in ("fire", "flood")
        column = Symbol("$(hazard)_probability")

        if haskey(rasters, hazard)
            raster = rasters[hazard]
            df[!, column] = [extract_hazard_probability(raster, lon, lat) for (lon, lat) in zip(df[!, longitude_col], df[!, latitude_col])]
        else
            df[!, column] = fill(missing, nrow(df))
        end
    end

    return df
end