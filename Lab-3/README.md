# Lab 3: Monitoring, Logging & DevSecOps

**Student:** Saksham Kumar (2301730151)

The taskboard service, now with structured JSON logs, Prometheus metrics and a
runtime feature flag. It is provisioned with Ansible and Terraform, monitored with
Prometheus and Grafana, logged through Filebeat, Logstash, Elasticsearch and Kibana,
and checked by a security pipeline.

## Layout

| Path | Purpose |
|---|---|
| `app/app.py` | Flask app on port 8000: `/` (HTML), `/health`, `/api/tasks`, `/api/flags`, `/metrics` |
| `tests/test_app.py` | Unit tests: flags, metrics, JSON logs, HTML escaping |
| `tests/e2e/test_browser.py` | Selenium (headless Chrome) tests against a running app |
| `tests/load/locustfile.py` | Locust load test |
| `ansible/` | Inventory, playbook and `taskboard` role: installs Docker, deploys the stack, verifies health |
| `terraform/` | Docker provider: builds the image, creates a network and N replicas on ports 8100+ |
| `observability/` | Compose stack: app, Prometheus (with alert rules), Grafana (provisioned dashboard), and ELK plus Filebeat behind a `logging` profile |
| `../.github/workflows/lab3-devsecops.yml` | Tests, pip-audit, Bandit, Semgrep, Hadolint, Trivy (filesystem and image), non-root check |

## The feature flag

`priority_tasks` controls whether tasks accept a `priority` (0–5) and are sorted by it.
It is read on every request from `FLAGS_FILE`, falling back to the `FEATURE_PRIORITY_TASKS`
environment variable. Edit `observability/flags.json` while the stack is running and the
change is live immediately. The `taskboard_feature_flag_enabled` metric and the badge on `/` both follow it.

## Runbook (capture your own output and screenshots)

**Task 1 – Ansible** (Ubuntu or WSL2, run from `Lab-3/`):
```bash
sudo apt install -y ansible
ansible-playbook -i ansible/inventory.ini ansible/site.yml --syntax-check
ansible-playbook -i ansible/inventory.ini ansible/site.yml --check
ansible-playbook -i ansible/inventory.ini ansible/site.yml -K
ansible-playbook -i ansible/inventory.ini ansible/site.yml -K   # second run shows changed=0 (idempotent)
ansible-playbook -i ansible/inventory.ini ansible/site.yml -K -e feature_priority_tasks=true
```

**Task 2 – Terraform**:
```bash
cd terraform
terraform init
terraform plan -var replicas=2
terraform apply -var replicas=2 -auto-approve
terraform output urls
terraform apply -var replicas=4 -auto-approve    # scale out
terraform destroy -auto-approve
```
On Docker Desktop for Windows, add `-var 'docker_host=npipe:////./pipe/docker_engine'`.

**Task 3 – Centralized logging**:
```bash
cd observability
docker compose --profile logging up -d --build
for i in $(seq 1 20); do curl -s -X POST -H 'Content-Type: application/json' -d "{\"title\":\"log $i\"}" localhost:8000/api/tasks; done
curl -s 'localhost:9200/_cat/indices/lab3-logs-*?v'
```
In Kibana (http://localhost:5601), create a data view for `lab3-logs-*` and open Discover. Filter with
`app.event : "task_created"` or `app.status >= 400`.

**Task 4 – DevSecOps**: push any change under `Lab-3/` and capture the Actions run. To run it locally:
`pip install pip-audit bandit && pip-audit -r requirements.txt && bandit -r app -ll`.
To show a gate failing, add `flask==2.0.0` to `requirements.txt` on a branch, then revert it.

**Task 5 – Prometheus and Grafana**:
```bash
cd observability && docker compose up -d --build
```
Open Prometheus at http://localhost:9090 (*Status → Targets*, then query `taskboard_http_requests_total`)
and Grafana at http://localhost:3000 (admin / `change-me`, or your own `GRAFANA_ADMIN_PASSWORD`).
The *Lab 3 → Taskboard Overview* dashboard is provisioned automatically. Run the load test (Task 6) while you watch it.

**Task 6 – Feature flags, load and Selenium**:
```bash
pip install -r requirements-dev.txt
python -m pytest -v                                    # unit tests
BASE_URL=http://localhost:8000 python -m pytest tests/e2e -v
locust -f tests/load/locustfile.py --headless -u 20 -r 5 -t 1m --host http://localhost:8000 --csv reports/load
```
Flip `priority_tasks` in `observability/flags.json`, then re-run the Selenium tests and show the badge and the metric change.

**Task 7 – Report**: write it up from the output and screenshots you captured above.
