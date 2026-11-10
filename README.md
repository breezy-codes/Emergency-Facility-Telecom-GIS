# Telecommunications Accessibility of Australian Evacuation Facilities

> Research software developed by Brianna Laird as part of her PhD research at Deakin University, Australia. This project develops a probabilistic geospatial framework to assess telecommunications accessibility and resilience at evacuation facilities by integrating evacuation locations, telecommunications infrastructure, bushfire and flood hazards, and administrative boundaries.

![License](https://img.shields.io/badge/license-GPLv3-blue.svg)
![Research](https://img.shields.io/badge/research-Deakin%20University-purple)

## Overview

This repository contains the data collection, preparation, and analysis framework used to assess telecommunications accessibility and hazard-related vulnerability at evacuation facilities.

Implemented in Julia, the framework integrates geospatial datasets on evacuation facilities, telecommunications infrastructure, natural hazards, and administrative boundaries. It incorporates probabilistic telecommunications coverage and infrastructure failure models to evaluate baseline accessibility, infrastructure redundancy, and service continuity under different deployment scenarios and hazard conditions.

The repository includes the scripts required to collect and prepare datasets, execute the probabilistic model, perform spatial analyses, and generate results, figures, and summary statistics.

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

## Framework Overview

The framework consists of three primary stages.

### 1. Data Collection

The framework uses publicly available datasets from government agencies and telecommunications data providers, including:

- Evacuation facility locations.
- Telecommunications infrastructure locations.
- Bushfire hazard datasets.
- Flood hazard datasets.
- Administrative boundaries.

Data acquisition involves a combination of automated collection scripts and manual downloads from external data providers. Detailed instructions, source links, and acquisition procedures are provided in [Data Management](docs/data_management.md).

### 2. Data Preparation

Collected datasets are placed in the repository's `data/` directory. The setup workflow processes the downloaded and collected data into the formats required by the analysis framework.

Preparation includes:

- Cleaning and standardising source datasets.
- Processing evacuation facility and telecommunications infrastructure locations.
- Preparing bushfire and flood hazard data.
- Generating and processing administrative boundaries.
- Integrating datasets into a common geospatial framework.

### 3. Probabilistic Modelling and Spatial Analysis

The main analysis framework integrates the prepared datasets to evaluate telecommunications accessibility and resilience at evacuation facilities.

The analyses include:

- Probabilistic 4G and 5G telecommunications coverage.
- Telecommunications infrastructure redundancy.
- Hazard-dependent infrastructure and facility failure probabilities.
- Telecommunications service continuity and cutoff risk.
- Facility-level vulnerability assessments.
- Spatial comparisons across deployment scenarios, jurisdictions, and analysis periods.

The framework generates CSV files containing analysis results and figures for visualisation and reporting.

## Installation and Requirements

The framework uses Julia for its primary analysis workflows and Python for selected data collection tasks, including telecommunications infrastructure retrieval. Both environments must be configured before running the framework.

### 1. Clone the Repository

Clone the repository and navigate into the project directory:

```bash
git clone https://github.com/breezy-codes/Emergency-Facility-Telecom-GIS.git

cd Emergency-Facility-Telecom-GIS
```

### 2. Set Up the Julia Environment

Install [Julia](https://julialang.org/downloads/) if it is not already available.

The repository includes a `Project.toml` and `Manifest.toml` defining the required Julia dependencies. From the repository root, initialise the project environment and install the dependencies:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

This activates the project-specific Julia environment and installs the required packages.

### 3. Set Up the Python Environment

Install Python 3 if it is not already available.

Create a local Python virtual environment from the repository root:

```bash
python3 -m venv .venv
```

Activate the environment:

```bash
source .venv/bin/activate
```

Install the required Python libraries:

```bash
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

The virtual environment keeps the project's Python dependencies isolated from other Python installations.

Once installation is complete, the environment can be deactivated using:

```bash
deactivate
```

The virtual environment does not need to be manually activated when running the setup workflow, provided the setup script invokes the Python executable located in `.venv`.

### 4. System Requirements

Ensure that the required system utilities are installed, including:

- Python 3 and its virtual environment support (`venv`).
- Julia.
- `unzip`.
- Any additional geospatial system dependencies required by the installed Julia and Python packages.

## Running the Framework

The framework is executed in two main stages.

### 1. Data Collection and Preparation

First, follow the instructions in [docs/data_management.md](docs/data_management.md) to download the datasets that require manual acquisition.

Place the downloaded datasets in the appropriate locations within the repository's `data/` directory, following the documented directory structure.

Then execute:

```bash
julia run_setup.jl
```

This script automatically collects the datasets supported by the automated collection workflow and processes the available source data into the formats required by the analysis framework.

**Important:** Datasets requiring manual download must be obtained and placed in the appropriate `data/` directories before running the setup script.

### 2. Execute the Analysis Framework

Once data collection and preparation are complete, run:

```bash
julia main.jl
```

The main script executes the complete analysis workflow, including:

- Loading and integrating the prepared datasets.
- Applying the probabilistic telecommunications coverage and infrastructure failure models.
- Performing the geospatial analysis.
- Evaluating facility-level accessibility and resilience measures.
- Generating summary statistics and visualisations.

Analysis outputs, including CSV result files and figures, are saved to the repository's results directory.

## Viewing Results

The framework generates several outputs during data preparation and analysis. These are saved in the repository's output directories.

### 1. Analysis Outputs

Most analysis outputs are saved under the `results/` directory, including:

- CSV files containing facility-level analysis results and summary statistics.
- Figures generated during the analysis.
- Plots used for visualising telecommunications accessibility and resilience.

Hazard raster visualisations are saved separately in the repository's top-level `figures/` directory.

### 2. Interactive Geospatial Map

During `run_setup.jl`, the framework also generates an interactive Folium map displaying the geographic distribution of:

- Australian states and territories.
- Evacuation facilities.
- Telecommunications infrastructure assets.

The map allows users to explore the spatial distribution of these datasets interactively.

**Important:** Folium maps need to be served through a local Python HTTP server to render correctly in a browser. Instructions for starting the server and viewing the interactive map are provided in [docs/basemaps.md](docs/basemaps.md).

## Data Availability

Source datasets are not redistributed within this repository. They are obtained from publicly available government and telecommunications data providers and may be subject to individual licensing and attribution requirements.

The repository provides data acquisition scripts, source links, and instructions for manually downloading datasets. The `run_setup.jl` script automates the collection and preparation steps supported by the workflow.

## Reproducibility

All Julia code required to execute the framework is provided in this repository. By obtaining the source datasets, following the documented data preparation instructions, and executing `run_setup.jl` followed by `main.jl`, users can reproduce the probabilistic modelling, spatial analyses, CSV outputs, and figures generated by the study.
