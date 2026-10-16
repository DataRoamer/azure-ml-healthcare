# Heart disease risk model on Azure Machine Learning

This project trains a machine learning model that estimates the risk of heart disease from basic patient information, and runs the training on Azure Machine Learning through an automated pipeline. It shows a reproducible training workflow with experiment tracking, CI/CD, and cloud access defined as code.

## How it works

1. A push to the `main` branch starts a GitHub Actions workflow.
2. The workflow logs in to Azure and submits `train_job.yml` as an Azure Machine Learning command job.
3. The job runs `training_script.py` on a compute cluster. MLflow records the parameters, metrics and model for each run.
4. `infra/identity.bicep` defines the identity the pipeline uses and limits it to the two roles it needs.

## Project files

| File | Purpose |
|---|---|
| `training_script.py` | Trains and evaluates a random forest classifier, tracked with MLflow |
| `train_job.yml` | Azure ML command job definition |
| `.github/workflows/train_model.yml` | CI/CD pipeline that submits the training job |
| `infra/identity.bicep` | Infrastructure as code for the pipeline's managed identity and permissions |
| `healthcare.csv` | Training data |

## Run it locally

```bash
pip install pandas scikit-learn mlflow joblib
python training_script.py
```

Optional arguments: `--n_estimators` (default 50) and `--max_depth` (default 5).

## Design choices

- **No data leakage.** The data is split into training and test sets before any preprocessing. Missing values are filled and text columns are encoded inside a scikit-learn `Pipeline`, so they are learned from the training data only.
- **Meaningful features only.** The `id` column is excluded because it identifies rows rather than describing patients.
- **Suitable evaluation.** Heart disease is rare in this data (5.4% of records), so accuracy alone is misleading: a model that always predicted "no" would score about 95%. The model uses balanced class weights and a stratified split, and is evaluated mainly with AUC calculated from predicted probabilities.
- **Least-privilege cloud access.** The pipeline's identity can submit jobs to the workspace and upload code to its storage, but cannot delete the workspace or create compute.

## Results

On the held-out test set (20% of the data), the model achieves an AUC of about 0.81 and accuracy of about 0.73. This is a simple baseline and has not been tuned.

## Data

`healthcare.csv` is the [Stroke Prediction Dataset](https://www.kaggle.com/datasets/fedesoriano/stroke-prediction-dataset) published on Kaggle by fedesoriano, with 5,110 patient records. The dataset's original target is `stroke`; this project uses `heart_disease` as the prediction target. It is for demonstration only and is not a clinical tool.
