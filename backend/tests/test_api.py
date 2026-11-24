def test_liveness(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_readiness(client):
    r = client.get("/api/health/ready")
    assert r.status_code == 200


def test_task_crud(client):
    r = client.post("/api/tasks", json={"title": "Write Terraform for VPC"})
    assert r.status_code == 201
    task = r.json()
    assert task["status"] == "todo"

    r = client.patch(f"/api/tasks/{task['id']}", json={"status": "done"})
    assert r.status_code == 200
    assert r.json()["status"] == "done"

    assert len(client.get("/api/tasks").json()) == 1

    assert client.delete(f"/api/tasks/{task['id']}").status_code == 204
    assert client.get(f"/api/tasks/{task['id']}").status_code == 404


def test_validation(client):
    assert client.post("/api/tasks", json={"title": ""}).status_code == 422
    assert client.post("/api/tasks", json={"title": "x", "status": "blocked"}).status_code == 422
