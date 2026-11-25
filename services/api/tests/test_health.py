"""Testele serviciului api pentru rutele de infrastructură.

Rulează fără server pornit și fără rețea: TestClient apelează aplicația
direct, în memorie. Se rulează cu: uv run pytest   (din services/api)
"""

from fastapi.testclient import TestClient

from app.main import app

# Client de test legat direct de aplicație.
client = TestClient(app)


def test_healthz():
    # Liveness: răspunde 200 cu corpul așteptat.
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readyz():
    # Readiness: rută separată de /healthz, cu alt răspuns.
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_metrics():
    # Facem întâi o cerere, ca să existe ce număra; apoi verificăm că
    # /metrics publică acel contor în formatul Prometheus.
    client.get("/healthz")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_requests_total" in response.text
