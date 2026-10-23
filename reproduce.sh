#!/usr/bin/env bash
# Run Report #RR11, §4 (Reproduction). Every line of the report's §4 block appears below, in order and exactly as printed;
# each step then runs the commands its lines print, one step per invocation. Steps 3 and 4 make one change per invocation,
# because the report polls for 120 s after each change; `poll` runs the three poll commands once (the report repeats them
# every 5 s). rr11.yaml is the report's manifest, byte for byte.
#   ./reproduce.sh 0 | 1 | 2 | 3-annotation | 3-label | 3-spec | 4-hourly | 4-onchange | poll | 5
# Per the report (§3), the last poll command (logs --since=10s | grep -E 'skipping refresh|reconciled secret') exits 1 when
# no such line was logged in the last 10 s — the usual case at the end of a window — so the script does not stop on a non-zero
# exit.
set -uo pipefail
cd "$(dirname "$0")"

step_0() {
# 0. Bring up a kind cluster (node Kubernetes v1.36.4) and install External Secrets Operator v2.11.0 from
#    the official chart, with the controller's log level at debug so that "skipping refresh" is logged.
#    Confirm the controller, webhook and cert-controller pods are Ready before measuring.
#      kind create cluster --name rr11 --image kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
#      helm install external-secrets https://github.com/external-secrets/external-secrets/releases/download/helm-chart-2.11.0/external-secrets-2.11.0.tgz -n external-secrets --create-namespace --set log.level=debug --wait
#      kubectl -n external-secrets get pods
kind create cluster --name rr11 --image kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
helm install external-secrets https://github.com/external-secrets/external-secrets/releases/download/helm-chart-2.11.0/external-secrets-2.11.0.tgz -n external-secrets --create-namespace --set log.level=debug --wait
kubectl -n external-secrets get pods
}

step_1() {
# 1. T0: apply rr11.yaml (below) and wait until all three ExternalSecrets are Ready; all three Secrets
#    hold token=value-1. Record each ExternalSecret's refreshTime and syncedResourceVersion.
#      kubectl apply -f rr11.yaml
#      kubectl -n rr11 wait --for=condition=Ready es --all --timeout=120s
kubectl apply -f rr11.yaml
kubectl -n rr11 wait --for=condition=Ready es --all --timeout=120s
}

step_2() {
# 2. Change the value in the store, then poll for 120 s (every 5 s; poll commands below).
#      kubectl -n rr11 patch secretstore rr11-fake --type=json -p '[{"op":"replace","path":"/spec/provider/fake/data/0/value","value":"value-2"}]'
kubectl -n rr11 patch secretstore rr11-fake --type=json -p '[{"op":"replace","path":"/spec/provider/fake/data/0/value","value":"value-2"}]'
}

step_3_annotation() {
# 3. The FAQ's manual refresh on es-zero (refreshInterval: 0s), one change at a time, polling for 120 s
#    after each: an annotation, a label, and a spec change that adds a new data key mapped to the same store key.
#      kubectl -n rr11 annotate es es-zero force-sync=$(date +%s) --overwrite
#      kubectl -n rr11 label es es-zero rr11/probe=1 --overwrite
#      kubectl -n rr11 patch es es-zero --type=json -p '[{"op":"add","path":"/spec/data/-","value":{"secretKey":"token2","remoteRef":{"key":"/rr11/token"}}}]'
kubectl -n rr11 annotate es es-zero force-sync=$(date +%s) --overwrite
}

step_3_label() {
kubectl -n rr11 label es es-zero rr11/probe=1 --overwrite
}

step_3_spec() {
kubectl -n rr11 patch es es-zero --type=json -p '[{"op":"add","path":"/spec/data/-","value":{"secretKey":"token2","remoteRef":{"key":"/rr11/token"}}}]'
}

step_4_hourly() {
# 4. The same annotation change on the two comparison ExternalSecrets, polling for 120 s after each.
#      kubectl -n rr11 annotate es es-hourly force-sync=$(date +%s) --overwrite
#      kubectl -n rr11 annotate es es-onchange force-sync=$(date +%s) --overwrite
kubectl -n rr11 annotate es es-hourly force-sync=$(date +%s) --overwrite
}

step_4_onchange() {
kubectl -n rr11 annotate es es-onchange force-sync=$(date +%s) --overwrite
}

poll() {
# Poll (every 5 s): each ExternalSecret's generation, refreshTime, syncedResourceVersion and Ready
# status; each target Secret's keys, decoded values and resourceVersion; the controller's
# "skipping refresh" and "reconciled secret" lines.
#      kubectl -n rr11 get es -o custom-columns='NAME:.metadata.name,GEN:.metadata.generation,REFRESHED:.status.refreshTime,SYNCED_RV:.status.syncedResourceVersion,READY:.status.conditions[?(@.type=="Ready")].status'
#      for s in es-zero-secret es-hourly-secret es-onchange-secret; do kubectl -n rr11 get secret $s -o go-template='{{.metadata.name}} rv={{.metadata.resourceVersion}}{{range $k, $v := .data}} {{$k}}={{$v | base64decode}}{{end}}{{"\n"}}'; done
#      kubectl -n external-secrets logs deploy/external-secrets --since=10s | grep -E 'skipping refresh|reconciled secret'
kubectl -n rr11 get es -o custom-columns='NAME:.metadata.name,GEN:.metadata.generation,REFRESHED:.status.refreshTime,SYNCED_RV:.status.syncedResourceVersion,READY:.status.conditions[?(@.type=="Ready")].status'
for s in es-zero-secret es-hourly-secret es-onchange-secret; do kubectl -n rr11 get secret $s -o go-template='{{.metadata.name}} rv={{.metadata.resourceVersion}}{{range $k, $v := .data}} {{$k}}={{$v | base64decode}}{{end}}{{"\n"}}'; done
kubectl -n external-secrets logs deploy/external-secrets --since=10s | grep -E 'skipping refresh|reconciled secret'
}

step_5() {
# 5. Delete the test cluster (our cluster only).
#      kind delete cluster --name rr11
kind delete cluster --name rr11
}

case "${1:-}" in
  0) step_0 ;;
  1) step_1 ;;
  2) step_2 ;;
  3-annotation) step_3_annotation ;;
  3-label) step_3_label ;;
  3-spec) step_3_spec ;;
  4-hourly) step_4_hourly ;;
  4-onchange) step_4_onchange ;;
  poll) poll ;;
  5) step_5 ;;
  *) echo "usage: $0 0 | 1 | 2 | 3-annotation | 3-label | 3-spec | 4-hourly | 4-onchange | poll | 5  (one step per run; see README)"; exit 2 ;;
esac
