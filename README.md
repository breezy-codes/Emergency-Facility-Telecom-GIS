# Telecommunications Accessibility of Australian Evacuation Facilities

> Research software developed by Brianna Laird as part of her PhD research at Deakin University, Australia. The project assesses telecommunications accessibility at evacuation facilities across Australia by integrating geospatial datasets on evacuation locations, telecommunications infrastructure, bushfire hazards, flood hazards, and administrative boundaries.

![License](https://img.shields.io/badge/license-GPLv3-blue.svg)
![Research](https://img.shields.io/badge/research-Deakin%20University-purple)

## Overview

This repository contains the data collection, preparation, and analysis workflow used to assess telecommunications accessibility at evacuation facilities across Australia.

The project integrates evacuation facility locations, telecommunications infrastructure, bushfire hazard data, flood hazard data, and administrative boundary datasets to evaluate the spatial relationship between evacuation facilities, hazards, and telecommunications infrastructure. The resulting analyses provide insights into the accessibility of telecommunications services at evacuation locations and identify facilities where hazard exposure coincides with comparatively limited proximity to telecommunications assets.

## Citation

If you use this repository, datasets, or implementations in academic work, please cite this repository.

GitHub provides a built-in **"Cite this repository"** option via the repository sidebar.

### BibTeX

```bibtex
@software{Laird_Telecommunications_Accessibility_of_2026,
author = {Laird, Brianna},
license = {GPL-3.0},
month = July,
title = {{Telecommunications Accessibility of Hazard-Exposed Facilities: A GIS-Based Analysis of Australian Evacuation Locations}},
url = {https://github.com/breezy-codes/Emergency-Facility-Telecom-GIS},
version = {1.0.0},
year = {2026}
}
```

## Research Objectives

The project addresses the following questions:

* How accessible is telecommunications infrastructure to evacuation facilities across Australia?
* How does telecommunications accessibility vary between jurisdictions?
* Which evacuation facilities are located within bushfire-prone or flood-prone areas?
* Among hazard-exposed evacuation facilities, which locations exhibit comparatively poor proximity to telecommunications infrastructure?
* How can spatial analysis support resilience planning and infrastructure investment decisions?

## Repository Structure

The repository is organised into the following directories:

> 📂 **[last-resort-GIS-comparison](.)/**
> - 📄 [README.md](README.md)
> - 📁 [code](code)/
>   - 📁 [analysis](code/analysis)/
>     - 🐍 [bushfire\_evac\_celltower.py](code/analysis/bushfire_evac_celltower.py)
>     - 🐍 [bushfire\_vs\_evacuation.py](code/analysis/bushfire_vs_evacuation.py)
>     - 🐍 [colocation\_statistics.py](code/analysis/colocation_statistics.py)
>     - 🐍 [data\_overview.py](code/analysis/data_overview.py)
>     - 🐍 [flood\_evac\_celltower.py](code/analysis/flood_evac_celltower.py)
>     - 🐍 [flood\_vs\_evacuation.py](code/analysis/flood_vs_evacuation.py)
>     - 🐍 [nearest\_neighbour\_proximity.py](code/analysis/nearest_neighbour_proximity.py)
>   - 📁 [data\_preparation](code/data_preparation)/
>     - 🐍 [NT\_scrape.py](code/data_preparation/NT_scrape.py)
>     - 🐍 [cell\_tower\_sanitising.py](code/data_preparation/cell_tower_sanitising.py)
>     - 🐍 [collect\_cell\_towers.py](code/data_preparation/collect_cell_towers.py)
>     - 🐍 [collect\_flood\_zones.py](code/data_preparation/collect_flood_zones.py)
>     - 💻 [download\_evacuation\_data.sh](code/data_preparation/download_evacuation_data.sh)
>     - 🐍 [process\_bushfire\_zones.py](code/data_preparation/process_bushfire_zones.py)
>     - 🐍 [process\_flood\_zones.py](code/data_preparation/process_flood_zones.py)
>     - 🐍 [state\_boundaries.py](code/data_preparation/state_boundaries.py)
>   - 📁 [visual\_analysis](code/visual_analysis)/
>     - 🐍 [NSW_bushfire_sample.py](code/visual_analysis/NSW_bushfire_sample.py)
>     - 🐍 [country\_map.py](code/visual_analysis/country_map.py)
>     - 🐍 [state\_map.py](code/visual_analysis/state_map.py)
> - 📁 [data](data)/
> - 📁 [docs](docs)/
>   - 📄 [analysis\_workflow.md](docs/analysis_workflow.md)
>   - 📄 [data\_management.md](docs/data_management.md)
> - 📁 [figures](figures)/
> - 📁 [maps](maps)/
>   - 🌐 [country\_map.html](maps/country_map.html)
> - 📁 [results](results)/

## Methodology

The workflow consists of four primary stages:

### 1. Data Collection

Datasets are obtained from publicly available government and telecommunications sources, including:

* Australian evacuation facility datasets.
* Telecommunications infrastructure datasets.
* Bushfire hazard datasets.
* Flood hazard datasets.
* Administrative boundary datasets.

Detailed instructions are provided in [data management](docs/data_management.md).

### 2. Data Preparation

Collected datasets are cleaned, standardised, transformed, and integrated into a common geospatial framework suitable for national-scale analysis.

Preparation scripts include:

* Evacuation facility processing.
* Telecommunications infrastructure processing.
* Bushfire hazard processing.
* Flood hazard processing.
* Administrative boundary generation.

### 3. Spatial Analysis

The analysis workflow evaluates:

* Telecommunications proximity to evacuation facilities.
* Telecommunications colocation statistics.
* Bushfire exposure of evacuation facilities.
* Flood exposure of evacuation facilities.
* Telecommunications accessibility of hazard-exposed facilities.

Detailed descriptions of each analysis script are provided in [analysis workflow](docs/analysis_workflow.md).

### 4. Visualisation and Reporting

Analysis outputs are used to generate:

* Summary statistics.
* Jurisdiction-level comparisons.
* Hazard exposure assessments.
* Telecommunications accessibility maps.
* Spatial resilience planning visualisations.

## Quick Start

### Clone the Repository

```bash
git clone https://github.com/breezy-codes/Emergency-Facility-Telecom-GIS.git

cd Emergency-Facility-Telecom-GIS
```

### Set Up the Python Environment

Create a virtual environment for the project:

```bash
python -m venv .venv
```

Activate the virtual environment:

```bash
source .venv/bin/activate
```

Install the required Python packages:

```bash
pip install -r requirements.txt
```

The virtual environment contains the project-specific dependencies and keeps them isolated from other Python installations.

### Collect and Prepare Data

Follow the instructions contained in [docs/data_management.md](docs/data_management.md) to obtain and prepare the necessary datasets.

### Run Analyses

Follow the workflow described in [docs/analysis_workflow.md](docs/analysis_workflow.md) to execute the analysis scripts in the correct sequence.

## Data Availability

The repository does not redistribute source datasets.

Many source datasets are provided by external government agencies and may be subject to licensing, attribution, or redistribution requirements. To ensure users obtain the most current versions of the data and to maintain compliance with source licensing conditions, datasets must be obtained directly from their original providers.

Scripts and documentation are provided to reproduce the complete data collection and preparation workflow.

## Reproducibility

All code required to reproduce the analyses presented in the associated publication is included within this repository. Provided the source datasets are obtained and processed according to the documented workflow, users should be able to reproduce all reported analyses, figures, and summary statistics using the Python environment specified in `requirements.txt`.
