import mlflow
import argparse
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, roc_auc_score
from sklearn.preprocessing import LabelEncoder

# Parse arguments
parser = argparse.ArgumentParser()
parser.add_argument('--n_estimators', type=int, default=50)
parser.add_argument('--max_depth', type=int, default=5)
args = parser.parse_args()

# Load data
df = pd.read_csv('./healthcare.csv')

# Encode text columns
le = LabelEncoder()
for col in df.columns:
    if df[col].dtype == 'object':
        df[col] = le.fit_transform(df[col])

# Fill missing values
df = df.fillna(df.median())

# Split data
X = df.drop('heart_disease', axis=1)
y = df['heart_disease']
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

# Start MLflow run
mlflow.sklearn.autolog()

with mlflow.start_run():
    model = RandomForestClassifier(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        class_weight='balanced',
        random_state=42
    )
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    auc = roc_auc_score(y_test, y_pred)

    mlflow.log_metric('accuracy', accuracy)
    mlflow.log_metric('auc', auc)

    print(f"Accuracy: {accuracy:.2f}")
    print(f"AUC: {auc:.2f}")
