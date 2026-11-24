# Shortcuts. Usage: make <target>   e.g.  make up   |   make plan ENV=staging
ENV ?= staging
TF_DIR = infra/terraform

.PHONY: up down logs test lint fmt init plan apply destroy

## ---------- Local ----------
up:            ## start the full stack locally on http://localhost:8080
	docker compose up --build -d

down:          ## stop local stack
	docker compose down

logs:
	docker compose logs -f backend frontend

test:          ## run backend unit tests
	cd backend && python -m pytest -q

lint:          ## lint backend + typecheck frontend
	cd backend && ruff check .
	cd frontend && npx tsc --noEmit

## ---------- Terraform ----------
fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive

init:          ## terraform init for ENV (staging|prod)
	terraform -chdir=$(TF_DIR) init -reconfigure -backend-config=envs/$(ENV).backend.hcl

plan:
	terraform -chdir=$(TF_DIR) plan -var-file=envs/$(ENV).tfvars -out=$(ENV).tfplan

apply:
	terraform -chdir=$(TF_DIR) apply $(ENV).tfplan

destroy:       ## tear everything down for ENV (stops AWS billing)
	terraform -chdir=$(TF_DIR) destroy -var-file=envs/$(ENV).tfvars
