#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .local-certs/passwords.env
# Run after port-forwarding svc/es-http 9200:9200 in another terminal.
curl --fail --silent --show-error --cacert .local-certs/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -X POST 'https://localhost:9200/_security/user/kibana_system/_password' \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"password":"%s"}' "$KIBANA_PASSWORD")"
echo; echo 'Configured kibana_system password.'
