# Imaginea serviciului api.
#
# Build în două etape (multi-stage): prima instalează bibliotecile cu uv,
# a doua copiază doar rezultatul. Imaginea finală nu conține uv și nici alte
# unelte de build, deci e mai mică și are mai puține programe de atacat.
#
# Construire: docker build -t rag-api:dev .   (din services/api)

# --- Etapa 1: builder. Instalează bibliotecile. Nu ajunge în imaginea finală. ---
# Imagine de bază: Debian minimal cu Python 3.12.
FROM python:3.12-slim AS builder
# Ia programul uv din imaginea lui oficială, în loc să-l instaleze cu pip.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
# Folderul de lucru din imagine; comenzile următoare rulează aici.
WORKDIR /app
# Se copiază doar lista de biblioteci, nu și codul: cât timp aceste două
# fișiere nu se schimbă, Docker refolosește pasul de instalare din cache.
COPY pyproject.toml uv.lock ./
# Instalează în /app/.venv exact versiunile din uv.lock (--frozen),
# fără bibliotecile de dezvoltare: pytest, ruff, httpx2 (--no-dev).
RUN uv sync --frozen --no-dev

# --- Etapa 2: imaginea finală. Doar Python, biblioteci și cod. ---
FROM python:3.12-slim
# Utilizator fără drepturi de administrator. UID numeric fix (10001), fără
# folder personal și fără shell: dacă procesul e compromis, poate face puțin.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
# Bibliotecile instalate în etapa 1.
COPY --from=builder /app/.venv /app/.venv
# Codul aplicației.
COPY app ./app
# PYTHONDONTWRITEBYTECODE: Python nu scrie fișiere .pyc (containerul rulează cu sistem de fișiere read-only).
# PYTHONUNBUFFERED: logurile ajung imediat pe stdout, de unde le ia Docker/Kubernetes.
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
# De aici încolo, totul rulează ca utilizatorul 10001, nu ca root.
USER 10001
# Procesul pornit în container. --host 0.0.0.0: ascultă pe toate interfețele
# containerului (altfel nu ar fi accesibil din afara lui). --port 8000: portul
# aplicației; manifestele Kubernetes (containerPort, probe) trebuie să-l folosească pe același.
CMD ["/app/.venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
