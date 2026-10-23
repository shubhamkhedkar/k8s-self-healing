#!/usr/bin/env bash
set -euo pipefail
kubectl delete namespace self-healing --ignore-not-found
echo "To remove the clusters too: kind delete cluster --name self-healing   or   minikube delete"
