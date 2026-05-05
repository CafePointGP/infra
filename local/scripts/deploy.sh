#!/usr/bin/env bash
# deploy.sh — Script de deploy para VPS Hetzner (staging/production).
# Executado via SSH pelo GitHub Actions CD workflow.
#
# Uso: ./deploy.sh <image-tag>
# Exemplo: ./deploy.sh main-a1b2c3d

set -euo pipefail

IMAGE_TAG=${1:?"Uso: deploy.sh <image-tag>"}
COMPOSE_DIR="/opt/cafepointgp"
COMPOSE_FILE="docker-compose.staging.yml"
REGISTRY="ghcr.io/cafepointgp"
HEALTH_TIMEOUT=120

cd "$COMPOSE_DIR"

echo "==> Deploy iniciando: tag=${IMAGE_TAG}"

# 1. Login no ghcr.io
if [ -f "$COMPOSE_DIR/.ghcr_token" ]; then
    cat "$COMPOSE_DIR/.ghcr_token" | docker login ghcr.io -u cafepointgp --password-stdin
else
    echo "ERRO: .ghcr_token não encontrado em $COMPOSE_DIR"
    exit 1
fi

# 2. Pull das novas imagens
echo "==> Pulling imagens..."
docker pull "${REGISTRY}/api:${IMAGE_TAG}"
docker pull "${REGISTRY}/web:${IMAGE_TAG}"
docker pull "${REGISTRY}/postgres:${IMAGE_TAG}"

# 3. Tag como :deploy (referenciado no compose)
docker tag "${REGISTRY}/api:${IMAGE_TAG}" "${REGISTRY}/api:deploy"
docker tag "${REGISTRY}/web:${IMAGE_TAG}" "${REGISTRY}/web:deploy"
docker tag "${REGISTRY}/postgres:${IMAGE_TAG}" "${REGISTRY}/postgres:deploy"

# 4. Salvar versão anterior para rollback
PREVIOUS_VERSION=""
if [ -f "$COMPOSE_DIR/CURRENT_VERSION" ]; then
    PREVIOUS_VERSION=$(cat "$COMPOSE_DIR/CURRENT_VERSION")
    echo "==> Versão anterior: ${PREVIOUS_VERSION}"
fi

# 5. Deploy
echo "==> Executando docker compose up..."
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

# 5.1 Reiniciar nginx para resolver DNS/IPs dos containers
echo "==> Reiniciando nginx..."
docker restart cafegp-nginx 2>/dev/null || true

# 6. Aguardar health checks
echo "==> Aguardando health checks (timeout: ${HEALTH_TIMEOUT}s)..."
ELAPSED=0
while [ $ELAPSED -lt $HEALTH_TIMEOUT ]; do
    API_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' cafegp-api 2>/dev/null || echo "starting")
    NGINX_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' cafegp-nginx 2>/dev/null || echo "starting")

    if [ "$API_HEALTH" = "healthy" ] && [ "$NGINX_HEALTH" = "healthy" ]; then
        echo "==> Todos os serviços healthy!"
        echo "$IMAGE_TAG" > "$COMPOSE_DIR/CURRENT_VERSION"
        docker image prune -f > /dev/null 2>&1
        echo "==> Deploy concluído: ${IMAGE_TAG}"
        exit 0
    fi

    echo "    api=${API_HEALTH} nginx=${NGINX_HEALTH} (${ELAPSED}s/${HEALTH_TIMEOUT}s)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

# 7. Rollback em caso de falha
echo "ERRO: Health checks falharam após ${HEALTH_TIMEOUT}s."
echo "==> Tentando rollback..."

if [ -n "$PREVIOUS_VERSION" ]; then
    docker tag "${REGISTRY}/api:${PREVIOUS_VERSION}" "${REGISTRY}/api:deploy" 2>/dev/null || true
    docker tag "${REGISTRY}/web:${PREVIOUS_VERSION}" "${REGISTRY}/web:deploy" 2>/dev/null || true
    docker tag "${REGISTRY}/postgres:${PREVIOUS_VERSION}" "${REGISTRY}/postgres:deploy" 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" up -d --remove-orphans
    echo "==> Rollback para ${PREVIOUS_VERSION} executado. Verifique manualmente."
else
    echo "==> Sem versão anterior para rollback. Intervenção manual necessária."
fi

exit 1
