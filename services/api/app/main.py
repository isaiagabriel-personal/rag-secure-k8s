"""Serviciul api: punctul de intrare HTTP al aplicației.

Rutele de infrastructură, folosite de Kubernetes și de Prometheus:

- /healthz  liveness: „procesul trăiește?"
- /readyz   readiness: „poate primi cereri?"
- /metrics  contoare citite de Prometheus

Pornit de uvicorn: uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

# Aplicația. uvicorn o găsește după numele „app" (app.main:app).
app = FastAPI()

# Numără fiecare cerere HTTP (rută, cod de răspuns, durată) și publică
# rezultatele pe ruta /metrics, de unde le citește Prometheus.
Instrumentator().instrument(app).expose(app)


@app.get("/healthz")
def healthz():
    # Liveness. Kubernetes se uită doar la codul 200; dacă nu-l primește,
    # repornește containerul. Nu verifică nicio dependență, intenționat.
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    # Readiness. Dacă nu răspunde 200, Kubernetes nu mai trimite cereri spre
    # acest pod, dar nu-l repornește. Serviciul nu are încă dependențe externe,
    # deci răspunde mereu 200.
    return {"status": "ready"}
