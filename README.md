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
| `deploy/helm/rag` | chart Helm cu șabloanele pentru `api`: Deployment (probe, reguli de securitate, resurse), Service și regula de rutare (HTTPRoute) |
| `deploy/platform` | setările componentelor de platformă instalate în cluster: Traefik, proxy-ul invers de la intrare |
| `deploy/local`, `scripts/local-up.sh` | descrierea clusterului local (k3d) și scriptul care îl construiește de la zero |
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
  platform/       valorile chart-urilor de platformă (Traefik)
  local/          descrierea clusterului local, pentru k3d
scripts/          pornirea mediului local
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

## Mediul local (k3d)

### Unelte necesare

Se instalează o singură dată, pe calculator. Versiunile sunt cele pe care a
fost probat proiectul (macOS, procesor arm64).

| Unealtă | Versiune | La ce folosește |
| --- | --- | --- |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | 29.1 | rulează containerele; nodurile clusterului local sunt containere |
| [k3d](https://k3d.io) | 5.9 | creează clusterul local |
| `kubectl` | 1.34 | clientul pentru cluster (vine și cu Docker Desktop) |
| [Helm](https://helm.sh) | 4.3 | instalează chart-urile |
| [uv](https://docs.astral.sh/uv/) | 0.13 | bibliotecile Python și testele serviciilor |
| `git` | | SHA-ul commit-ului e tag-ul imaginii |

Cu Homebrew: `brew install k3d helm uv`, plus Docker Desktop.

### Pornire

```
scripts/local-up.sh
```

Scriptul poate fi rulat de oricâte ori; face doar ce lipsește. În ordine:

1. verifică uneltele și că Docker rulează;
2. creează clusterul descris în `deploy/local/k3d-config.yaml` (un nod server,
   doi agenți) sau îl pornește, dacă există;
3. instalează tipurile de obiecte ale standardului Gateway API;
4. instalează Traefik, cu valorile din `deploy/platform/traefik-values.yaml`;
5. instalează aplicația (chart-ul `deploy/helm/rag`, release-ul `rag`).

Imaginea `api` e descărcată din ghcr.io; tag-ul e SHA-ul ultimului commit de pe
`main` cunoscut local. Altă versiune: `IMAGE_TAG=<sha> scripts/local-up.sh`.
Imaginea e publică și are două variante, `linux/amd64` și `linux/arm64`;
fiecare nod o ia pe cea potrivită procesorului său.

### Adrese

| Adresă pe calculator | Unde duce |
| --- | --- |
| `127.0.0.1:6550` | API server-ul clusterului (folosit de `kubectl` și Helm) |
| `127.0.0.1:8080` | intrarea HTTP: Traefik, apoi serviciile aplicației |

Ambele sunt publicate doar pe adresa locală, nu și în rețea.

```
curl -i http://127.0.0.1:8080/api/test
```

Din exterior se ajunge doar la căile care încep cu `/api`. Până apar rutele
aplicației, răspunsul e un `404` în format JSON, dat de `api`. Rutele de
infrastructură (`/healthz`, `/readyz`, `/metrics`) nu au regulă de rutare și
primesc `404` direct de la Traefik.

### Oprire și ștergere

```
k3d cluster stop licenta      # oprește nodurile; datele rămân
k3d cluster start licenta     # le pornește la loc
k3d cluster delete licenta    # șterge clusterul cu totul
```

Clusterul se oprește înainte de închiderea Docker Desktop. Repornit doar de
Docker, nodul server poate rămâne fără API server; `stop` urmat de `start` îl
repară, fără pierdere de date.

Comenzi utile pentru chart:

```
helm lint deploy/helm/rag                  # verifică chart-ul
helm template rag deploy/helm/rag -n rag --set api.image.tag=test   # afișează manifestele generate, fără să le trimită
helm history rag -n rag                    # reviziile instalării
helm rollback rag <revizie> -n rag         # revine la o revizie anterioară
```

Pentru depanare, un tunel temporar de pe laptop direct până la Service, ocolind Traefik:

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
