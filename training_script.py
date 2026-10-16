import argparse
import os

import joblib
import mlflow
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import accuracy_score, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

TARGET = "heart_disease"
NUMERIC = ["age", "hypertension", "avg_glucose_level", "bmi", "stroke"]
CATEGORICAL = ["gender", "ever_married", "work_type", "Residence_type", "smoking_status"]

# Parse arguments
parser = argparse.ArgumentParser()
parser.add_argument("--n_estimators", type=int, default=50)
parser.add_argument("--max_depth", type=int, default=5)
args = parser.parse_args()

# Load data. "id" only identifies rows, so it is not used as a feature.
df = pd.read_csv("./healthcare.csv")
X = df[NUMERIC + CATEGORICAL]
y = df[TARGET]

# Split first, so nothing learned from the test set leaks into training.
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# Fill missing values and encode text columns inside the pipeline,
# so they are learned from the training data only.
preprocess = ColumnTransformer([
    ("num", SimpleImputer(strategy="median"), NUMERIC),
    ("cat", Pipeline([
        ("impute", SimpleImputer(strategy="most_frequent")),
        ("encode", OneHotEncoder(handle_unknown="ignore")),
    ]), CATEGORICAL),
])

model = Pipeline([
    ("preprocess", preprocess),
    ("classifier", RandomForestClassifier(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        class_weight="balanced",
        random_state=42,
    )),
])

mlflow.sklearn.autolog()

with mlflow.start_run():
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    y_prob = model.predict_proba(X_test)[:, 1]  # AUC needs probabilities

    accuracy = accuracy_score(y_test, y_pred)
    auc = roc_auc_score(y_test, y_prob)

    mlflow.log_metric("test_accuracy", accuracy)
    mlflow.log_metric("test_auc", auc)

    print(f"Accuracy: {accuracy:.2f}")
    print(f"AUC: {auc:.2f}")

# Save the fitted pipeline so it can be reused for predictions.
os.makedirs("outputs", exist_ok=True)
joblib.dump(model, "outputs/model.joblib")