#!/usr/bin/env bash
set -euo pipefail

#------------------------------------
# Environment Variables
#------------------------------------
# Обязательные
APP="{APP:-}"
IMAGE="{IMAGE:-}"

# Опциональные с дефолтами
TIMEOUT="{TIMEOUT:-60}"
APP_TYPE="{APP_TYPE:-spring}"
PATH_TO_APP="{PATH_TO_APP:-}"
APP_IMAGE_URL="{APP_IMAGE_URL:-}"

#------------------------------------
# Validate requires
#------------------------------------
if [[ -z "$APP" || -z "$IMAGE" ]]; then
  echo "Required environments: APP, IMAGE"
  exit 1
fi

#------------------------------------
# Helps
#------------------------------------
log() {
  echo "[$(date + '%Y-%m-%d %H:%M:%S')] $*"
}

rollback() {
  if [[ -n "$OLD_IMAGE" ]]; then
      log "Rolling back to previous image: $OLD_IMAGE"
      docker compose up -d --no-deps "$APP"
  fi
  exit 1
}

#------------------------------------
# Change directory if specified
#------------------------------------
if [[ -n "$PATH_TO_APP" ]]; then
    cd ~/"$PATH_TO_APP" || { log "Cannot cd to $PATH_TO_APP"; exit 1; }
fi

if [[ ! -f docker-compose.yml ]]; then
    log "docker-compose.yml not found in $(pwd)"
    exit 1
fi

#------------------------------------
# Detect current container/image
#------------------------------------
log "Detect current container..."
OLD_CONTAINER=$(docker compose ps -q "$APP" || true)

OLD_IMAGE=""
if [[ -n "$OLD_CONTAINER" ]]; then
    OLD_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$OLD_CONTAINER")
fi

log "Current image: ${OLD_IMAGE:-none}"

#------------------------------------
# Setup APP_IMAGE_URL variable
#------------------------------------
if [[ -n "$APP_IMAGE_URL" ]]; then
  IMAGE_VAR="$APP_IMAGE_URL"
else
  IMAGE_VAR=$(echo "$APP" | tr '[:lower:]-' '[:upper:]_')_IMAGE
fi

log "Using APP_IMAGE: $IMAGE_VAR"
export "$IMAGE_VAR"="$IMAGE"

#------------------------------------
# Pull new image
#------------------------------------
log "Pull new image: $OLD_IMAGE"
docker compose pull "$APP"

#------------------------------------
# Start new container
#------------------------------------
log "Starting update container..."
docker compose up -d --no-deps "$APP"

#------------------------------------
# Healthcheck
#------------------------------------
log "Waiting for container health (timeout ${TIMEOUT}s)..."
START_TIME=$(date +%s)

while true; do
  CONTAINER_ID=$(docker compose ps -q "$APP")

  if [[ "$APP_TYPE" == "spring" ]]; then
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_ID" 2>/dev/null || echo "no-healthcheck")
    [[ "$STATUS" == "healthy" || "$STATUS" == "no-healthcheck" ]] && break
  elif [[ "$APP_TYPE" == "vue" ]]; then
    HTTP_CODE=$(docker exec "$CONTAINER_ID" curl -s -o /dev/null -w "%{http_code}" http://localhost:80/ || echo 0)
    [[ "$HTTP_CODE" == "200" ]] && break
  else
    echo "Unknown APP_TYPE: $APP_TYPE"
    rollback
  fi

  NOW=$(date +%s)
  ELAPSED=$((NOW - START_TIME))
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log "Healthcheck timeout reached"
    rollback
  fi

  sleep 3
done

#------------------------------------
# Cleanup
#------------------------------------
log "Cleaning ol images for $APP (keep current: $IMAGE)..."

IMAGES_TO_REMOVE=$(docker image --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep "^${APP}:" | awk -v keep="$IMAGE" '$1 != keep {print $2}')

if [[ -n "$IMAGES_TO_REMOVE" ]]; then
  log "Removing images: $IMAGES_TO_REMOVE"
  docker rmi -f $IMAGES_TO_REMOVE
else
  log "No old images to remove"
fi

log "Deploy finished successfully!"