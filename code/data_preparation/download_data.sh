#!/bin/bash
set -e

mkdir -p ../data/raw
mkdir -p ../data/evacuation_datasets
mkdir -p ../data/fire_history
mkdir -p ../data/flood_history
mkdir -p ../data/telecommunications_datasets
mkdir -p ../data/boundaries

# Download evacuation datasets from various sources
curl -L \
"https://services6.arcgis.com/OWiNqVszgclESSTd/arcgis/rest/services/Nearby_Safer_Places/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson" \
-o ../data/evacuation_datasets/tasmania.geojson

curl -L \
"https://portal.spatial.nsw.gov.au/server/rest/services/Hosted/Neighbourhood_Safer_Places/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson" \
-o ../data/evacuation_datasets/new_south_wales.geojson

curl -L \
"https://services-ap1.arcgis.com/vh59f3ZyAEAhnejO/ArcGIS/rest/services/MY_CFA_Data_Layers/FeatureServer/2/query?where=1%3D1&outFields=*&f=geojson" \
-o ../data/evacuation_datasets/victoria.geojson

curl -fL \
"https://www.dptiapps.com.au/dataportal/BushfireLastResortRefuges_geojson.zip" \
-o ../data/raw/bushfire_last_resort_refuges.zip

unzip -o ../data/raw/bushfire_last_resort_refuges.zip -d ../data/evacuation_datasets/

mv ../data/evacuation_datasets/BushfireLastResortRefuges_GDA2020.geojson ../data/evacuation_datasets/south_australia.geojson

# Download and extract Tasmanian flood depth data
curl -fL \
"https://listdata.thelist.tas.gov.au/opendata/data/TSFM_CALIBRATION_DATA_DEPTH_STATEWIDE.zip" \
-o ../data/raw/tsfm_calibration_data_depth.zip

unzip -o ../data/raw/tsfm_calibration_data_depth.zip -d ../data/flood_history/

# Download and extract Tasmanian fire history data
curl -fL \
"https://listdata.thelist.tas.gov.au/opendata/data/LIST_FIRE_HISTORY_STATEWIDE.zip" \
-o ../data/raw/list_fire_history_statewide.zip

unzip -o ../data/raw/list_fire_history_statewide.zip -d ../data/fire_history/

# Download and extract South Australian fire history data
curl -fL \
"https://www.waterconnect.sa.gov.au/Content/Downloads/DEWNR/FIREMGT_FireHistory_geojson.zip" \
-o ../data/raw/sa_fire_history.zip

unzip -o ../data/raw/sa_fire_history.zip -d ../data/fire_history/


# Download and extract NSW fire history data
curl -fL \
"https://datasets.seed.nsw.gov.au/dataset/1d05e145-80cb-4275-af9b-327a1536798d/resource/3853d6c0-6517-4cba-8482-68f93a6d43b1/download/fire_npwsfirehistory.zip" \
-o ../data/raw/nsw_fire_history.zip

unzip -o ../data/raw/nsw_fire_history.zip -d ../data/fire_history/
