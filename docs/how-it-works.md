# How Forge works

Forge is one Python process: a few background loops that sync from GitHub
into SQLite, and a small HTTP server that pushes a JSON snapshot to the
browser over server-sent events.

## Sync loops

| Loop | Every | Does |
|---|---|---|
| runs | 15 s | For each watched repo: list recent workflow runs, then list the jobs of any run that is in progress or has changed since its jobs were last read. Then evaluate alert rules. |
| runners | 30 s | List self-hosted runners (org and repo scope) and track how long each has been offline. |
| host | 15 s | Query Prometheus for the runner host's CPU, memory, disk and load (optional). |
| tests | 30 s | Download logs of up to 12 finished test jobs and parse their result summaries. |
| housekeeping | 1 h | Discover org repos, and delete data older than the retention window. |

### Staying under GitHub's rate limit

Every GET is sent with the `ETag` from the previous response. When nothing has
changed, GitHub answers `304 Not Modified`, which **doesn't count against the
rate limit**. So Forge can poll every 15 seconds and still spend most of its
budget only on real changes. The first start is the expensive part: it
backfills 100 runs per repo and their jobs. The header shows the remaining
budget, and Forge pauses polling if it drops below 100.

Job logs answer with a redirect to pre-signed blob storage. Forge follows it
**without** the GitHub token, which that storage would reject anyway.

## Test parsing

A job counts as a test when its name, its workflow's name or one of its step
commands looks like one (see `FORGE_TEST_PATTERN`). For finished test jobs
Forge strips timestamps and ANSI colour from the log and looks for:

| Tool | Line it reads |
|---|---|
| vitest | `Tests  2 failed \| 120 passed (122)` plus `FAIL  file > suite > test` lines |
| jest | `Tests: 1 failed, 11 passed, 12 total` plus `● Suite › test` |
| go test | `--- PASS` / `--- FAIL` |
| eslint | `✖ 12 problems (3 errors, 9 warnings)` |
| tsc | `error TS…` lines; a clean typecheck (no output) is recorded as 0 errors |

A **suite** is a (repo, workflow, job) combination. A suite is marked **flaky**
when, over its last 20 results (at least 5 of them), it changed between pass and fail at least 3
times and its pass rate is between 20% and 99%.

## Alerts

When a run finishes, Forge compares it with the previous finished run of the
same workflow on the same branch:

- failed, after a pass (or with no history) → **"failed"** email
- failed, after a failure → no email (logged in Activity as "still failing")
- passed, after a failure → **"recovered"** email
- cancelled or skipped → ignored

Runs that had already finished when Forge first saw a repo count as history,
not news, so installing Forge never sends a burst of old failures.

## AI explainer

For the item you clicked, Forge builds a context block: job name, workflow,
branch, commit, runner, status, every step with its duration, parsed test
results and failing test names. For failed jobs it adds an excerpt of about
160 log lines around the first failure marker (vitest's *Failed Tests*
section, `error TS`, eslint's summary, or GitHub's `##[error]`). It also
includes the workflow YAML at the exact commit that ran.

That block goes into the system prompt, below instructions to explain things
plainly to a non-engineer and to treat logs as data. Answers stream back token
by token. Requests use server-side refusal fallbacks, so a declined request is
retried on a fallback model instead of failing. First explanations are cached
per item and result in SQLite.

## Why jobs that use secrets shouldn't run on self-hosted runners

A self-hosted runner's disk and Docker cache **survive between jobs**. A job
that writes a credential to disk (a kubeconfig, a `.env` file, a registry
login) can leave it for the next job to find, and a public repo's pull
requests from forks can run arbitrary code on the machine. The pattern Forge
was built around:

- **Self-hosted:** lint, typecheck, unit tests, database migrations against a
  throwaway database. These are the bulk of CI minutes, and none of them needs
  secrets.
- **GitHub-hosted:** image builds that push to a registry, deploys, and anything
  that monitors production (it must not depend on your own infrastructure
  being up).

In the project this came from, that split moved roughly half of the monthly
Actions minutes to a free runner, and with a little more work would have kept
the rest inside GitHub's free tier.
