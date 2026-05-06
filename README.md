# LAAC + MR — Analysis Pipeline

R analysis pipeline used in:

> **Mitral regurgitation and in-hospital outcomes of percutaneous left atrial appendage closure**
> *Journal of Interventional Cardiac Electrophysiology* (2025).
> [https://doi.org/10.1007/s10840-025-02200-x](https://link.springer.com/article/10.1007/s10840-025-02200-x)

The script reproduces the descriptive tables, statistical comparisons, multivariable logistic regression and forest plot reported in the paper. It is built on top of the **HCUP National Inpatient Sample (NIS)** for the years 2016–2021, but the same pipeline can be reused for any NIS-based two-group comparison (see [Adapting the pipeline](#adapting-the-pipeline)).

---

## Repository contents

```
.
├── run_pipeline.R          # Main analysis pipeline
├── Background_Info.csv     # ICD-10 codes for comorbidities and background variables
├── Complications.csv       # ICD-10 codes for in-hospital complications + category mapping
├── Continous_Columns.csv   # Continuous-variable configuration (table assignment + normality flag)
└── README.md               # This file
```

The raw NIS file (`LAAC_ANY_2016_2021.sav`) is **not included** — it is a licensed product of HCUP and must be obtained separately (see [Data access](#data-access)).

---

## Pipeline overview

`run_pipeline.R` is a single, top-to-bottom script that:

1. **Loads** the NIS extract (`.sav`) and three reference CSVs.
2. **Cleans** the cohort: excludes patients < 18 years old and rows with missing values in `FEMALE`, `RACE`, `ZIPINC_QRTL`, `LOS`, `DIED`. Both raw and discharge-weighted (`DISCWT`) row counts are printed at each step.
3. **Builds comorbidity flags** from the `I10_DX*` columns using the ICD-10 codes in `Background_Info.csv`. A flag is set to 1 if any of the patient's diagnosis columns matches any of the listed codes.
4. **Computes clinical risk scores**:
   - `CHA2DS2_VASc`
   - `Atria_Bleeding_Score`
   - `Charlson_Index`
5. **Maps sociodemographic variables**: median income quartile (from `ZIPINC_QRTL`), white-ethnicity indicator (from `RACE`), hospital type (from `HOSP_LOCTEACH`).
6. **Builds complication flags and category roll-ups** from `Complications.csv`. Leaf complications are matched against either `I10_DX*` or `I10_PR*` depending on the `Category` field (see [Reference CSV format](#reference-csv-format)). Category rows are roll-ups: a category flag is 1 if any of its member complications is 1.
7. **Defines the subset column** that splits the cohort into the two comparison groups. In this study the subset is MR (ICD-10: `Q23.3`, `I34.0`, `I05.1`); patients with isolated mitral valve prolapse (`I34.1`) without an MR code are removed.
8. **Builds Table 1 (baseline characteristics)**:
   - Continuous variables: weighted t-test or Wilcoxon rank-sum, depending on the normality flag in `Continous_Columns.csv`.
   - Categorical variables: weighted Pearson χ² (Fisher's exact when the minimum expected cell count < 5).
   - Cells with weighted *n* < 10 are masked as `<10` per HCUP small-cell reporting guidance.
9. **Builds Table 2 (in-hospital complications and outcomes)** using the same logic.
10. **Fits multivariable logistic regression** for every complication that differed significantly (p ≤ 0.05) between the two groups in Table 2. Covariates are pre-selected by univariate significance against the outcome (p ≤ 0.05). For each model the script reports:
    - Adjusted odds ratio with 95% CI
    - Per-coefficient p-value
    - McFadden's pseudo-R²
    - Likelihood-ratio p-value
    - Naive accuracy at a 0.5 threshold
11. **Plots a forest plot** of the adjusted OR for the subset variable (MR) across all significant complications (`Odds_Ratio_Graph.jpg`).

---

## Outputs

Running the script produces, in the working directory:

| File | Contents |
|---|---|
| `table1.csv` | Table 1 — baseline characteristics, subset vs. non-subset |
| `table2.csv` | Table 2 — in-hospital procedures, complications and mortality |
| `Logistic_Regerssion_Results.csv` | Per-complication adjusted OR / 95% CI / p-value for every retained covariate |
| `Odds_Ratio_Graph.jpg` | Forest plot of the adjusted OR for the subset variable across all significant complications |

The script also prints diagnostic information to the console: row counts after each filtering step, χ² expected-frequency tables, and the regression formula it auto-builds for each outcome.

---

## Requirements

- **R** ≥ 4.1
- The following CRAN packages:
  - `haven` — read SPSS `.sav` files
  - `dplyr`
  - `tidyverse`
  - `stringr`
  - `reshape2`
  - `ggplot2`

Install with:

```r
install.packages(c("haven", "dplyr", "tidyverse", "stringr", "reshape2", "ggplot2"))
```

> **Note:** the published script contains a typo — `install.packages("hevan")` should be `install.packages("haven")`. The `library("haven")` call below it is correct, so the script will still run as long as `haven` is installed.

---

## Data access

The analysis relies on the **HCUP National Inpatient Sample (NIS)**, 2016–2021. NIS is a restricted-use, licensed dataset and **cannot be redistributed in this repository**.
## Reference CSV format

The three CSVs in this repo encode all of the project-specific configuration. Editing them is enough to redirect the pipeline at a different cohort question.

### `Background_Info.csv`

Column headers: `Name, Values, Is_Presented_In_Table1`.

| Column | Meaning |
|---|---|
| `Name` | Variable name (becomes the column name added to the data frame, e.g. `Hypertension`, `Diabetes`, `Anemia`) |
| `Values` | Comma-separated ICD-10 codes, with no dots, matching how NIS stores `I10_DX*` (e.g. `I10`, `E785`, `I110,I130,I132,...`) |
| `Is_Presented_In_Table1` | `1` if the variable should appear in Table 1, `0` if it is computed only to feed a derived score (CHA2DS2-VASc, ATRIA, Charlson) |

The flag is built as: `1` if **any** of the patient's `I10_DX*` columns equals **any** of the listed codes, otherwise `0`.

> The CSV may contain a few trailing empty columns from the original Excel export — these are harmless; the script reads only the first three columns by index.

### `Complications.csv`

Column headers: `Complication, Values, Category`.

This file mixes two row types, distinguished by the value in the `Category` column:

| Row type | `Category` value | What `Values` contains |
|---|---|---|
| Leaf — diagnosis-based | `DX` | Comma-separated ICD-10 diagnosis codes; matched against `I10_DX*` |
| Leaf — procedure-based | `PR` | Comma-separated ICD-10 procedure codes; matched against `I10_PR*` |
| Roll-up | `Category` | Comma-separated **names** of other rows in this file. The roll-up flag is `1` if any member is `1`. |

Internally the script does `str_c("I10_", Category)` to build the column-name prefix for leaf rows, so the `Category` column doubles as a routing field (DX → diagnoses, PR → procedures) and as the roll-up marker.

Examples from the file:

```
Acute_Kidney_Injury, N179, DX                                # leaf, diagnosis-based
Need_for_Hemodialysis, "5A1D70Z,5A1D80Z,5A1D90Z", PR         # leaf, procedure-based
Renal, "Acute_Kidney_Injury,Need_for_Hemodialysis", Category # roll-up
Total_Complication_Rate, "Cardiac,Vascular,Neurologic,Pulmonary,Renal,Mortality,Systemic", Category   # higher-level roll-up
```

Roll-ups can reference other roll-ups (e.g. `Total_Complication_Rate` references `Cardiac`, which is itself a roll-up of `Cardiogenic_Shock`, `Pericarditis`, …). The script builds leaf rows first, then categories, so this works as long as the row ordering inside the file is preserved.

### `Continous_Columns.csv`

Column headers: `Variable_Name, Variable_Table, Treat_as_Normally_Distributed`.

| Column | Meaning |
|---|---|
| `Variable_Name` | Name of an existing numeric column in the data frame (e.g. `AGE`, `Length_of_Stay`, or any of the computed scores) |
| `Variable_Table` | `1` to put the variable in Table 1, `2` to put it in Table 2 |
| `Treat_as_Normally_Distributed` | `1` → t-test + mean ± SD; `0` → Wilcoxon rank-sum + median (IQR) |

Default contents (5 rows): `AGE`, `CHA2DS2_VASc`, `Atria_Bleeding_Score`, `Charlson_Index`, `Length_of_Stay`.

---

## How to run

1. Place `LAAC_ANY_2016_2021.sav`, the three reference CSVs and `run_pipeline.R` in the same folder.
2. Open R / RStudio and set that folder as the working directory:
   ```r
   setwd("path/to/this/folder")
   ```
3. Source the script:
   ```r
   source("run_pipeline.R")
   ```

The script will print row counts after each filtering step, the χ² expected-frequency tables, and the regression formulas it auto-builds, before writing the four output artifacts to disk.

---

## Methodological notes

- **Survey weighting.** All frequencies and percentages reported in Table 1 and Table 2 use NIS trend-adjusted discharge weights (`DISCWT`). The hypothesis tests use a pragmatic implementation: continuous values are replicated 5× before the t-test / Wilcoxon, and categorical tests are run on the rounded weighted contingency table. This is not a fully design-based survey analysis — users wishing to use Taylor-series linearization can re-run the comparisons with the [`survey`](https://cran.r-project.org/package=survey) package.
- **Small-cell suppression.** Cells with weighted *n* < 10 are reported as `<10` in line with HCUP data-use rules.
- **Variable selection for multivariable models.** The script greedily adds any covariate with a univariate p ≤ 0.05 against the outcome to the model, in addition to the subset (group) indicator. The retained formula is printed to the console for each complication.
- **MVP exclusion.** Patients with isolated mitral valve prolapse (`I34.1`) and no MR diagnosis are removed before the comparison, so the contrast is *MR vs. no significant valvular pathology* rather than *MR vs. all other LAAC patients*. To disable this behavior, set `Excluded_Values <- character(0)` near line ~164 of the script.

---

## Citation

If you use this code, please cite the paper:

```bibtex
@article{LAAC_MR_2025,
  title   = {Mitral regurgitation and in-hospital outcomes of percutaneous left atrial appendage closure},
  journal = {Journal of Interventional Cardiac Electrophysiology},
  year    = {2025},
  doi     = {10.1007/s10840-025-02200-x},
  url     = {https://link.springer.com/article/10.1007/s10840-025-02200-x}
}
```

---

## Disclaimer

This code is provided **for academic reproducibility only** and is not a clinical decision tool. The analyses depend on NIS administrative coding, which has known limitations for severity stratification (e.g. MR severity is not captured by ICD-10 alone).

The HCUP NIS data are © Agency for Healthcare Research and Quality. Use of the data is governed by the HCUP Data Use Agreement.

---

## License

Code in this repository is released under the **MIT License** (see `LICENSE`). The reference CSV files (`Background_Info.csv`, `Complications.csv`, `Continous_Columns.csv`) consist of ICD-10 code lists curated by the authors and are released under the same license.

---