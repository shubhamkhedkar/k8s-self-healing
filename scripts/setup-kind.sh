#!/usr/bin/env bash
# Create a local kind cluster, build the image, load it, install metrics-server and deploy.
set -euo pipefail
CLUSTER=${CLUSTER:-self-healing}
cd "$(dirname "$0")/.."

kind create cluster --name "$CLUSTER" --config scripts/kind-config.yaml
docker build -t self-healing-app:1.0.0 app
kind load docker-image self-healing-app:1.0.0 --name "$CLUSTER"

# metrics-server is needed for the HPA; --kubelet-insecure-tls is required on kind.
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl apply -k k8s/base
kubectl -n self-healing rollout status deployment/self-healing-app --timeout=180s
kubectl -n self-healing get pods -o wide
