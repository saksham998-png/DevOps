"""Load test:
    locust -f tests/load/locustfile.py --headless -u 20 -r 5 -t 1m --host http://localhost:8000 --csv reports/load
"""
import random

from locust import HttpUser, between, task


class TaskboardUser(HttpUser):
    wait_time = between(0.5, 2)

    @task(5)
    def list_tasks(self):
        self.client.get("/api/tasks")

    @task(2)
    def create_task(self):
        self.client.post("/api/tasks", json={"title": f"load-{random.randint(1, 10_000)}",
                                             "priority": random.randint(0, 5)})

    @task(1)
    def home(self):
        self.client.get("/")

    @task(1)
    def health(self):
        self.client.get("/health")
