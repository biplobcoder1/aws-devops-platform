#!/usr/bin/env bash
# One-time helper (README Phase 4): build both images and push them to ECR with
# the tag "initial", so the very first `terraform apply` has something to run.
# After that, GitHub Actions builds and pushes every image (tagged by git SHA).
#
#   AWS_REGION=us-west-2 ./scripts/push-initial-images.sh
set -euo pipefail

PROJECT="${PROJECT:-taskflow}"
AWS_REGION="${AWS_REGION:-us-west-2}"
TAG="${TAG:-initial}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Logging in to ${REGISTRY}"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

cd "$(dirname "$0")/.."
for svc in backend frontend; do
  image="${REGISTRY}/${PROJECT}/${svc}:${TAG}"
  echo "Building ${image}"
  # --platform: Fargate runs x86_64; needed if you build on an Apple Silicon Mac
  docker build --platform linux/amd64 -t "$image" "./${svc}"
  docker push "$image"
done

echo "✅ Pushed ${TAG} images. ECR registry: ${REGISTRY}"
