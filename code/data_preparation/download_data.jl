using Downloads

function download_data()
    # Download helper for printing messages and downloading files
    format_bytes(bytes) = bytes < 1024^2 ? "$(round(bytes / 1024; digits=1)) KiB" : "$(round(bytes / 1024^2; digits=1)) MiB"

    function download_file(url, destination)
        filename = basename(destination)
        bar_width = 30

        @info "Downloading dataset" filename

        progress = function (total, now)
            if total > 0
                percentage = clamp(now / total, 0, 1)
                filled = round(Int, bar_width * percentage)
                bar = repeat("█", filled) * repeat("░", bar_width - filled)
                print(stderr, "\r  $filename [$bar] $(round(percentage * 100; digits=1))% ($(format_bytes(now)) / $(format_bytes(total)))")
            else
                print(stderr, "\r  $filename ($(format_bytes(now)) downloaded)")
            end
            flush(stderr)
        end

        Downloads.download(url, destination; progress=progress)

        print(stderr, "\r  $filename [$(repeat("█", bar_width))] 100% Complete\n")
        @info "Downloaded dataset" filename

        return destination
    end

    # === EVACUATION DATASETS ===
    download_file("https://services6.arcgis.com/OWiNqVszgclESSTd/arcgis/rest/services/Nearby_Safer_Places/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson", "../data/evacuation_datasets/tasmania.geojson")

    download_file("https://portal.spatial.nsw.gov.au/server/rest/services/Hosted/Neighbourhood_Safer_Places/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson", "../data/evacuation_datasets/new_south_wales.geojson")

    download_file("https://services-ap1.arcgis.com/vh59f3ZyAEAhnejO/ArcGIS/rest/services/MY_CFA_Data_Layers/FeatureServer/2/query?where=1%3D1&outFields=*&f=geojson", "../data/evacuation_datasets/victoria.geojson")

    download_file("https://www.dptiapps.com.au/dataportal/BushfireLastResortRefuges_geojson.zip", "../data/raw/bushfire_last_resort_refuges.zip")

    run(`unzip -o ../data/raw/bushfire_last_resort_refuges.zip -d ../data/evacuation_datasets/`)

    mv("../data/evacuation_datasets/BushfireLastResortRefuges_GDA2020.geojson", "../data/evacuation_datasets/south_australia.geojson"; force=true)

    # === TASMANIAN FLOOD HISTORY ===
    download_file("https://listdata.thelist.tas.gov.au/opendata/data/TSFM_CALIBRATION_DATA_DEPTH_STATEWIDE.zip", "../data/raw/tsfm_calibration_data_depth.zip")

    run(`unzip -o ../data/raw/tsfm_calibration_data_depth.zip -d ../data/flood_history/`)

    # === TASMANIAN FIRE HISTORY ===
    download_file("https://listdata.thelist.tas.gov.au/opendata/data/LIST_FIRE_HISTORY_STATEWIDE.zip", "../data/raw/list_fire_history_statewide.zip")

    run(`unzip -o ../data/raw/list_fire_history_statewide.zip -d ../data/fire_history/`)

    # === SOUTH AUSTRALIAN FIRE HISTORY ===
    download_file("https://www.waterconnect.sa.gov.au/Content/Downloads/DEWNR/FIREMGT_FireHistory_geojson.zip", "../data/raw/sa_fire_history.zip")

    run(`unzip -o ../data/raw/sa_fire_history.zip -d ../data/fire_history/`)

    # === NSW FIRE HISTORY ===
    download_file("https://datasets.seed.nsw.gov.au/dataset/1d05e145-80cb-4275-af9b-327a1536798d/resource/3853d6c0-6517-4cba-8482-68f93a6d43b1/download/fire_npwsfirehistory.zip", "../data/raw/nsw_fire_history.zip")

    run(`unzip -o ../data/raw/nsw_fire_history.zip -d ../data/fire_history/`)

    println("\nAll datasets downloaded and extracted successfully.")
    return nothing
end

download_data()