# rag-secure-k8s

Asistent documentar bazat pe Retrieval-Augmented Generation (RAG), cu modele de
limbaj open-source rulate în cluster, pe Kubernetes. Lucrare de licență,
Universitatea Titu Maiorescu, Facultatea de Informatică.

Toate componentele AI rulează în cluster; aplicația nu trimite date către
servicii AI externe.

## Starea proiectului

| Componentă | Stare |
| --- | --- |
| `services/api` | serviciu FastAPI cu rutele de infrastructură (`/healthz`, `/readyz`, `/metrics`), teste, imagine Docker |
| `deploy/helm/rag` | chart Helm cu șabloanele pentru `api`: Deployment (probe, reguli de securitate, resurse) și Service |
| `.github/workflows/ci.yml` | pipeline: ruff și teste, gitleaks pe tot istoricul, scanare Trivy, apoi publicarea imaginii `api` în ghcr.io (`linux/amd64` și `linux/arm64`), cu SHA-ul commit-ului ca tag |
| `.github/dependabot.yml` | Dependabot propune săptămânal actualizări pentru acțiunile GitHub, imaginile din Dockerfile, bibliotecile Python și verificările pre-commit |
| `services/worker`, `services/web` | neimplementate |
| `infra/terraform` | neimplementat |
| `docs/uml` | diagramele UML ale sistemului (PlantUML) |

## Structura

```
services/
  api/            serviciul HTTP (FastAPI)
    app/          codul aplicației
    tests/        testele serviciului
    Dockerfile    imaginea, construită în două etape
  worker/         procesarea documentelor în fundal
  web/            interfața
deploy/
  helm/rag/       chart Helm
    Chart.yaml    descrierea chart-ului
    values.yaml   valorile implicite
    templates/    șabloanele manifestelor Kubernetes
infra/terraform/  infrastructura din Azure
tests/            teste la nivel de sistem (atacuri, evaluare)
docs/             diagrame și decizii de arhitectură
```

## Serviciul `api`, local

Necesită [uv](https://docs.astral.sh/uv/) și Docker.

```
cd services/api
uv sync                  # instalează bibliotecile în .venv
uv run pytest            # rulează testele
uv run ruff check .      # verifică codul
uv run ruff format .     # formatează codul
```

Imaginea:

```
docker build -t rag-api:dev .
docker run --rm --read-only -p 127.0.0.1:8000:8000 rag-api:dev
curl http://127.0.0.1:8000/healthz
```

Containerul rulează ca utilizator fără drepturi de administrator (UID 10001) și
funcționează cu sistemul de fișiere doar pentru citire.

## `api` într-un cluster local (k3d)

Necesită [k3d](https://k3d.io), `kubectl` și [Helm](https://helm.sh).

```
# Cluster cu un nod server și doi agenți. Traefik-ul livrat cu k3s e dezactivat;
# API server-ul e publicat doar pe 127.0.0.1.
k3d cluster create licenta --agents 2 --k3s-arg "--disable=traefik@server:0" --api-port 127.0.0.1:6550

kubectl create namespace rag

# Instalează chart-ul ca release-ul „rag" (sau îl actualizează, dacă există).
# Tag-ul imaginii e obligatoriu: SHA-ul unui commit de pe main pentru care
# pipeline-ul a publicat imaginea în ghcr.io.
helm upgrade --install rag deploy/helm/rag -n rag --set api.image.tag=$(git rev-parse HEAD)
kubectl rollout status deployment/api -n rag
```

Nodurile descarcă imaginea `ghcr.io/isaiagabriel-personal/rag-api` direct din
registry. Imaginea e publică și are două variante, `linux/amd64` și
`linux/arm64`; fiecare nod o ia pe cea potrivită procesorului său.

Clusterul se oprește și se pornește cu `k3d cluster stop licenta` și
`k3d cluster start licenta`. Repornit doar de Docker, nodul server poate rămâne
fără API server; aceleași două comenzi îl repară, fără pierdere de date.

Comenzi utile pentru chart:

```
helm lint deploy/helm/rag                  # verifică chart-ul
helm template rag deploy/helm/rag -n rag --set api.image.tag=test   # afișează manifestele generate, fără să le trimită
helm history rag -n rag                    # reviziile instalării
helm rollback rag <revizie> -n rag         # revine la o revizie anterioară
```

Verificare, printr-un tunel temporar de pe laptop până la Service:

```
kubectl port-forward service/api 8000:8000 -n rag
curl http://127.0.0.1:8000/healthz
```

Ce impune chart-ul containerului `api`:

- rulează ca utilizator neprivilegiat, cu sistem de fișiere doar pentru citire;
- fără capabilități Linux, fără escaladare de privilegii, cu filtrul seccomp implicit;
- fără tokenul contului de serviciu montat în pod;
- cereri și limite de procesor și memorie;
- probe de liveness (`/healthz`) și readiness (`/readyz`).
