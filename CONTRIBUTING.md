# Team workflow (Agile, multi-developer)

## Branching: trunk-based development

- `main` is always deployable and protected. Nobody pushes to it directly.
- Work on short-lived branches (1–3 days), named after the ticket:
  `feat/TF-42-task-due-dates`, `fix/TF-51-health-check`, `infra/TF-60-https`.
- Open a pull request early (as a Draft if it's not finished).

## Pull request rules (enforced by branch protection)

1. All CI checks green: backend, frontend, docker scans, terraform validation.
2. At least **1 approving review**.
3. Branch is up to date with `main`.
4. For `infra/` changes, read the `terraform plan` comment before approving.
   **Any `destroy` or `replace` of a stateful resource (RDS, S3) needs a second reviewer.**

## Commit messages: Conventional Commits

```
feat(api): add due_date to tasks
fix(frontend): handle empty task list
infra(ecs): raise backend max tasks to 6
chore(ci): cache pip dependencies
```

## Sprint rhythm (2 weeks)

| When | What |
|---|---|
| Day 1 | Sprint planning: pick tickets, each ticket = one small PR |
| Daily | 15-min stand-up: done / doing / blocked |
| Continuous | Merge → auto-deploys to **staging** for QA / product owner review |
| Release | Approve the **production** step in GitHub Actions (any merged commit can be released) |
| Last day | Demo on staging + retrospective |

## Database migrations: the expand / contract rule

Migrations run **before** new code starts, while old code is still serving traffic.
So every migration must work with both the old and the new code:

- ✅ Add a nullable column, add a table, add an index
- ❌ Rename or drop a column in the same release the code stops using it

Do destructive changes in two releases: (1) stop using the column, (2) drop it later.

Create a migration:

```bash
cd backend
alembic revision -m "add due_date to tasks"
# edit the generated file in alembic/versions/, then:
alembic upgrade head   # against your local docker-compose DB
```
