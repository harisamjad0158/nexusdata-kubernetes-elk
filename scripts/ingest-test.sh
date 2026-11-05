#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .local-certs/passwords.env
EVENT_ID="nexus-$(date +%s)-$$"
printf 'Sending event %s\n' "$EVENT_ID"
curl --fail --show-error --silent -X POST 'http://127.0.0.1:5044/' \
  -H 'Content-Type: application/json' \
  -d "{"event_id":"$EVENT_ID","event_type":"purchase","service":"ecommerce","order_id":"ORD-2026-1001","amount":129.99,"currency":"EUR","@timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}"
echo
sleep 5
curl --fail --silent --show-error --cacert .local-certs/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H 'Content-Type: application/json' \
  'https://localhost:9200/nexusdata-events/_search?pretty' \
  -d "{"query":{"term":{"event_id.keyword":"$EVENT_ID"}}}"
