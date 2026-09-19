#!/usr/bin/env bash
# Forge installer — gets a Forge dashboard running in Docker in about a minute.
#
#   curl -fsSL https://raw.githubusercontent.com/codephilip/forge-ci/main/install.sh | bash
#
# What it does:
#   1. checks Docker is running
#   2. finds a GitHub token (GITHUB_TOKEN, then `gh auth token`, then asks)
#   3. asks which repos to watch (and, optionally, AI + email settings)
#   4. writes ~/.forge-ci/forge.env (chmod 600)
#   5. pulls the image (or builds it from source if the pull fails) and starts it
#
# Re-running is safe: it keeps your settings unless you choose to change them.
# Non-interactive: set GITHUB_TOKEN and FORGE_REPOS (and anything else from
# .env.example) in the environment and pass --yes.
#
# Flags:  --yes          don't ask; use environment / existing config
#         --reconfigure  ask again even if a config exists
#         --uninstall    stop and remove the container (keeps data + config)
#         --purge        also delete the data volume and config
set -euo pipefail

IMAGE="${FORGE_IMAGE:-ghcr.io/codephilip/forge-ci:latest}"
SOURCE="${FORGE_SOURCE:-https://github.com/codephilip/forge-ci.git#main}"
NAME="${FORGE_CONTAINER:-forge-ci}"
PORT="${FORGE_PORT:-8080}"
CONF_DIR="${FORGE_CONF_DIR:-$HOME/.forge-ci}"
CONF="$CONF_DIR/forge.env"
VOLUME="forge-ci-data"

YES=0; RECONF=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --reconfigure) RECONF=1 ;;
    --uninstall|--purge)
      docker rm -f "$NAME" >/dev/null 2>&1 && echo "Removed container $NAME." || echo "No container $NAME."
      if [ "$arg" = --purge ]; then
        docker volume rm "$VOLUME" >/dev/null 2>&1 && echo "Removed volume $VOLUME."
        rm -rf "$CONF_DIR" && echo "Removed $CONF_DIR."
      else
        echo "Kept data volume $VOLUME and config $CONF (use --purge to delete them)."
      fi
      exit 0 ;;
    -h|--help) sed -n '2,23p' "$0" 2>/dev/null || echo "See https://github.com/codephilip/forge-ci"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

bold=$(printf '\033[1m'); dim=$(printf '\033[2m'); red=$(printf '\033[31m'); grn=$(printf '\033[32m'); ylw=$(printf '\033[33m'); off=$(printf '\033[0m')
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==>%s %s\n' "$bold" "$off" "$*"; }
warn() { printf '%s!%s %s\n' "$ylw" "$off" "$*"; }
die()  { printf '%sx%s %s\n' "$red" "$off" "$*" >&2; exit 1; }

# When piped (curl | bash) stdin is this script, so prompts read the terminal.
TTY=/dev/tty
ask() {  # ask VAR "Question" [default] [secret]
  local var="$1" q="$2" def="${3:-}" secret="${4:-}" ans=""
  if [ "$YES" = 1 ] || [ ! -r "$TTY" ]; then printf -v "$var" '%s' "$def"; return; fi
  if [ -n "$def" ] && [ -z "$secret" ]; then q="$q ${dim}[$def]${off}"; fi
  if [ -n "$secret" ]; then read -rsp "$q: " ans <"$TTY"; echo; else read -rp "$q: " ans <"$TTY"; fi
  printf -v "$var" '%s' "${ans:-$def}"
}

gh_api() {  # gh_api TOKEN PATH  -> prints HTTP status
  curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $1" \
       -H "Accept: application/vnd.github+json" "https://api.github.com$2"
}

say "${bold}Forge${off} — GitHub Actions dashboard  ${dim}(https://github.com/codephilip/forge-ci)${off}"

# ---------------------------------------------------------------- docker ----
step "Checking Docker"
command -v docker >/dev/null 2>&1 || die "Docker is not installed. Get it from https://docs.docker.com/get-docker/ and re-run."
docker info >/dev/null 2>&1 || die "Docker is installed but not running. Start Docker Desktop (or the docker service) and re-run."
say "${grn}ok${off} $(docker version --format '{{.Server.Version}}' 2>/dev/null | sed 's/^/Docker /')"

# ---------------------------------------------------------------- config ----
mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
if [ -f "$CONF" ] && [ "$RECONF" = 0 ]; then
  step "Using existing settings in $CONF"
  say "${dim}(run with --reconfigure to change them)${off}"
else
  step "GitHub access"
  TOKEN="${GITHUB_TOKEN:-}"
  if [ -z "$TOKEN" ] && command -v gh >/dev/null 2>&1; then
    TOKEN="$(gh auth token 2>/dev/null || true)"
    [ -n "$TOKEN" ] && say "Found a token from the GitHub CLI (gh)."
  fi
  if [ -z "$TOKEN" ]; then
    say "Forge reads your Actions runs with a GitHub token."
    say "Create one at ${bold}https://github.com/settings/tokens/new?scopes=repo&description=Forge${off}"
    say "${dim}(scope 'repo' for private repos; add 'admin:org' to see an org's self-hosted runners)${off}"
    ask TOKEN "Paste the token" "" secret
  fi
  [ -n "$TOKEN" ] || die "A GitHub token is required (set GITHUB_TOKEN or paste one)."
  code=$(gh_api "$TOKEN" /user)
  [ "$code" = 200 ] || die "GitHub rejected that token (HTTP $code)."
  LOGIN=$(curl -s -H "Authorization: Bearer $TOKEN" https://api.github.com/user | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p' | head -1)
  say "${grn}ok${off} signed in as ${bold}$LOGIN${off}"

  step "What should Forge watch?"
  REPOS="${FORGE_REPOS:-}"
  if [ -z "$REPOS" ]; then
    # Suggest the account's most recently pushed repos as a starting point.
    SUGGEST=$(curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/user/repos?sort=pushed&per_page=3&affiliation=owner" \
              | sed -n 's/.*"full_name": *"\([^"]*\)".*/\1/p' | paste -sd, -)
    say "Repos as ${bold}owner/name${off}, comma-separated."
    ask REPOS "Repos" "$SUGGEST"
  fi
  REPOS=$(printf '%s' "$REPOS" | tr -d ' ')
  [ -n "$REPOS" ] || die "Give Forge at least one repo to watch (FORGE_REPOS=owner/name)."
  IFS=, read -ra LIST <<<"$REPOS"
  for r in "${LIST[@]}"; do
    code=$(gh_api "$TOKEN" "/repos/$r/actions/runs?per_page=1")
    if [ "$code" = 200 ]; then say "${grn}ok${off} $r"; else warn "$r — HTTP $code (typo, or the token can't read it); Forge will show an error for it."; fi
  done
  ORGS="${FORGE_ORGS:-}"
  ask ORGS "Also watch every private repo in an org? org name(s), or Enter to skip" "$ORGS"

  step "Optional extras (press Enter to skip any)"
  say "${dim}What each one is for: https://github.com/codephilip/forge-ci#credentials-what-youll-be-asked-for-and-why${off}"
  AI="${ANTHROPIC_API_KEY:-}"
  [ -n "$AI" ] || ask AI "Anthropic API key for the AI explainer" "" secret
  NOTIFY_TO="${NOTIFY_TO:-}"
  ask NOTIFY_TO "Email address for failure alerts" "$NOTIFY_TO"
  RESEND=""; NOTIFY_FROM="${NOTIFY_FROM:-Forge CI <onboarding@resend.dev>}"
  if [ -n "$NOTIFY_TO" ]; then
    RESEND="${RESEND_API_KEY:-}"
    [ -n "$RESEND" ] || ask RESEND "Resend API key (https://resend.com; or set SMTP_* in $CONF later)" "" secret
  fi

  umask 077
  {
    echo "# Forge settings — written by install.sh on $(date -u +%Y-%m-%dT%H:%MZ). Edit and re-run install.sh to apply."
    echo "GITHUB_TOKEN=$TOKEN"
    echo "FORGE_REPOS=$REPOS"
    [ -n "$ORGS" ] && echo "FORGE_ORGS=$ORGS"
    echo "FORGE_RUNNER_REPOS=$REPOS"
    echo "FORGE_URL=http://localhost:$PORT"
    [ -n "$AI" ] && echo "ANTHROPIC_API_KEY=$AI"
    if [ -n "$NOTIFY_TO" ]; then
      echo "NOTIFY_TO=$NOTIFY_TO"
      echo "NOTIFY_FROM=$NOTIFY_FROM"
      [ -n "$RESEND" ] && echo "RESEND_API_KEY=$RESEND"
    fi
  } >"$CONF"
  chmod 600 "$CONF"
  say "${grn}ok${off} saved $CONF"
fi

# ----------------------------------------------------------------- image ----
step "Getting the Forge image"
if docker pull -q "$IMAGE" >/dev/null 2>&1; then
  say "${grn}ok${off} pulled $IMAGE"
elif docker image inspect "$IMAGE" >/dev/null 2>&1; then
  warn "Couldn't pull $IMAGE — using the copy already on this machine."
else
  warn "Couldn't pull $IMAGE — building it from source instead (about a minute)."
  docker build -q -t "$IMAGE" "$SOURCE" >/dev/null || die "Build failed. Clone the repo and run 'docker compose up --build' to see why."
  say "${grn}ok${off} built $IMAGE"
fi

# ------------------------------------------------------------------- run ----
step "Starting Forge"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped \
  -p "$PORT:8080" --env-file "$CONF" -v "$VOLUME:/data" "$IMAGE" >/dev/null \
  || die "Couldn't start the container. Is port $PORT in use? Try: FORGE_PORT=8090 bash install.sh"

URL="http://localhost:$PORT"
for _ in $(seq 1 30); do
  curl -fs "$URL/healthz" >/dev/null 2>&1 && break
  sleep 1
done
curl -fs "$URL/healthz" >/dev/null 2>&1 || die "Forge didn't come up. See: docker logs $NAME"

say ""
say "${grn}${bold}Forge is running → $URL${off}"
say "${dim}The first sync takes a minute or two for busy repos. Logs: docker logs -f $NAME · Settings: $CONF${off}"
say "${dim}Uninstall: curl -fsSL https://raw.githubusercontent.com/codephilip/forge-ci/main/install.sh | bash -s -- --uninstall${off}"
if [ "$YES" = 0 ]; then
  if command -v open >/dev/null 2>&1; then open "$URL" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL" >/dev/null 2>&1 || true; fi
fi
