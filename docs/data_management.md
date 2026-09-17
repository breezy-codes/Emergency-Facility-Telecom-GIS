# Data Collection and Preparation

This document describes the steps required to obtain and prepare all datasets used in the analysis. Source datasets are not redistributed within this repository. Instead, users should obtain data directly from the original providers and use the supplied scripts to reproduce the complete data preparation workflow.

## Evacuation Facility Data

### Tasmania, New South Wales, Victoria, and Northern Territory

Evacuation facility data for Tasmania, New South Wales, Victoria, and the Northern Territory can be collected by running:

```bash
bash code/data_preparation/download_evacuation_data.sh
```

This script downloads:

* Tasmania Neighbourhood Safer Places
* New South Wales Neighbourhood Safer Places
* Victoria Bushfire Places of Last Resort
* Northern Territory shelter location information

This script also creates all of the necessary data directories for storing the raw and processed datasets.

### Northern Territory Post-Processing

The Northern Territory shelter data is downloaded as an HTML page and must be converted into a machine-readable format using:

```bash
python code/data_preparation/NT_scrape.py
```

### South Australia

The South Australian Bushfire Last Resort Refuges dataset must be downloaded manually from:

<https://data.sa.gov.au/data/dataset/bushfire-last-resort-refuges>

After downloading, place the dataset in the `data/evacuation_datasets` directory.

## Telecommunications Infrastructure Data

Cell tower data can be collected and processed using:

```bash
python code/data_preparation/collect_cell_towers.py
python code/data_preparation/cell_tower_sanitising.py
```

The collection script retrieves the source telecommunications infrastructure data, while the sanitisation script performs cleaning and standardisation required for subsequent analysis.

---

## Bushfire Hazard Data

Bushfire hazard data can be downloaded from:

<https://portal.spatial.nsw.gov.au/client/services?id=84c338fe2e8c49a9836751ed49c9c581>

After downloading the source dataset, place it in the `data/raw` directory and process it using:

```bash
python code/data_preparation/process_bushfire_zones.py
```

---

## Flood Hazard Data

Flood hazard data can be collected using:

```bash
python code/data_preparation/collect_flood_zones.py
```

After collection, process the dataset using:

```bash
python code/data_preparation/process_flood_zones.py
```

---

## Administrative Boundaries

Australian state and territory boundary data can be collected using:

```bash
python code/data_preparation/state_boundaries.py
```

---

## Recommended Workflow

The recommended order of execution is:

```bash
# Evacuation facilities
bash code/data_preparation/download_evacuation_data.sh
python code/data_preparation/NT_scrape.py

# Cell towers
python code/data_preparation/collect_cell_towers.py
python code/data_preparation/cell_tower_sanitising.py

# Flood data
python code/data_preparation/collect_flood_zones.py
python code/data_preparation/process_flood_zones.py

# Bushfire data
python code/data_preparation/process_bushfire_zones.py

# State boundaries
python code/data_preparation/state_boundaries.py
```

Once all datasets have been collected and processed, the repository will contain the required inputs for reproducing the analysis and figures presented in the study.
