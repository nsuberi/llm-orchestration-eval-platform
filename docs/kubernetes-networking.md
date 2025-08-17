## Networking choices

This stack exposes the frontend publicly via an Application Load Balancer (ALB) while keeping the API internal to the cluster.

- Public entrypoint: an Ingress resource on the `frontend` Service with annotations to provision an internet‑facing ALB and terminate TLS using ACM for `evals.cookinupideas.com`.
- Internal services: `api` Service remains `ClusterIP` and is only reachable from inside the cluster. The frontend calls the API using the internal DNS name `http://api.<namespace>.svc.cluster.local`.
- DNS: `evals.cookinupideas.com` is an alias to the ALB hostname returned by the Ingress status. Terraform creates the Route 53 record after the ALB is provisioned.
- TLS: The ACM certificate is referenced by Ingress annotations so the ALB serves HTTPS. HTTP requests are redirected to HTTPS.

Operational notes
- The ALB hostname is only known after pods are Ready and the Ingress is reconciled. Terraform will first apply workloads, then create the DNS alias once the hostname is available.
- API remains private; do not expose it via a LoadBalancer or Ingress. Use `ClusterIP` and restrict network access to the frontend and internal jobs.
- To change the hostname, update the subdomain variable for DNS and the Ingress TLS hosts.
