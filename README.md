Echo-Innovatech Cloud Environment
A fully automated 2-tier AWS environment: containerized web tier behind an ALB,isolated Multi-AZ PostgreSQL, Prometheus/Grafana monitoring with alerting,OpenVPN management plane — built and destroyed entirely by CI/CD.

Architecture
<img width="1052" height="1382" alt="architecture diagram final draft (used) drawio" src="https://github.com/user-attachments/assets/ce97a258-4acd-466f-8ecd-0d81a464a698" />

Stack
Terraform · AWS (eu-central-1) · Docker (Nginx + Gunicorn/Flask) · RDS PostgreSQL 17 (Multi-AZ)· Prometheus + Grafana + Node Exporter · GitHub Actions (self-hosted runner, OIDC) · OpenVPN

Deploy
Push to main → pipeline applies automatically. Destroy via the manual destroy workflow.

Docs
See the submitted documentation set (Test Plan, DevOps Guide) for procedures and evidence.

Key design decisions
Scaling on ALB requests-per-target (load test showed CPU was the wrong signal for this I/O-bound workload)
OIDC-federated pipeline with least-privilege app-* IAM scoping — zero stored credentials
Fully idempotent: destroy + rebuild reproduces the entire environment, self-seeding database included
