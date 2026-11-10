# Data Collection and Preparation

This document describes how to obtain and prepare the datasets required by the analysis framework. Source datasets are not redistributed within this repository. Instead, datasets are collected directly from their original providers using the supplied download and processing workflows.

## 1. Manual Data Download

One dataset must be downloaded manually: the Victorian flood dataset.

Download the dataset from the [Victorian DataShare portal](https://datashare.maps.vic.gov.au/search?q=uuid%3Dd817f3be-a7a2-5847-9944-c0f2fdb39444).

After downloading, place the dataset in the appropriate location within the repository's `data/` directory, following the expected directory structure.

## 2. Data Collection and Preparation

Once the Victorian flood dataset has been downloaded and placed in the appropriate location, execute the setup script from the repository root:

```bash
julia run_setup.jl
```

The setup script automates the collection and preparation of the remaining datasets. It orchestrates the supplied Julia and Python scripts, including:

- **Evacuation facility datasets:** Downloads evacuation facility data from the relevant state providers.
- **Hazard datasets:** Collects fire and flood history data from the relevant providers.
- **Telecommunications datasets:** Uses Python scripts to retrieve telecommunications infrastructure data.
- **Data preparation:** Processes and prepares the collected datasets into the formats required by the analysis framework.

Most data collection and preparation tasks are implemented in Julia, with a small number of Python scripts used for telecommunications data retrieval.

Once the setup script completes successfully, the required datasets will be available for analysis.

## 3. Running the Analysis

After data collection and preparation are complete, execute the main analysis framework from the repository root:

```bash
julia main.jl
```

This runs the probabilistic modelling and geospatial analysis workflows, generating the resulting CSV files and figures.

## Recommended Workflow

The complete workflow is:

```bash
# 1. Manually download the Victorian flood dataset and place it
#    in the appropriate location within data/

# 2. Collect and prepare all remaining datasets
julia run_setup.jl

# 3. Execute the analysis framework
julia main.jl
```

Once these steps are complete, the repository will contain the required datasets and will be ready to reproduce the analyses and figures presented in the study.
