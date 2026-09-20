# Releasing

Versions follow [SemVer](https://semver.org). For Forge the "public API" that
SemVer protects is: **environment variable names and their meanings**, the
**database file and its location**, the **HTTP endpoints**, and the
**container's behaviour on start**. Renaming a setting or changing the data
layout is a breaking change; adding a panel to the UI is not.

Before 1.0.0, a minor release may change configuration — anything that breaks an
existing install is listed in the changelog with its migration step.

## Cutting a release

1. Bump `VERSION` in `forge/server.py`.
2. Move the `## [Unreleased]` items in `CHANGELOG.md` under a new version
   heading with today's date, and update the links at the bottom.
3. Commit: `git commit -am "release: 0.2.0"`.
4. Tag and push:

   ```bash
   git tag -a v0.2.0 -m "Forge 0.2.0"
   git push origin main --follow-tags
   ```
5. CI builds and publishes the image for that tag, then create the GitHub
   release notes:

   ```bash
   gh release create v0.2.0 --title "Forge 0.2.0" --notes-from-tag
   ```

## What the tag publishes

For `v0.2.0`, CI pushes these image tags to GHCR:

| Tag | Moves | Use it when |
|---|---|---|
| `0.2.0` | never | you want a fixed version (production, Kubernetes) |
| `0.2` | on each patch release | you want bug fixes automatically |
| `latest` | on each push to `main` | you're trying Forge out |
| `sha-<commit>` | never | you're testing an unreleased commit |

Upgrading an install means pointing at the new tag and restarting: for Docker,
`docker pull … && docker rm -f forge-ci` then re-run the installer; for
Kubernetes, bump the tag in your manifest. The database carries over; Forge
migrates its own schema on start.
