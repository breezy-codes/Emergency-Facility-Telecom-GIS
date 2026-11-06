# Data Collection and Preparation

This document describes how to obtain and prepare the datasets required by the analysis framework. Source datasets are not redistributed within this repository. Instead, data are obtained directly from their original providers using the supplied download scripts and processing workflows.

## 1. Manual Data Download

One dataset requires manual download: the Victorian flood dataset.

Download the dataset from the [Victorian DataShare portal](https://datashare.maps.vic.gov.au/search?q=uuid%3Dd817f3be-a7a2-5847-9944-c0f2fdb39444).

After downloading, place the dataset in the appropriate location within the repository's `data/` directory, following the expected directory structure.

## 2. Data Collection and Preparation

After downloading and placing the Victorian flood dataset in the appropriate location, execute the Julia setup script from the repository root:

```bash
julia run_setup.jl
```

This script automatically executes `code/data_preparation/download_data.sh` to collect the evacuation facility and hazard datasets, then processes and prepares the collected data into the formats required by the analysis framework.

Once the script completes successfully, all required datasets will be available for analysis.

## 3. Running the Analysis

Once data collection and preparation are complete, all required datasets will be available for analysis.

Execute the main framework using:

```bash
julia main.jl
```

This runs the probabilistic modelling and geospatial analysis workflow, generating the resulting CSV files and figures.

## Recommended Workflow

The complete workflow is:

```bash
# 1. Manually download the Victorian flood dataset
#    https://datashare.maps.vic.gov.au/search?q=uuid%3Dd817f3be-a7a2-5847-9944-c0f2fdb39444

# 2. Collect the remaining datasets and prepare all datasets
julia run_setup.jl

# 3. Execute the analysis framework
julia main.jl
```

Once these steps are complete, the repository will contain all required datasets and will be ready to reproduce the analyses and figures presented in the study.
