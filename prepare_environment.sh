#!/bin/bash

# Copyright 2017 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
export REGION=${ZONE::-2}
echo "Creating quiz-account Service Account"
gcloud iam service-accounts create quiz-account --display-name "Quiz Account"
gcloud iam service-accounts keys create key.json --iam-account=quiz-account@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com

echo "Setting quiz-account IAM Role"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID --member serviceAccount:quiz-account@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com --role roles/owner

echo "Creating Datastore/App Engine instance"
gcloud app create --region "us-central"

echo "Creating bucket: gs://$DEVSHELL_PROJECT_ID-media"
gsutil mb gs://$DEVSHELL_PROJECT_ID-media

echo "Exporting GCLOUD_PROJECT and GCLOUD_BUCKET"
export GCLOUD_PROJECT=$DEVSHELL_PROJECT_ID
export GCLOUD_BUCKET=$DEVSHELL_PROJECT_ID-media

echo "Creating virtual environment"
mkdir ~/venvs
virtualenv -p python3 ~/venvs/developingapps
source ~/venvs/developingapps/bin/activate

echo "Installing Python libraries"
pip install --upgrade pip
pip install -r requirements.txt

echo "Creating Datastore entities"
python add_entities.py

echo "Export credentials key.json"
export GOOGLE_APPLICATION_CREDENTIALS=key.json

echo "Creating Cloud Pub/Sub topic"
gcloud pubsub topics create feedback
gcloud pubsub subscriptions create worker-subscription --topic feedback

echo "Creating Cloud Spanner Instance, Database, and Table"
gcloud spanner instances create quiz-instance --config=regional-us-central1 --description="Quiz instance" --nodes=1
gcloud spanner databases create quiz-database --instance quiz-instance --ddl "CREATE TABLE Feedback ( feedbackId STRING(100) NOT NULL, email STRING(100), quiz STRING(20), feedback STRING(MAX), rating INT64, score FLOAT64, timestamp INT64 ) PRIMARY KEY (feedbackId);"


echo "Creating Container Engine cluster"
gcloud container clusters create quiz-cluster --zone $ZONE --scopes cloud-platform
gcloud container clusters get-credentials quiz-cluster --zone $ZONE


echo "Building Containers"
gcloud builds submit -t gcr.io/$DEVSHELL_PROJECT_ID/quiz-frontend ./frontend/
gcloud builds submit -t gcr.io/$DEVSHELL_PROJECT_ID/quiz-backend ./backend/

export GCR_FRONTEND="gcr.io/$DEVSHELL_PROJECT_ID/quiz-frontend"
export GCR_BACKEND="gcr.io/$DEVSHELL_PROJECT_ID/quiz-backend"
echo "Deploying to Container Engine"
sed -i -e "s/\[GCLOUD_PROJECT\]/$DEVSHELL_PROJECT_ID/g" ./frontend-deployment.yaml
sed -i -e "s/\[GCLOUD_BUCKET\]/$GCLOUD_BUCKET/g" ./frontend-deployment.yaml
sed -i -e "s#\[FRONTEND_IMAGE_IDENTIFIER\]#$GCR_FRONTEND#g" ./frontend-deployment.yaml

sed -i -e "s/\[GCLOUD_PROJECT\]/$DEVSHELL_PROJECT_ID/g" ./backend-deployment.yaml
sed -i -e "s/\[GCLOUD_BUCKET\]/$GCLOUD_BUCKET/g" ./backend-deployment.yaml
sed -i -e "s#\[BACKEND_IMAGE_IDENTIFIER\]#$GCR_BACKEND#g" ./backend-deployment.yaml
kubectl create -f ./frontend-deployment.yaml
kubectl create -f ./backend-deployment.yaml
kubectl create -f ./frontend-service.yaml

echo "Project ID: $DEVSHELL_PROJECT_ID"
