#!/usr/bin/env bash
# Failure simulator for the self-healing demo.
# Usage: scripts/simulate-failure.sh <kill-pod|kill-all|crash|liveness|readiness|drain|load|watch>
set -euo pipefail
NS=${NS:-self-healing}
APP=${APP:-self-healing-app}
SEL="app=$APP"

pick_pod() { kubectl -n "$NS" get pods -l "$SEL" -o jsonpath='{.items[0].metadata.name}'; }

call() { # call <pod> <METHOD> <path>  (uses port-forward to hit one specific pod)
  local pod=$1 method=$2 path=$3 port=18080
  kubectl -n "$NS" port-forward "pod/$pod" "$port:8080" >/dev/null 2>&1 &
  local pf=$!
  sleep 2
  curl -s -X "$method" "http://127.0.0.1:$port$path" || true
  echo
  kill "$pf" 2>/dev/null || true
}

case "${1:-}" in
  kill-pod)
    POD=$(pick_pod)
    echo "Deleting pod $POD; the ReplicaSet will create a replacement."
    kubectl -n "$NS" delete pod "$POD" --wait=false ;;
  kill-all)
    echo "Deleting ALL pods; watch the ReplicaSet bring 3 back."
    kubectl -n "$NS" delete pods -l "$SEL" --wait=false ;;
  crash)
    POD=$(pick_pod)
    echo "Crashing the process in $POD; RESTARTS should go up by 1."
    call "$POD" POST /crash ;;
  liveness)
    POD=$(pick_pod)
    echo "Breaking /healthz in $POD; the liveness probe will restart the container in ~15s."
    call "$POD" POST /fail/liveness ;;
  readiness)
    POD=$(pick_pod)
    echo "Breaking /readyz in $POD; it will go 0/1 READY and leave the Service endpoints."
    call "$POD" POST /fail/readiness
    echo "Restore with: kubectl -n $NS delete pod $POD   (or wait, then call /recover/readiness)" ;;
  drain)
    NODE=$(kubectl -n "$NS" get pod "$(pick_pod)" -o jsonpath='{.spec.nodeName}')
    echo "Draining node $NODE; the PodDisruptionBudget keeps at least 2 pods available."
    kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=120s
    echo "Undo with: kubectl uncordon $NODE" ;;
  load)
    echo "Generating CPU load for 2 minutes; watch the HPA scale out."
    kubectl -n "$NS" run load-gen --rm -i --restart=Never --image=busybox:1.36 -- \
      /bin/sh -c "end=\$((\$(date +%s)+120)); while [ \$(date +%s) -lt \$end ]; do wget -q -O- http://$APP/burn >/dev/null & sleep 0.2; done; wait" ;;
  watch)
    watch -n 1 "kubectl -n $NS get pods -l $SEL -o wide; echo; kubectl -n $NS get hpa,pdb; echo; kubectl -n $NS get endpoints $APP" ;;
  *)
    sed -n '2,3p' "$0"; exit 1 ;;
esac
