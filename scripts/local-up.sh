#!/usr/bin/env bash
# Pornește mediul local de la zero: clusterul k3d și tot ce rulează în el.
#
# Poate fi rulat de mai multe ori: fiecare pas verifică ce există deja și
# face doar ce lipsește.
#
# Folosire: scripts/local-up.sh

# Oprește scriptul la prima comandă care eșuează (-e), la folosirea unei
# variabile nedefinite (-u) și la eșecul oricărei comenzi dintr-un lanț cu | .
set -euo pipefail

# Numele clusterului, același ca în deploy/local/k3d-config.yaml.
CLUSTER=licenta
# Numele sub care k3d înregistrează clusterul în kubeconfig. Toate comenzile
# kubectl și helm îl primesc explicit, ca scriptul să nu poată lucra din
# greșeală pe alt cluster configurat pe același calculator.
CONTEXT="k3d-${CLUSTER}"
# Folderul repo-ului, indiferent de folderul din care e pornit scriptul.
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# Versiunile componentelor de platformă. Se schimbă împreună: fiecare versiune
# de Traefik cere o anumită versiune a standardului Gateway API (o afișează
# chart-ul la instalare).
GATEWAY_API_VERSION=v1.7.0
TRAEFIK_CHART_VERSION=43.0.0

# Tag-ul imaginii api: SHA-ul unui commit pentru care pipeline-ul a publicat
# imaginea în ghcr.io. Implicit, ultimul commit de pe main cunoscut local
# (după git fetch sau git pull). Poate fi dat din afară:
#   IMAGE_TAG=<sha> scripts/local-up.sh
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$REPO" rev-parse origin/main)}"

# --- 1. Uneltele necesare ---
for tool in docker k3d kubectl helm git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Lipsește unealta: $tool. Vezi README, secțiunea Unelte necesare." >&2
    exit 1
  fi
done
if ! docker info >/dev/null 2>&1; then
  echo "Docker nu rulează. Pornește Docker Desktop și rulează din nou." >&2
  exit 1
fi

# --- 2. Clusterul ---
if k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
  echo "Clusterul $CLUSTER există; îl pornesc dacă e oprit."
  k3d cluster start "$CLUSTER"
else
  k3d cluster create --config "$REPO/deploy/local/k3d-config.yaml"
fi
# Așteaptă până când toate nodurile sunt gata să primească poduri.
kubectl --context "$CONTEXT" wait --for=condition=Ready nodes --all --timeout=120s

# --- 3. Tipurile de obiecte ale standardului Gateway API ---
# Definițiile (CRD-uri) publicate de autorii standardului, canalul standard.
# Fără ele, API server-ul nu cunoaște obiectele Gateway și HTTPRoute.
kubectl --context "$CONTEXT" apply --server-side \
  -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
# Așteaptă ca API server-ul să înceapă să servească noile tipuri.
kubectl --context "$CONTEXT" wait --for=condition=Established --timeout=60s \
  crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io

# --- 4. Traefik: proxy-ul invers de la intrarea în cluster ---
# --repo ia chart-ul direct de la adresa depozitului, fără ca depozitul să
# fie înregistrat dinainte pe calculator. --wait așteaptă până când podul
# trece proba de pregătire.
helm --kube-context "$CONTEXT" upgrade --install traefik traefik \
  --repo https://traefik.github.io/charts --version "$TRAEFIK_CHART_VERSION" \
  --namespace traefik --create-namespace \
  -f "$REPO/deploy/platform/traefik-values.yaml" \
  --wait --timeout 3m

# --- 5. Aplicația ---
helm --kube-context "$CONTEXT" upgrade --install rag "$REPO/deploy/helm/rag" \
  --namespace rag --create-namespace \
  --set "api.image.tag=${IMAGE_TAG}" \
  --wait --timeout 3m

echo
echo "Gata. Imaginea api: ${IMAGE_TAG}"
echo "Verificare: curl -i http://127.0.0.1:8080/api/test  (răspunde api, cu 404 în format JSON)"
