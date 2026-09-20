# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions before 1.0.0 may change configuration in a minor release; anything that
would break an existing install is called out under **Changed** with the
migration step.

## [Unreleased]

## [0.1.0] - 2026-09-20

First public release.

### Added

- **Live overview** — jobs in flight with per-step progress and timers, runs
  across every watched repository, and a job timeline per run that marks the
  failing step.
- **Runner fleet** — self-hosted runners (org- and repo-scoped) with idle / busy
  / offline state, current job, 24-hour utilisation, and optional runner-host
  CPU, memory and disk from Prometheus.
- **Testing view** — every test and check suite with pass history, flaky
  detection, and result counts parsed from job logs for vitest, jest, go test,
  eslint and tsc, including the names of failing tests.
- **Cost view** — self-hosted minutes priced at GitHub's per-minute rate, shown
  for the last 7 days.
- **Email alerts** on a workflow's pass → fail transition, on recovery, and when
  a self-hosted runner has been offline past the grace period. Resend or SMTP.
- **AI explainer and chat** (optional, Anthropic API) on any job, run, test suite
  or runner, with the job's steps, parsed results, failure-log excerpt and
  workflow file as context. First explanations are cached per item and state;
  per-IP rate limiting.
- **Install paths** — one-line installer, Docker, Docker Compose, Kubernetes
  manifests, or plain Python with no dependencies.
- **Docs** — configuration reference, how it works, and a self-hosted runner
  guide.

### Known limitations

- No authentication. Run it on a private network or behind an authenticating
  proxy.
- Single instance only (SQLite, one writer).
- GitHub Actions only.
- Test counts come from log summaries; unrecognised runners still show pass/fail
  without counts.

[Unreleased]: https://github.com/codephilip/forge-ci/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/codephilip/forge-ci/releases/tag/v0.1.0
