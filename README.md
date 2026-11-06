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

The framework is implemented in Julia. Install Julia and the required project dependencies before running the analysis.

Clone the repository:

```bash
git clone https://github.com/breezy-codes/Emergency-Facility-Telecom-GIS.git

cd Emergency-Facility-Telecom-GIS
```

Install the project dependencies using Julia's package manager:

```julia
using Pkg
Pkg.instantiate()
```

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

## Data Availability

Source datasets are not redistributed within this repository. They are obtained from publicly available government and telecommunications data providers and may be subject to individual licensing and attribution requirements.

The repository provides data acquisition scripts, source links, and instructions for manually downloading datasets. The `run_setup.jl` script automates the collection and preparation steps supported by the workflow.

## Reproducibility

All Julia code required to execute the framework is provided in this repository. By obtaining the source datasets, following the documented data preparation instructions, and executing `run_setup.jl` followed by `main.jl`, users can reproduce the probabilistic modelling, spatial analyses, CSV outputs, and figures generated by the study.
