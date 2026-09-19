# Configuration

Forge is configured entirely through environment variables. The installer
writes them to `~/.forge-ci/forge.env`; with Compose they live in `.env`; on
Kubernetes, put the secret ones in the `forge-secrets` Secret.

After editing `~/.forge-ci/forge.env`, run the installer again (or
`docker restart forge-ci`) to apply the changes.

## GitHub

| Variable | Default | What it does |
|---|---|---|
| `GITHUB_TOKEN` | — | **Required** for private repos, runners and logs. See [token scopes](#token-scopes). |
| `FORGE_REPOS` | — | Repos to watch, comma-separated: `owner/repo,owner/other`. |
| `FORGE_ORGS` | — | Orgs whose **private** repos pushed in the last `FORGE_DISCOVER_DAYS` are watched automatically, and whose org-level self-hosted runners are listed. |
| `FORGE_RUNNER_REPOS` | — | Repos whose **repo-level** self-hosted runners should appear in the fleet strip. |
| `FORGE_DISCOVER_DAYS` | `30` | How recently an org repo must have been pushed to be auto-watched. |
| `FORGE_POLL_SECONDS` | `15` | How often runs are polled. Unchanged responses cost no rate limit. |
| `FORGE_RUNS_PER_REPO` | `30` | Runs fetched per repo on each poll (the first poll after a start fetches 100 to backfill history). |

### Token scopes

| To… | Classic PAT scope |
|---|---|
| watch public repos | none (but a token is still needed to read job logs) |
| watch private repos | `repo` |
| list an org's self-hosted runners / auto-watch its private repos | `admin:org` (Forge only reads) |
| list a repo's self-hosted runners | `repo`, and you must be an admin of that repo |

Fine-grained tokens are limited to one owner (your user *or* one org). They
work if everything you watch has the same owner: grant **Actions: read**,
**Metadata: read** and, for runners, **Administration: read** (repos) or
**Self-hosted runners: read** (org).

If Forge can't list runners for a repo you don't administer, it skips them
quietly. That's normal.

## Display

| Variable | Default | What it does |
|---|---|---|
| `FORGE_TITLE` | `CI` | Shown under the Forge logo and in email footers. |
| `FORGE_URL` | `http://localhost:8080` | Forge's public URL, used for links in emails. |
| `FORGE_HOST_LABEL` | `self-hosted` | The name used for your self-hosted runners and runner host in the UI (for example `build-box`). |
| `FORGE_MINUTE_PRICE` | `0.006` | $/minute used for "saved" figures (GitHub Linux 2-core). |
| `PORT` | `8080` | Port Forge listens on inside the container. |

## Tests

| Variable | Default | What it does |
|---|---|---|
| `FORGE_TEST_PATTERN` | `test\|lint\|typecheck\|check\|migrat\|smoke\|spec\|e2e\|coverage\|vet\|verify\|quality\|diagram\|architecture\|parity` | A job counts as a test when its name or its workflow's name matches this regular expression (case-insensitive). Jobs that run `npm test`, `vitest`, `jest`, `pytest`, `go test`, `tsc` or `eslint` in a step also count. |
| `FORGE_TEST_LOG_DAYS` | `4` | How far back Forge reads logs of finished test jobs to parse their counts. It reads 12 logs every 30 seconds. |

## AI explainer

| Variable | Default | What it does |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | Turns on the ✦ buttons and chat. Without a key they show "AI is not configured". The account needs API credit. |
| `FORGE_AI_MODEL` | `claude-opus-5` | Model used for explanations and chat. |
| `FORGE_AI_EFFORT` | `medium` | Effort level (`low` … `max`). Lower is faster and cheaper. |
| `FORGE_AI_RATE_PER_10MIN` | `40` | Questions allowed per client IP per 10 minutes. Cached explanations don't count. |

Each question sends the model about 5–20 KB of context: job steps, parsed
results, a log excerpt and the workflow file. The first explanation of an item
in a given state is cached and served to everyone after that.

## Alerts

| Variable | Default | What it does |
|---|---|---|
| `NOTIFY_TO` | — | Recipients, comma-separated. Alerts are off without it. |
| `NOTIFY_FROM` | `Forge CI <onboarding@resend.dev>` | Sender. With Resend, use an address on a domain you've verified there (`onboarding@resend.dev` only delivers to the Resend account's own address). |
| `NOTIFY_MODE` | `transitions` | `transitions` emails on pass→fail and on recovery; `every` emails on every failure. |
| `NOTIFY_BRANCHES` | — | Only alert for these branches (for example `main,dev`). Empty means all branches. |
| `FORGE_OFFLINE_GRACE` | `300` | Seconds a self-hosted runner must be offline before an alert. |
| `RESEND_API_KEY` | — | Send through [Resend](https://resend.com). |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASS` | — / `465` | Or send through any SMTP server (465 uses TLS; anything else uses STARTTLS). |

## Runner host health (Prometheus)

| Variable | Default | What it does |
|---|---|---|
| `PROM_URL` | — | Prometheus base URL, for example `http://prometheus:9090`. |
| `PROM_INSTANCE` | — | The `instance` label of the runner machine's node-exporter, for example `10.0.0.5:9100`. |

When both are set, the fleet strip shows a card with the host's CPU, memory,
disk and load, and a one-hour CPU sparkline. When they're not set, the card is hidden.

## Storage

| Variable | Default | What it does |
|---|---|---|
| `FORGE_DB` | `/data/forge.db` | SQLite database path. Mount a volume at `/data`. |
| `FORGE_RETENTION_DAYS` | `45` | Runs, jobs, events and cached AI answers older than this are deleted hourly. |

The database is a cache of GitHub plus Forge's own alert history. Deleting it
is safe: Forge backfills on the next start. The only things you lose are old
alerts and runs beyond what GitHub's API still returns.

## Kubernetes

```bash
kubectl create namespace forge
kubectl -n forge create secret generic forge-secrets \
  --from-literal=GITHUB_TOKEN=ghp_... \
  --from-literal=FORGE_REPOS=owner/repo
kubectl apply -k deploy/kubernetes
kubectl -n forge port-forward svc/forge 8080:80     # or edit the Ingress host
```

Edit `deploy/kubernetes/forge.yaml` to set `FORGE_URL` and the Ingress host.
Keep `replicas: 1`, because SQLite is single-writer.
