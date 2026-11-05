#!/usr/bin/env bash
set -euo pipefail
N=nexusdata
kubectl get nodes -o wide
kubectl -n "$N" get pods -o wide
kubectl -n "$N" get pvc
NODE0="$(kubectl -n "$N" get pod es-0 -o jsonpath='{.spec.nodeName}')"
NODE1="$(kubectl -n "$N" get pod es-1 -o jsonpath='{.spec.nodeName}')"
[[ -n "$NODE0" && -n "$NODE1" && "$NODE0" != "$NODE1" ]] || { echo 'FAIL: ES data Pods are not on separate nodes'; exit 1; }
[[ "$NODE0" == nexusdata-cluster-worker || "$NODE0" == nexusdata-cluster-worker2 ]] || exit 1
[[ "$NODE1" == nexusdata-cluster-worker || "$NODE1" == nexusdata-cluster-worker2 ]] || exit 1
kubectl -n "$N" wait --for=condition=Ready pod/es-0 pod/es-1 --timeout=300s
kubectl -n "$N" rollout status deployment/es-witness --timeout=300s
kubectl -n "$N" rollout status deployment/logstash --timeout=300s
kubectl -n "$N" rollout status deployment/kibana --timeout=300s
for claim in data-es-0 data-es-1; do
  status="$(kubectl -n "$N" get pvc "$claim" -o jsonpath='{.status.phase}')"
  [[ "$status" == Bound ]] || { echo "FAIL: $claim status $status"; exit 1; }
done
echo "PASS: data Pods placed on distinct workers ($NODE0, $NODE1); PVCs bound; deployments ready"
