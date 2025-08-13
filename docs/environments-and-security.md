## Environments, cluster topology, and security controls

### Docker Compose locally vs. Kubernetes in prod
**Benefits of Docker Compose locally**
- Fast iteration: fewer moving parts and simpler networking
- Lower resource usage on developer laptops
- Easy to run DB/Redis alongside app without cluster overhead

**Tradeoffs**
- Drift risk: Compose is not a perfect mirror of Kubernetes manifests
- Networking, DNS, and service discovery differ; bugs can hide until K8s
- Autoscaling, resource limits/requests, and probes are not exercised
- Secrets management differs (env files vs. K8s Secrets/External Secrets)

Recommendation: Use Compose sparingly for local convenience but validate critical flows in a dev Kubernetes environment.

### Two clusters vs. one cluster with namespaces
**Two clusters (dev, prod)**
- Isolation: strong blast-radius reduction; separate control planes
- Security: cluster-level IAM, separate VPCs, distinct node groups
- Cost: higher baseline cost, duplicated infra
- Ops: more to manage; drift risk between clusters

**One cluster, two namespaces (dev, prod)**
- Cost: cheaper, shared control plane and nodes
- Simpler operations; fewer moving parts
- Weaker isolation: noisy-neighbor effects, shared cluster IAM
- Risk: misconfiguration could cross-impact environments

Recommendation: For HIPAA-oriented workloads, prefer two clusters. If cost-constrained, start with namespaces and plan a migration path to dual clusters.

### Locking down production changes via GitHub Actions
- Use protected branches and required reviews for `main` (or `release/*`)
- Require PR approvals to run `terraform apply` to prod (manual approval job)
- Configure OpenID Connect (OIDC) from GitHub to cloud provider for short-lived credentials
- Production cluster:
  - Disable direct `kubectl` access for humans; read-only logs only
  - Enforce admission policies (OPA/Gatekeeper or Kyverno) for resource limits, images from approved registries, and required labels/annotations
  - Use `ImagePullPolicy: IfNotPresent` with immutable image tags (digest pins)
  - External Secrets Operator with access scoped to prod secrets only
- Dev cluster:
  - Allow limited `kubectl` access for developers via group IAM
  - Enable sandbox namespaces for experiments

### Promotion strategy
- Dev deploys on merge to `main`
- Run smoke tests and small-batch runs
- Tag a release when ready; prod deployment only from tags
- Use the same Helm chart/kustomize overlays with explicit values for prod (resource requests/limits, autoscaling, PDBs, topology spread)
