# Deploy TaskFlow to AWS with GitHub Actions

This guide takes the project from your Windows machine to a running AWS deployment. After the one-time setup, merging a pull request into `main` deploys automatically.

**Run every command in Git Bash, from the repository root, unless a step says otherwise.**

## How the automation works

```text
Pull request ──► CI: lint, tests, migrations, image scan, Terraform checks
     │           Terraform plan posted on the PR (when infra/terraform changes)
     ▼
Merge to main
     ├─ app changed ───► Build images ─► Deploy staging ─► Smoke test
     │                                        └─► Your approval ─► Deploy production
     └─ infra changed ─► Terraform apply staging
                                              └─► Your approval ─► Terraform apply production
```

GitHub signs in to AWS with OIDC, so **you never store AWS access keys in GitHub**.

| What | Who does it | How often |
|---|---|---|
| Create state bucket, ECR, and IAM roles | You, from your laptop | Once |
| Push the first container images | You, from your laptop | Once |
| Configure GitHub | You | Once |
| Create VPC, database, load balancer, and ECS | GitHub Actions | Automatic after setup |
| Build, migrate, deploy, and smoke test | GitHub Actions | Every merge |

## Before you start: cost

This creates real resources that bill **every hour, even with no traffic**. The rough estimate is **$75–90/month for staging** and **$200+/month for production**. Start with staging only (Step 9 shows how), and follow [Tear down](#tear-down) when you are finished.

---

## Step 1. Install and sign in to the tools

You already have Git, the AWS CLI, Docker, and the GitHub CLI. Terraform is missing, so install it in PowerShell, then **open a new Git Bash window**:

```powershell
winget install --id Hashicorp.Terraform -e
```

Check the tools. Terraform must be 1.10 or newer, and Docker Desktop must be running.

```bash
terraform -version
docker info --format '{{.ServerVersion}}'
```

Sign in to GitHub, including permission to push workflow files:

```bash
gh auth login
gh auth refresh -s workflow
```

Sign in to AWS with an identity that has **administrator access**, then confirm the account:

```bash
aws configure          # region: us-west-2, output: json
aws sts get-caller-identity
```

In the AWS console, create a monthly budget alert under **Billing and Cost Management → Budgets** before continuing.

## Step 2. Set your session variables

Change `GH_REPO_NAME` only if you want a different repository name. **If you open a new terminal later, run this block again.**

```bash
export GH_OWNER=$(gh api user --jq .login)
export GH_REPO_NAME=aws-devops-platform
export REPO="$GH_OWNER/$GH_REPO_NAME"
export AWS_REGION=us-west-2
export PROJECT=taskflow
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "$REPO | $ACCOUNT_ID | $ECR_REGISTRY"
```

## Step 3. Fix the CI security scanner

`.github/workflows/ci.yml` uses `aquasecurity/trivy-action@0.28.0`. That tag was removed after the [March 2026 Trivy supply-chain attack](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23), so CI cannot run until it is changed. This pins the action to the exact commit of the safe `v0.35.0` release:

```bash
sed -i 's|aquasecurity/trivy-action@0.28.0|aquasecurity/trivy-action@57a97c7e7821a5776cebc9bb87c984fa69cba8f1 # v0.35.0|' .github/workflows/ci.yml
grep -n "trivy-action" .github/workflows/ci.yml
```

## Step 4. Create the AWS foundation

This creates the Terraform state bucket, ECR repositories, GitHub OIDC provider, and three IAM roles.

```bash
cat > infra/bootstrap/terraform.tfvars <<EOF
project      = "$PROJECT"
aws_region   = "$AWS_REGION"
github_owner = "$GH_OWNER"
github_repo  = "$GH_REPO_NAME"
EOF

terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap apply
```

Review the plan and type `yes`.

> The owner and repository name must match GitHub exactly, including capitalization. If they differ, GitHub Actions cannot sign in to AWS.

> If apply fails with `EntityAlreadyExists` for the OIDC provider, your account already has one. Import it, then apply again:
> `terraform -chdir=infra/bootstrap import aws_iam_openid_connect_provider.github arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com`

Back up the bootstrap state, because it exists only on your laptop and Git ignores it:

```bash
aws s3 cp infra/bootstrap/terraform.tfstate "s3://$PROJECT-tfstate-$ACCOUNT_ID/bootstrap/terraform.tfstate"
```

Point the environments at the new state bucket:

```bash
sed -i "s/<ACCOUNT_ID>/$ACCOUNT_ID/" infra/terraform/envs/staging.backend.hcl infra/terraform/envs/prod.backend.hcl
```

## Step 5. Push the first images

The first Terraform run starts ECS services from images tagged `initial`, so they must exist first. This takes a few minutes.

```bash
./scripts/push-initial-images.sh
```

ECR tags cannot be overwritten. If the script fails after pushing the backend image, push the frontend by hand instead of re-running it:

```bash
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
docker build --platform linux/amd64 -t "$ECR_REGISTRY/$PROJECT/frontend:initial" ./frontend
docker push "$ECR_REGISTRY/$PROJECT/frontend:initial"
```

## Step 6. (Optional) Add alert emails

Terraform creates CloudWatch alarms for each environment whether or not you do this step. Adding an email address makes AWS send you a message when one of them fires:

| Alarm | Fires when |
|---|---|
| `<env>-alb-target-5xx` | More than 10 server errors (5xx) per minute, 3 minutes in a row |
| `<env>-alb-p95-latency` | The slowest 5% of requests take over 1 second, for 10 minutes |
| `<env>-backend-unhealthy-targets`, `<env>-frontend-unhealthy-targets` | The load balancer sees an unhealthy container for 3 minutes |
| `<env>-backend-cpu-high`, `<env>-frontend-cpu-high` | A service's average CPU use is above 85% for 10 minutes |
| `<env>-backend-memory-high`, `<env>-frontend-memory-high` | A service's average memory use is above 85% for 10 minutes |
| `<env>-rds-cpu-high` | Database average CPU use is above 80% for 15 minutes |
| `<env>-rds-free-storage-low` | The database has less than 2 GiB of free disk space |

`<env>` is `taskflow-staging` or `taskflow-prod`. All alarms send to one SNS topic per environment, named `<env>-alerts`.

> **Privacy:** the tfvars files are committed, and Step 7 makes the repository public, so anyone can read this address. Use an address you don't mind sharing, such as a Gmail `+` alias (`you+taskflow@gmail.com`).

### 6.1 Set the address

Do this **before Step 7**, so the address is part of the first push and Step 9 creates the subscription.

```bash
ALERT_EMAIL="you+taskflow@example.com"   # replace with your address

sed -i "s/^alert_email = \"\".*/alert_email = \"$ALERT_EMAIL\"/" \
  infra/terraform/envs/staging.tfvars infra/terraform/envs/prod.tfvars

grep -n alert_email infra/terraform/envs/*.tfvars
```

Both lines should now show your address. You can use a different address for each environment. For example, you might send staging alerts to yourself and production alerts to a team inbox. To do that, edit each file by hand.

### 6.2 Confirm the subscription (after Step 9)

Nothing is emailed yet. When Step 9 applies each environment, AWS sends one email per environment from **AWS Notifications** (`no-reply@sns.amazonaws.com`), with the subject **AWS Notification - Subscription Confirmation**.

1. Open each email and click **Confirm subscription**. Check your spam folder if you don't see it.
2. Click the link within **3 days**. After that it expires, and you have to run the apply again to get a new one.

Check that both environments are confirmed:

```bash
for ENV in staging prod; do
  TOPIC_ARN="arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:$PROJECT-$ENV-alerts"
  aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
    --query 'Subscriptions[].[Endpoint,SubscriptionArn]' --output table
done
```

A confirmed subscription shows an ARN that ends in an ID. If it shows `PendingConfirmation`, you haven't clicked the link yet.

### 6.3 Send a test alert (optional)

Force an alarm into the `ALARM` state to make sure an email arrives. CloudWatch sets it back to normal at its next check, about a minute later.

```bash
aws cloudwatch set-alarm-state \
  --alarm-name "$PROJECT-staging-rds-cpu-high" \
  --state-value ALARM \
  --state-reason "Testing alert email"
```

An email titled `ALARM: "taskflow-staging-rds-cpu-high" in US West (Oregon)` should arrive within a minute.

### Changing or removing the address later

Edit `alert_email` in the tfvars file and push to `main`, and the pipeline applies the change. If you change the address, confirm the new one as in 6.2. If you set it back to `""`, the subscription is deleted.

## Step 7. Push the code to GitHub

**Use a public repository.** The production approval gate relies on GitHub's required reviewers, which [only work on public repositories](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments) unless you have GitHub Enterprise. On a private repository, production could deploy with no approval.

Check what will be published before pushing. The list must not contain `.env`, `*.tfstate`, or `.terraform/` files.

```bash
git init -b main
git add .
git add --chmod=+x scripts/deploy.sh scripts/push-initial-images.sh
git status --short
```

`--chmod=+x` is required on Windows. Without it, the pipeline fails with `Permission denied` on `deploy.sh`.

`[skip ci]` in this commit stops the pipelines from starting before GitHub and AWS are fully connected:

```bash
git commit -m "Initial commit [skip ci]"
gh repo create "$REPO" --public --source=. --remote=origin --push
```

## Step 8. Connect GitHub to AWS

Add the repository variables. None of these values are secret credentials.

```bash
gh variable set AWS_REGION            -R "$REPO" -b "$AWS_REGION"
gh variable set PROJECT               -R "$REPO" -b "$PROJECT"
gh variable set ECR_REGISTRY          -R "$REPO" -b "$ECR_REGISTRY"
gh variable set AWS_TF_PLAN_ROLE_ARN  -R "$REPO" -b "arn:aws:iam::$ACCOUNT_ID:role/$PROJECT-gha-terraform-plan"
gh variable set AWS_TF_APPLY_ROLE_ARN -R "$REPO" -b "arn:aws:iam::$ACCOUNT_ID:role/$PROJECT-gha-terraform-apply"
gh variable set AWS_DEPLOY_ROLE_ARN   -R "$REPO" -b "arn:aws:iam::$ACCOUNT_ID:role/$PROJECT-gha-deploy"
gh variable list -R "$REPO"
```

Create the `staging` and `production` environments. Production requires your approval, and both accept deployments only from `main`. That branch limit matters because the Terraform role has administrator access.

```bash
MY_ID=$(gh api user --jq .id)

gh api -X PUT "repos/$REPO/environments/staging" --input - <<EOF
{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF

gh api -X PUT "repos/$REPO/environments/production" --input - <<EOF
{"reviewers":[{"type":"User","id":$MY_ID}],
 "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF

for e in staging production; do
  gh api -X POST "repos/$REPO/environments/$e/deployment-branch-policies" -f name=main -f type=branch
done
```

## Step 9. Create the infrastructure from GitHub Actions

```bash
gh workflow run terraform.yml -R "$REPO" --ref main
sleep 5
gh run watch -R "$REPO" "$(gh run list -R "$REPO" --workflow=terraform.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Staging usually takes 10–20 minutes, mostly for the database. The run then pauses at **Apply prod**.

Open the run under the repository's **Actions** tab, select **Review deployments**, and choose one:

- **Reject** to stay on staging only and avoid production costs. The run shows as failed, which is expected.
- **Approve** to create production as well.

## Step 10. Run the first automatic deployment

```bash
gh workflow run deploy.yml -R "$REPO" --ref main
sleep 5
gh run watch -R "$REPO" "$(gh run list -R "$REPO" --workflow=deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

The workflow builds both images, runs database migrations, updates ECS, and smoke-tests staging. At the production gate, **Reject** if you skipped production in Step 9. The job would fail without that infrastructure.

Open your staging app:

```bash
DNS=$(aws elbv2 describe-load-balancers --names "$PROJECT-staging" --query 'LoadBalancers[0].DNSName' --output text)
curl -s "http://$DNS/api/health"; echo
curl -s "http://$DNS/api/health/ready"; echo
echo "App: http://$DNS"
```

The health response's `version` should equal the deployed commit SHA, and the ready endpoint should return `{"status":"ready"}`.

## Step 11. Protect `main`

The Deploy workflow runs on **any** push to `main` and does not wait for CI. Branch protection is what makes passing CI mandatory.

First, open a small pull request so GitHub learns the CI check names:

```bash
git switch -c test/first-pr
git commit --allow-empty -m "Trigger first CI run"
git push -u origin test/first-pr
gh pr create --fill
gh pr checks --watch
```

Then go to **Settings → Branches → Add classic branch protection rule**, use the pattern `main`, and enable:

- **Require a pull request before merging.** Set required approvals to 0 if you work alone.
- **Require status checks to pass before merging**, with these five checks:
  - `Backend — lint, test, migrations`
  - `Frontend — typecheck & build`
  - `Docker build + vulnerability scan (backend)`
  - `Docker build + vulnerability scan (frontend)`
  - `Terraform — fmt, validate, security scan`
- **Do not allow bypassing the above settings.**

Merge the test PR, then update your local branch:

```bash
gh pr merge --squash --delete-branch
git switch main && git pull
```

**Setup is complete.**

---

## Your everyday workflow

```bash
git switch -c feature/my-change
# edit code
git add .
git commit -m "Describe the change"
git push -u origin feature/my-change
gh pr create --fill
gh pr checks --watch
gh pr merge --squash --delete-branch
```

The merge deploys to staging. When you are happy with it, approve the production step in **Actions**.

Keep application and `infra/terraform` changes in **separate PRs**. Both pipelines start at the same time on merge, so a release that depends on new infrastructure could deploy before that infrastructure exists.

## Roll back

Redeploy an earlier image using its full commit SHA:

```bash
git log --format='%H %s' -10
gh workflow run deploy.yml -R "$REPO" --ref main -f image_tag=<FULL_COMMIT_SHA>
```

ECR keeps the last 30 images.

> **Database limit:** every deploy runs `alembic upgrade head`. If a newer release added a migration, an older image does not know that revision and the rollback stops at the migration step. In that case, ship a forward fix, or deliberately downgrade the database first after taking a snapshot.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Owner or repo name differs from bootstrap, or the run is not from `main` | Correct `infra/bootstrap/terraform.tfvars`, apply bootstrap again |
| `./scripts/deploy.sh: Permission denied` | Executable bit missing | `git update-index --chmod=+x scripts/deploy.sh`, then commit through a PR |
| `Unable to resolve action trivy-action` | Step 3 was skipped | Apply Step 3 |
| `tag ... already exists` / `ImageTagAlreadyExistsException` | The same commit was built twice, and ECR tags are immutable | Use **Re-run failed jobs**, not **Re-run all jobs**, or run Deploy with `-f image_tag=<sha>` |
| `Unable to describe task definition` | Infrastructure is not ready | Finish Step 9, then re-run failed jobs |
| ECS tasks stop with `CannotPullContainerError` | The `initial` images are missing | Run Step 5 |
| Migration task fails | Bad migration or database problem | Read the job log, then `aws logs tail /ecs/$PROJECT-staging/backend --since 30m` |
| `ECS rolled back` | New tasks failed health checks | `aws logs tail /ecs/$PROJECT-staging/backend --since 30m` (or `frontend`) |
| Docker scan fails on a PR | A new fixable CVE in an image or dependency | Update the base image or dependency |

## Tear down

Stop the hourly charges by destroying each environment from your laptop.

**Staging:**

```bash
terraform -chdir=infra/terraform init -reconfigure -backend-config=envs/staging.backend.hcl
terraform -chdir=infra/terraform destroy -var-file=envs/staging.tfvars
```

**Production** has deletion protection. Set `deletion_protection = false` in `prod.tfvars`, then:

```bash
terraform -chdir=infra/terraform init -reconfigure -backend-config=envs/prod.backend.hcl
terraform -chdir=infra/terraform apply -var-file=envs/prod.tfvars
terraform -chdir=infra/terraform destroy -var-file=envs/prod.tfvars
```

**This permanently deletes the environment's database**, because turning off deletion protection also turns off the final snapshot. Take a manual RDS snapshot first if you need the data.

The state bucket and ECR repositories remain and cost very little, so you can recreate an environment by re-running the Terraform workflow.
