#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
mkdir -p .local-certs
openssl req -x509 -newkey rsa:3072 -nodes -days 30 -sha256 \
  -keyout .local-certs/tls.key -out .local-certs/tls.crt \
  -subj '/CN=es-http.nexusdata.svc.cluster.local' \
  -addext 'subjectAltName=DNS:es-http.nexusdata.svc.cluster.local,DNS:es-headless.nexusdata.svc.cluster.local,DNS:es-witness.nexusdata.svc.cluster.local,DNS:localhost,IP:127.0.0.1'
cp .local-certs/tls.crt .local-certs/ca.crt
ELASTIC_PASSWORD="$(openssl rand -hex 24)"
KIBANA_PASSWORD="$(openssl rand -hex 24)"
printf 'ELASTIC_PASSWORD=%s\nKIBANA_PASSWORD=%s\n' "$ELASTIC_PASSWORD" "$KIBANA_PASSWORD" > .local-certs/passwords.env
kubectl -n nexusdata create secret generic nexusdata-credentials \
  --from-literal=elastic-password="$ELASTIC_PASSWORD" \
  --from-literal=kibana-password="$KIBANA_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n nexusdata create secret generic nexusdata-tls \
  --from-file=tls.key=.local-certs/tls.key \
  --from-file=tls.crt=.local-certs/tls.crt \
  --from-file=ca.crt=.local-certs/ca.crt \
  --dry-run=client -o yaml | kubectl apply -f -
echo 'Created local credentials and TLS Secrets. Never commit .local-certs.'
