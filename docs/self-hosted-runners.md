# Self-hosted runners

Forge was built to sit on top of self-hosted runners. This page covers the runner
side: what one is, how to set some up, how to point an existing project at them,
and what to keep on GitHub-hosted runners.

None of this is required to use Forge — it reads GitHub-hosted runs just as well.

## What moving to your own runners changes

| | Before | After |
|---|---|---|
| Triggers the run, stores logs, shows the check | GitHub | **GitHub** (unchanged) |
| Executes the job | a machine GitHub rents you | **your machine** |
| Cost per minute | ~$0.006 | **nothing** |
| Works while GitHub is down | no | **no** — GitHub still schedules every run |

Self-hosted runners are a GitHub Actions feature, not a way to leave GitHub.
Your workflows, your pull-request checks and your logs stay exactly where they
are; only the hardware changes.

## What a self-hosted runner is

A small program (`actions/runner`) that runs on a machine you own. It opens an
outbound connection to GitHub, waits to be given a job, runs it, and reports
back. There is no inbound port and no public endpoint, so it works behind NAT.

Two things follow:

- **Its minutes are free.** GitHub bills rented runners per minute (about
  $0.006/min for Linux) and nothing for your own.
- **Its disk survives between jobs.** That's what makes it fast (warm caches)
  and what makes secrets risky — see [what to keep on GitHub](#what-to-keep-on-github-hosted-runners).

Forge doesn't install, manage or talk to runners. It reads their status from the
GitHub API and shows it next to the jobs they ran.

## Setting up runners

### The quick way (one runner, from GitHub's UI)

In the repository or organisation: **Settings → Actions → Runners → New runner**.
GitHub shows the exact commands to download, configure and start it. Give it
labels you'll target later, then install it as a service so it survives reboot:

```bash
./config.sh --url https://github.com/OWNER/REPO --token <registration token> \
            --name build-box --labels self-hosted,linux,build-box --unattended
sudo ./svc.sh install && sudo ./svc.sh start
```

### Repo runners vs org runners

| | Serves | Needs |
|---|---|---|
| **Repository runner** | that one repository | admin on the repo |
| **Organisation runner** | every repo in the org (private ones by default) | org owner |

An org runner is usually what you want past the first repo: register once, and
every private repository in the org can use it. Check
**Settings → Actions → Runner groups**: the Default group excludes public
repositories, which is the safe setting.

### The repeatable way (Ansible)

Doing this by hand doesn't survive a rebuild. The author's homelab — the machines
this Forge instance and its runners run on — is public and built with Terraform +
Ansible:

**[github.com/codephilip/homelab](https://github.com/codephilip/homelab)**

`ansible/ci.yml` there installs a runner on a VM: it creates a dedicated `runner`
user, downloads the runner, fetches a registration token from the GitHub API
(keeping your PAT on your laptop, not the server), registers with labels, and
installs the systemd service.

For more than one runner per machine, the shape that works well is a systemd
**template unit** plus one directory per runner:

```ini
# /etc/systemd/system/github-runner@.service
[Unit]
Description=GitHub Actions runner %i
After=network-online.target docker.service

[Service]
User=runner
WorkingDirectory=/home/runner/runners/%i
ExecStart=/home/runner/runners/%i/runsvc.sh
KillMode=process
Restart=always
MemoryHigh=80%

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now github-runner@build-1 github-runner@build-2
```

Worth adding on the runner host, because GitHub's images have them and your
machine doesn't:

- **Docker + buildx** — a missing `docker buildx` is the most common reason a
  workflow that passes on GitHub fails on your runner.
- **Common CLI tools** your workflows assume: `git`, `jq`, `zip`, `psql`, `yq`.
- **Passwordless sudo for the runner user**, if workflows run `sudo apt-get install …`.
- **A daily `docker system prune`** — build caches will otherwise fill the disk.
- **Memory headroom**: a Node typecheck or build can reserve 4 GB. Two or three
  concurrent runners on an 8 GB box will start failing with out-of-memory errors.

## Linking an existing project

### …to Forge (read-only, nothing installed)

Add the repository to Forge's settings and restart it:

```bash
# ~/.forge-ci/forge.env
FORGE_REPOS=owner/repo,owner/another
FORGE_RUNNER_REPOS=owner/repo      # repos whose own runners you want listed
FORGE_ORGS=my-org                  # optional: every private repo in the org
```

Nothing is added to the project, and its team doesn't have to do anything. The
token needs `repo` to read private repositories, and `admin:org` (or repo admin)
to *list* runners. If it can't list them, Forge hides the fleet strip rather than
erroring. See [configuration.md](configuration.md#token-scopes).

### …to your runners (one line in the project)

Runner choice lives in the project's own workflow file, not in Forge:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest            # before: rented from GitHub
    runs-on: [self-hosted, build-box] # after: your machine, matched by labels
```

All labels must match, so `[self-hosted, build-box]` only picks runners carrying
both. Give runners a label per capability (`build-box`, `gpu`, `arm64`) and
target that, rather than naming a specific machine.

### A kill switch worth having

If your runner is down, jobs pinned to it queue rather than fail — for up to 24
hours. Reading the target from a repository variable lets you move every job back
to GitHub in one click (**Settings → Secrets and variables → Actions → Variables**):

```yaml
runs-on: ${{ fromJSON(vars.CI_RUNS_ON || '["self-hosted","build-box"]') }}
```

Set `CI_RUNS_ON` to `["ubuntu-latest"]` and the next run goes back to GitHub-hosted,
with no commit and no PR.

## What to keep on GitHub-hosted runners

A self-hosted runner's disk persists between jobs, so treat it as a shared
machine:

- **Jobs that use secrets** — deploy credentials, registry logins, kubeconfigs.
  A file left behind is readable by the next job.
- **Anything that monitors production.** An uptime check that runs on your own
  hardware goes quiet exactly when your hardware does.
- **Public repositories.** A pull request from a fork would run a stranger's code
  on your machine. If you must, set **Settings → Actions → Require approval for
  all external contributors**.

What's left — lint, typecheck, unit tests, migrations against a throwaway
database — is usually the bulk of the minutes and needs no secrets at all.

## Checking it worked

In Forge:

- the runner appears in the fleet strip as **idle**, and flips to **busy** with
  the job name while it runs;
- jobs that ran on it are tagged with your runner label instead of `github`;
- **Saved · 7d** starts counting what those minutes would have cost;
- the **Testing** tab shows which suites run where, so you can see the split at a
  glance.

If a job sits queued forever, the labels in `runs-on` don't match any online
runner — that mismatch is the usual cause.
