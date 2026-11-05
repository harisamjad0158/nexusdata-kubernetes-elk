# NexusData — Enterprise Real-Time Log Analytics & Event Streaming Platform

A security-conscious **KinD portfolio reference deployment** using Elasticsearch 8.11.1, Logstash, and Kibana on **one control-plane and two worker nodes**. It demonstrates persistence, strict worker anti-affinity, TLS, HTTP event ingestion, and verification. **Not production-ready without the hardening noted below.**

## Important engineering decisions

- Two Elasticsearch **data replicas** are scheduled strictly apart, one on each worker. A **third, voting-only master-eligible node** runs on the control-plane to support a three-voter quorum. The witness uses `emptyDir` and is **not durable**; for production, make its metadata persistent and use independent failure domains.
- `rancher.io/local-path` is the **KinD local-path provisioner** when installed. The StorageClass uses `Retain`, but host-path volumes are **node-local**: a lost worker cannot access the other worker's PV, and retained PVs may require manual cleanup/rebinding. This is not shared or cloud HA storage.
- Elasticsearch **HTTP and transport TLS** are enabled with a short-lived locally generated certificate. Passwords are generated locally and injected through Kubernetes Secrets. Kubernetes Secret objects are **base64 encoded, not automatically encrypted at rest**.
- The ingestion port **5044 uses Logstash HTTP input**, not Beats protocol. HTTP input is intentionally localhost-accessible via port-forward only; it is **not authenticated or TLS-protected** on the client side. For production add authenticated TLS ingestion, authorization, and network policies.
- The Elasticsearch `elastic` superuser is used by Logstash for this local demonstration. Replace with a least-privilege ingestion role for production.
- This is an **ELK log analytics pipeline**, not a durable message broker or full event streaming platform (Kafka/Redpanda would add replay, offsets, and broker-level durability).

## Resource prerequisites

Recommended: **at least 12 GiB RAM available to Docker**, 4+ CPU cores, and free disk space for images and 2 x 5 GiB PVC requests. Actual host usage depends on KinD, OS and workload. On Linux set `sudo sysctl -w vm.max_map_count=262144` (persist separately if needed).

## Directory structure

```text
nexusdata/
├── manifests/
│   ├── 00-base.yaml
│   ├── 01-config.yaml
│   ├── 02-elasticsearch.yaml
│   ├── 03-processing.yaml
│   └── 04-kibana.yaml
├── scripts/
│   ├── prepare-secrets.sh
│   ├── configure-kibana-user.sh
│   └── ingest-test.sh
├── tests/
│   └── verify.sh
└── .gitignore
```

## Deployment order

```bash
kubectl config use-context kind-nexusdata-cluster
kubectl get nodes -o wide
kubectl get storageclass
# The class must use provisioner rancher.io/local-path.
# If not installed, install the official KinD/local-path provisioner first;
# do not apply PVCs until it exists.
sudo sysctl -w vm.max_map_count=262144
kubectl apply -f manifests/00-base.yaml
kubectl apply -f manifests/01-config.yaml
bash scripts/prepare-secrets.sh
kubectl apply -f manifests/02-elasticsearch.yaml
kubectl -n nexusdata rollout status statefulset/es --timeout=10m
kubectl -n nexusdata rollout status deployment/es-witness --timeout=10m
kubectl -n nexusdata get pods -o wide
kubectl -n nexusdata get pvc,pv
```

**Terminal A:**

```bash
kubectl -n nexusdata port-forward svc/es-http 9200:9200 --address=127.0.0.1
```

**Terminal B:**

```bash
source .local-certs/passwords.env
curl --cacert .local-certs/ca.crt -u "elastic:$ELASTIC_PASSWORD" \
  https://localhost:9200/_cluster/health?pretty
bash scripts/configure-kibana-user.sh
kubectl apply -f manifests/03-processing.yaml
kubectl apply -f manifests/04-kibana.yaml
kubectl -n nexusdata rollout status deployment/logstash --timeout=10m
kubectl -n nexusdata rollout status deployment/kibana --timeout=10m
bash tests/verify.sh
```

**Terminal C (Logstash HTTP ingestion):**

```bash
kubectl -n nexusdata port-forward svc/logstash 5044:5044 --address=127.0.0.1
```

**Terminal D (Kibana):**

```bash
kubectl -n nexusdata port-forward svc/kibana 5601:5601 --address=127.0.0.1
```

With all three port-forwards active, run in Terminal B:

```bash
bash scripts/ingest-test.sh
```

Open **http://localhost:5601** and log in as **elastic** with the locally generated `ELASTIC_PASSWORD` from `.local-certs/passwords.env`. In **Discover**, create a data view for `nexusdata-events*` with time field `@timestamp`, then search for `event_type: purchase` or the `event_id` from the test output. `kibana_system` is an internal service identity, **not** a browser login.

## Placement and storage verification

```bash
kubectl -n nexusdata get pods -o wide
kubectl -n nexusdata get pvc
kubectl get pv
kubectl -n nexusdata describe pod es-0
kubectl -n nexusdata describe pod es-1
```

`es-0` and `es-1` must show **different worker node names**. PVCs must be **Bound**. Confirm the Elasticsearch index has replicas and the cluster health is `green` (or investigate if `yellow`). For Elasticsearch's actual replica copies, use:

```bash
source .local-certs/passwords.env
curl --cacert .local-certs/ca.crt -u "elastic:$ELASTIC_PASSWORD" \
  'https://localhost:9200/_cat/shards/nexusdata-events?v'
```

**Persistence check:** Ingest an event, delete `es-0` Pod, wait for its recreation and re-run the search. This verifies Pod restart persistence on the **same worker**, not host-loss recovery.

## Controlled failover drill

1. Record `_cluster/health`, `_cat/nodes` and `_cat/shards` before disruption.
2. `kubectl cordon nexusdata-cluster-worker` to prevent new Pods scheduling there.
3. Delete `es-0` **only for a controlled test**: `kubectl -n nexusdata delete pod es-0`.
4. The StatefulSet Pod may remain **Pending** while its worker is cordoned; with strict anti-affinity it must not move to the other worker. Check whether Elasticsearch remains writable with the surviving data node and witness. Availability is conditional on healthy quorum and shard placement.
5. `kubectl uncordon nexusdata-cluster-worker`, wait for Pod recovery and green health. Avoid draining/killing a worker during active production workloads.

**Do not confuse Pod deletion with a node failure.** Local-path volumes are tied to a node, and a genuinely lost node may require manual volume recovery. A single control-plane is also a single point of failure for the Kubernetes API.

## Security and operational limitations

- No secret encryption-at-rest guarantee: enable Kubernetes API-server encryption provider/KMS for real environments.
- No external access is configured: port-forwarding only, on loopback.
- Elasticsearch TLS certificate is locally generated, shared by nodes, expires in 30 days, and is for demonstrations. Production should use cert-manager or a trusted CA with per-node certificates and rotation.
- No PodDisruptionBudget, topology-spread policy for Logstash/Kibana, dedicated service-account role, persistent Logstash queue, authentication on ingestion, backup/snapshot repository, or monitoring stack is included.
- `cluster.initial_master_nodes` is for **initial cluster bootstrapping** only. Remove it after the cluster forms and before subsequent long-term operation or re-bootstrap procedures; never casually re-bootstrap an existing cluster.
- A third **voting-only** Elasticsearch node participates in voting but cannot become elected master. This design can tolerate one data-node loss if quorum is healthy, but it is still a **local lab** rather than an enterprise multi-AZ production topology.
- All examples are intended for a dedicated, trusted lab cluster; review RBAC, security context and admission policies before reuse elsewhere.
