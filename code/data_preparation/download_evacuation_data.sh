#!/bin/bash

mkdir -p data/raw
mkdir -p data/evacuation_datasets
mkdir -p data/bushfire_datasets
mkdir -p data/flood_datasets
mkdir -p data/telecommunications_datasets
mkdir -p data/boundaries

curl -L \
"https://services6.arcgis.com/OWiNqVszgclESSTd/arcgis/rest/services/Nearby_Safer_Places/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson" \
-o data/evacuation_datasets/tasmania.geojson

curl -L \
"https://portal.spatial.nsw.gov.au/server/rest/services/Hosted/Neighbourhood_Safer_Places/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson" \
-o data/evacuation_datasets/new_south_wales.geojson

curl -L \
"https://services-ap1.arcgis.com/vh59f3ZyAEAhnejO/ArcGIS/rest/services/MY_CFA_Data_Layers/FeatureServer/2/query?where=1%3D1&outFields=*&f=geojson" \
-o data/evacuation_datasets/victoria.geojson

curl -L \
"https://securent.nt.gov.au/prepare-for-an-emergency/emergency-planning/shelter-locations/all-shelters" \
-o data/raw/NT_shelters.html