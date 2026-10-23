#!/usr/bin/env bash
# Start minikube, build the image inside it, enable metrics-server and deploy.
set -euo pipefail
cd "$(dirname "$0")/.."

minikube start --nodes 2 --cpus 2 --memory 4096
minikube addons enable metrics-server
minikube image build -t self-healing-app:1.0.0 app

kubectl apply -k k8s/base
kubectl -n self-healing rollout status deployment/self-healing-app --timeout=180s
kubectl -n self-healing get pods -o wide
