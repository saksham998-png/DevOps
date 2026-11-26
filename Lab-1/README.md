# Lab 1: DevOps Foundations & Continuous Integration

**Student:** Saksham Kumar (2301730151)

A small task-tracking service (**taskboard**) built, tested, packaged and deployed by a
Jenkins pipeline that pulls from GitHub.

## Layout

| Path | Purpose |
|---|---|
| `app/app.py` | Flask service: `/`, `/health`, `/api/tasks` (list, create, update, delete) |
| `tests/test_app.py` | 6 pytest tests, JUnit XML for Jenkins |
| `Dockerfile` | `python:3.12-slim`, gunicorn, runs as non-root UID 10001, has a HEALTHCHECK |
| `scripts/deploy.sh` | Builds the image, swaps the container, waits for `/health`, rolls back on failure |
| `Jenkinsfile` | Checkout → Build → Test → Package → Deploy → Smoke Test |

## Run it locally

```bash
cd Lab-1
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python -m pytest -v
python app/app.py           # http://localhost:5000
```

## Runbook (do these yourself and capture the real output for your report)

### Q4 – Install and configure Git and Jenkins on Ubuntu

```bash
sudo apt update && sudo apt install -y git openjdk-17-jre python3-venv docker.io curl
git --version && java -version
git config --global user.name "Saksham Kumar"
git config --global user.email "2301730151@krmu.edu.in"
git config --global init.defaultBranch main
git config --list --show-origin

sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
sudo apt update && sudo apt install -y jenkins
sudo systemctl enable --now jenkins
systemctl status jenkins --no-pager
sudo usermod -aG docker jenkins && sudo systemctl restart jenkins   # lets the pipeline run docker
sudo cat /var/lib/jenkins/secrets/initialAdminPassword               # then open http://<host>:8080
```

Screenshot: `git --version`, `git config --list`, `systemctl status jenkins`, the Jenkins dashboard.

### Q5 – Version control with Git

```bash
git clone https://github.com/saksham998-png/DevOps.git && cd DevOps
git checkout -b feature/task-delete
# make a real change, e.g. edit app/app.py or add a test
git add -A && git commit -m "feat(lab1): <describe your change>"
git checkout main
git merge --no-ff feature/task-delete -m "merge: feature/task-delete"
git push origin main feature/task-delete
git log --graph --oneline --all --decorate
```

### Q6 – Basic Jenkins pipeline pulling from GitHub

1. Jenkins → **New Item** → *Pipeline* → name `taskboard-lab1`.
2. *Build Triggers*: tick **GitHub hook trigger for GITScm polling**.
3. *Pipeline*: **Pipeline script from SCM** → Git → `https://github.com/saksham998-png/DevOps.git`,
   branch `*/main`, Script Path `Lab-1/Jenkinsfile`.
4. GitHub repo → Settings → Webhooks → `http://<jenkins-host>:8080/github-webhook/`, content type
   `application/json`, *push* events. (If Jenkins is on your laptop, use a tunnel such as ngrok, or rely on the `pollSCM` fallback.)
5. Push a commit and screenshot the build starting automatically and its console output.

### Q7 – Jenkinsfile stages

Explain each stage of `Jenkinsfile`, then screenshot the **Stage View** of a green build and the **Test Result** page.

### Q3 – Automated deployment

- Triggers: `githubPush()` and `pollSCM('H/15 * * * *')`.
- Deploy: `scripts/deploy.sh` (build, replace container, health-check, rollback).
- Post-build actions: JUnit report, archived `dist/*.tar.gz`, workspace cleanup.

To show the rollback working, temporarily break `/health` (for example return a 500), push, and capture the failed build where `deploy.sh` restores the previous image.

### Q1 and Q2 – Records and CI/CD workflow report

Keep a log of every command you ran with its output (`script lab1-session.log` records a terminal session),
plus the build durations and test counts from your own Jenkins builds. Use those real numbers in the report.
