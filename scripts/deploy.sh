#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Zero-downtime deploy of one image tag to one environment.
# Used by GitHub Actions, and runnable by hand in an emergency:
#
#   PROJECT=taskflow ENVIRONMENT=staging IMAGE_TAG=<git-sha> \
#   ECR_REGISTRY=<acct>.dkr.ecr.us-west-2.amazonaws.com ./scripts/deploy.sh
#
# Steps:
#   1. Register new task definition revisions that point at the new image tag
#   2. Run database migrations as a one-off ECS task (abort deploy if they fail)
#   3. Roll both ECS services to the new revisions (rolling, zero downtime)
#   4. Wait until stable, and verify ECS did NOT auto-roll back
# -----------------------------------------------------------------------------
set -euo pipefail

: "${PROJECT:?}" "${ENVIRONMENT:?}" "${IMAGE_TAG:?}" "${ECR_REGISTRY:?}"
CLUSTER="${PROJECT}-${ENVIRONMENT}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# Copies the latest task definition of a family, swaps the image + APP_VERSION,
# removes read-only fields, registers it, and prints the new ARN.
register_revision() {
  local service="$1"
  local family="${CLUSTER}-${service}"
  local image="${ECR_REGISTRY}/${PROJECT}/${service}:${IMAGE_TAG}"

  aws ecs describe-task-definition --task-definition "$family" --query taskDefinition --output json \
    | jq --arg IMG "$image" --arg TAG "$IMAGE_TAG" '
        .containerDefinitions[0].image = $IMG
        | .containerDefinitions[0].environment |= ((. // []) | map(if .name == "APP_VERSION" then .value = $TAG else . end))
        | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
              .registeredAt, .registeredBy, .deregisteredAt)' \
    > "/tmp/${service}-taskdef.json"

  aws ecs register-task-definition --cli-input-json "file:///tmp/${service}-taskdef.json" \
    --query taskDefinition.taskDefinitionArn --output text
}

log "Registering new task definitions for ${IMAGE_TAG}"
BACKEND_TD=$(register_revision backend)
FRONTEND_TD=$(register_revision frontend)
echo "backend : $BACKEND_TD"
echo "frontend: $FRONTEND_TD"

# ---------------------------------------------------------------------------
log "Running database migrations (alembic upgrade head)"
NETWORK=$(aws ecs describe-services --cluster "$CLUSTER" --services backend \
  --query 'services[0].networkConfiguration' --output json)

TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$BACKEND_TD" \
  --launch-type FARGATE \
  --network-configuration "$NETWORK" \
  --overrides '{"containerOverrides":[{"name":"backend","command":["alembic","upgrade","head"]}]}' \
  --started-by "migrate-${IMAGE_TAG:0:12}" \
  --query 'tasks[0].taskArn' --output text)
echo "migration task: $TASK_ARN"

aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"
EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)

if [[ "$EXIT_CODE" != "0" ]]; then
  echo "❌ Migration failed (exit code: $EXIT_CODE). Services were NOT updated."
  TASK_ID="${TASK_ARN##*/}"
  aws logs get-log-events --log-group-name "/ecs/${CLUSTER}/backend" \
    --log-stream-name "backend/backend/${TASK_ID}" --limit 50 \
    --query 'events[].message' --output text || true
  exit 1
fi
echo "✅ migrations applied"

# ---------------------------------------------------------------------------
log "Rolling out services"
aws ecs update-service --cluster "$CLUSTER" --service backend  --task-definition "$BACKEND_TD"  >/dev/null
aws ecs update-service --cluster "$CLUSTER" --service frontend --task-definition "$FRONTEND_TD" >/dev/null

log "Waiting for services to become stable (usually 2-5 min)"
aws ecs wait services-stable --cluster "$CLUSTER" --services backend frontend

# The circuit breaker may have rolled back to the previous version; the waiter
# would still report "stable", so verify which revision is actually running.
for pair in "backend|$BACKEND_TD" "frontend|$FRONTEND_TD"; do
  svc="${pair%%|*}"; expected="${pair##*|}"
  read -r running state < <(aws ecs describe-services --cluster "$CLUSTER" --services "$svc" \
    --query 'services[0].deployments[?status==`PRIMARY`] | [0].[taskDefinition, rolloutState]' --output text)
  if [[ "$running" != "$expected" || "$state" != "COMPLETED" ]]; then
    echo "❌ $svc did not deploy cleanly (running=$running state=$state) — ECS rolled back."
    exit 1
  fi
  echo "✅ $svc running $running"
done

log "Deploy of ${IMAGE_TAG} to ${ENVIRONMENT} complete"
