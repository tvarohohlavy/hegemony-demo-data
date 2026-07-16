#!/bin/sh
# SPDX-FileCopyrightText: 2026 Jakub Travnik <jakub.travnik@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# One-command installer for the Hegemony demo.
#
# Versioned release (recommended — pin the exact tag; immutable + reproducible):
#   curl -fsSL https://github.com/tvarohohlavy/hegemony-demo-data/releases/download/vX.Y.Z/install.sh | sh
# Floating latest release (follows the newest release; convenient, not pinned):
#   curl -fsSL https://github.com/tvarohohlavy/hegemony-demo-data/releases/latest/download/install.sh | sh
# Bleeding edge (tracks main):
#   curl -fsSL https://raw.githubusercontent.com/tvarohohlavy/hegemony-demo-data/main/install.sh | sh
#   curl -fsSL https://hegemony.sh/install.sh | sh            # once the site fronts the latest release asset
#
# This clones the platform repository and this demo-data repository as siblings
# and runs the demo through the platform repo's own Taskfile, so the compose and
# Task definitions come straight from source (the application images are still
# pulled from ghcr.io) — nothing is copied or vendored into this repository.
#
# Assumes the machine already has:
#   - git, with read access to the platform repository
#   - docker with the compose v2 plugin
#   - go-task (https://taskfile.dev) — used to bring the stack up
#   - docker authenticated to ghcr.io (`docker login ghcr.io`) to pull images
#
# Options (also as: curl ... | sh -s -- --dir ./demo --platform-ref main):
#   --dir <dir>            workspace dir            (env: HEGEMONY_DEMO_DIR;  default ./hegemony-demo)
#   --platform-ref <ref>   platform repo tag/branch (env: HEGEMONY_PLATFORM_REF; default v2.0.0)
#   --demo-ref <ref>       demo-data repo tag/branch (env: HEGEMONY_DEMO_REF;  default this installer's version)
#   --no-up                clone only, do not start the stack
#   --version              print the installer version and exit
#   --help                 print this usage and exit

set -eu
unset CDPATH 2>/dev/null || true

# Stamped to the release tag when this script is published as a release asset
# (scripts/checksums.py + the release workflow); stays "main" in the committed
# and raw copies. This is what makes a downloaded installer clearly versioned.
INSTALLER_VERSION=main

PLATFORM_REPO=${HEGEMONY_PLATFORM_REPO:-https://github.com/tvarohohlavy/InfraHorizon.git}
DEMO_DATA_REPO=${HEGEMONY_DEMO_DATA_REPO:-https://github.com/tvarohohlavy/hegemony-demo-data.git}
PLATFORM_REF=${HEGEMONY_PLATFORM_REF:-v2.0.0}
# Defaults to this installer's own version, so the release asset for vX.Y.Z
# installs demo-data@vX.Y.Z (reproducible) and the raw main copy installs main.
DEMO_REF=${HEGEMONY_DEMO_REF:-$INSTALLER_VERSION}
# The bootstrap mount in the demo overlay is ../../../hegemony-demo-data/dist,
# so the demo-data checkout MUST be a sibling named exactly this.
DEMO_DATA_DIRNAME=hegemony-demo-data
PLATFORM_DIRNAME=hegemony
# Image ref used only for the pre-flight auth check; overridable for forks.
AUTH_CHECK_IMAGE=${HEGEMONY_AUTH_CHECK_IMAGE:-ghcr.io/tvarohohlavy/hegemony/api}

log() { echo "[hegemony-demo] $*"; }
err() {
  echo "[hegemony-demo] ERROR: $*" >&2
  exit 1
}

# Printed by --help. Kept in a heredoc (not `sed "$0"`) so it works when the
# script is piped to sh, where $0 is the shell rather than this file.
usage() {
  cat <<'EOF'
One-command installer for the Hegemony demo. Clones the platform and demo-data
repositories as siblings and brings the demo up via the platform Taskfile.

Requires: git (with access to the platform repo), docker + the compose v2
plugin, go-task, and `docker login ghcr.io`.

Usage: install.sh [options]
  --dir <dir>           workspace dir            (env HEGEMONY_DEMO_DIR;      default ./hegemony-demo)
  --platform-ref <ref>  platform repo tag/branch (env HEGEMONY_PLATFORM_REF;  default v2.0.0)
  --demo-ref <ref>      demo-data repo tag/branch (env HEGEMONY_DEMO_REF;     default this installer's version)
  --no-up               clone only, do not start the stack
  --version             print the installer version and exit
  --help                print this usage and exit
EOF
}

preflight() {
  command -v git >/dev/null 2>&1 || err "git is required"
  command -v curl >/dev/null 2>&1 || err "curl is required"
  command -v docker >/dev/null 2>&1 \
    || err "docker is required — https://docs.docker.com/engine/install/"
  docker info >/dev/null 2>&1 \
    || err "cannot talk to the Docker daemon — is it running, and can your user access it?"

  compose_version=$(docker compose version --short 2>/dev/null) \
    || err "the 'docker compose' v2 plugin is required (classic docker-compose is not supported)"
  compose_version=${compose_version#v}
  compose_major=${compose_version%%.*}
  case "$compose_major" in *[!0-9]*|'') compose_major=0 ;; esac
  [ "$compose_major" -ge 2 ] || err "docker compose v2+ is required (found $compose_version)"
}

detect_docker_gid() {
  if [ -n "${DOCKER_GID:-}" ]; then
    echo "$DOCKER_GID"
  elif command -v getent >/dev/null 2>&1 && getent group docker >/dev/null 2>&1; then
    getent group docker | cut -d: -f3
  elif [ -S /var/run/docker.sock ] && stat -c %g /var/run/docker.sock >/dev/null 2>&1; then
    stat -c %g /var/run/docker.sock
  elif [ -S /var/run/docker.sock ] && stat -f %g /var/run/docker.sock >/dev/null 2>&1; then
    stat -f %g /var/run/docker.sock
  else
    echo 999
  fi
}

clone_or_update() { # $1=url $2=ref $3=dest
  url=$1
  ref=$2
  dest=$3
  if [ -d "$dest/.git" ]; then
    log "Updating $(basename "$dest") to $ref ..."
    git -C "$dest" fetch --depth 1 origin "$ref" \
      || err "git fetch of $ref from $url failed (do you have access?)"
    git -C "$dest" checkout -q --detach FETCH_HEAD
  else
    log "Cloning $(basename "$dest") at $ref ..."
    git clone --depth 1 --branch "$ref" "$url" "$dest" 2>/dev/null \
      || err "git clone of $ref from $url failed — check the ref and your access to $url"
  fi
}

require_task() {
  command -v task >/dev/null 2>&1 \
    || err "go-task is required to bring the demo up — install it (https://taskfile.dev) and re-run.
       (Use --no-up to just clone the repositories without starting the stack.)"
}

check_ghcr_auth() { # $1=platform-dir
  tag=$(sed -n 's/^HEGEMONY_IMAGE_TAG=//p' "$1/deploy/compose/.env.demo" | tail -n 1)
  tag=${tag:-latest}
  log "Verifying ghcr.io access ($AUTH_CHECK_IMAGE:$tag) ..."
  docker pull "$AUTH_CHECK_IMAGE:$tag" >/dev/null 2>&1 \
    || err "cannot pull $AUTH_CHECK_IMAGE:$tag — run 'docker login ghcr.io' with an account
       that has access to the Hegemony packages, then re-run this installer"
}

main() {
  no_up=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) HEGEMONY_DEMO_DIR=${2:?--dir needs a value}; shift 2 ;;
      --platform-ref) PLATFORM_REF=${2:?--platform-ref needs a value}; shift 2 ;;
      --demo-ref) DEMO_REF=${2:?--demo-ref needs a value}; shift 2 ;;
      --no-up) no_up=1; shift ;;
      --version) echo "$INSTALLER_VERSION"; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      *) err "unknown option: $1" ;;
    esac
  done

  log "installer version: $INSTALLER_VERSION"
  preflight

  WORKSPACE=${HEGEMONY_DEMO_DIR:-./hegemony-demo}
  mkdir -p "$WORKSPACE"
  WORKSPACE=$(cd -- "$WORKSPACE" && pwd)
  platform_dir="$WORKSPACE/$PLATFORM_DIRNAME"
  demo_data_dir="$WORKSPACE/$DEMO_DATA_DIRNAME"

  clone_or_update "$PLATFORM_REPO" "$PLATFORM_REF" "$platform_dir"
  clone_or_update "$DEMO_DATA_REPO" "$DEMO_REF" "$demo_data_dir"
  log "Installed into $WORKSPACE (platform@$PLATFORM_REF, demo-data@$DEMO_REF)"

  if [ -n "$no_up" ]; then
    log "Skipping stack start (--no-up). Start it with:"
    log "  cd $platform_dir && task compose:demo:up"
    exit 0
  fi

  require_task
  check_ghcr_auth "$platform_dir"

  gid=$(detect_docker_gid)
  log "Bringing up the demo (DOCKER_GID=$gid) ..."
  # Exported DOCKER_GID wins over .env.demo in compose interpolation.
  ( cd "$platform_dir" && DOCKER_GID="$gid" task compose:demo:up )

  echo ""
  log "Lifecycle (run from $platform_dir):"
  log "  task compose:demo:down     # stop, keep data"
  log "  task compose:demo:reset    # stop and wipe all data"
  log "  task compose:demo:logs     # follow logs"
}

main "$@"
