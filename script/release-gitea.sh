#!/usr/bin/env bash
#
# release-gitea.sh — build EasyTier release binaries and publish them to a
# Gitea/Forgejo release over the Gitea REST API.
#
# This script deliberately contains NO server addresses, tokens or secrets.
# Everything is supplied at runtime through environment variables or CLI
# arguments, so the file and its git history stay clean:
#
#   Required env:
#     GITEA_SERVER_URL   e.g. http://gitea.example:3000   (no trailing slash)
#     GITEA_TOKEN        Gitea access token with "repository" write scope
#
#   Optional env:
#     GITEA_OWNER        owner of the release repo (default: taken from the
#                        `origin` git remote)
#     GITEA_REPO         repo name (default: taken from the `origin` git remote)
#
#   Usage:
#     ./script/release-gitea.sh [--version v2.6.4] [--draft] [--publish]
#                               [--assets-dir DIR] [--skip-build] [--dry-run]
#
#     --version      release tag/version, defaults to v$(easytier crate
#                    version), e.g. v2.6.4
#     --draft        create the release as draft (default)
#     --publish      un-draft the release after uploading assets
#     --assets-dir   publish existing files from DIR instead of building
#                    (implies --skip-build)
#     --skip-build   do not run cargo build, use whatever exists in
#                    target/release
#     --dry-run      print the API requests without sending them
#
# The Gitea API creates the git tag automatically when the release is created
# (targeting the repo default branch), so no local `git tag` is needed.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=""
DRAFT=true
PUBLISH=false
ASSETS_DIR=""
SKIP_BUILD=false
DRY_RUN=false

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

# ---------------------------------------------------------------- arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"; shift 2 ;;
    --draft)      DRAFT=true;  shift ;;
    --publish)    PUBLISH=true; shift ;;
    --assets-dir) ASSETS_DIR="${2:-}"; SKIP_BUILD=true; shift 2 ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    -h|--help)    usage ;;
    *) echo "error: unknown argument: $1" >&2; usage ;;
  esac
done

# ------------------------------------------------------------------ config
GITEA_SERVER_URL="${GITEA_SERVER_URL:-}"
GITEA_TOKEN="${GITEA_TOKEN:-}"

if [[ -z "$GITEA_SERVER_URL" ]]; then
  echo "error: GITEA_SERVER_URL is not set" >&2
  echo "  export GITEA_SERVER_URL=http://<your-gitea-host>:3000" >&2
  exit 1
fi
if [[ -z "$GITEA_TOKEN" ]]; then
  echo "error: GITEA_TOKEN is not set" >&2
  echo "  export GITEA_TOKEN=<access-token-with-repository-write-scope>" >&2
  exit 1
fi

# Derive owner/repo from the origin remote unless overridden.
remote_url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
if [[ -z "$remote_url" ]]; then
  echo "error: no origin remote and GITEA_OWNER/GITEA_REPO not set" >&2
  exit 1
fi

GITEA_OWNER="${GITEA_OWNER:-}"
GITEA_REPO="${GITEA_REPO:-}"
if [[ -z "$GITEA_OWNER" || -z "$GITEA_REPO" ]]; then
  # Derive owner/repo, supporting:
  #   http(s)://host[:port]/owner/repo.git   and   git@host:owner/repo.git
  if [[ "$remote_url" == *"://"* ]]; then
    rest="${remote_url#*://}"
    rest="${rest#*@}"
    path="${rest#*/}"          # drop host[:port]
  else
    rest="${remote_url#*@}"    # scp-like syntax
    path="${rest#*:}"
  fi
  path="${path%.git}"
  owner="${path%/*}"
  repo="${path#*/}"
  GITEA_OWNER="${GITEA_OWNER:-$owner}"
  GITEA_REPO="${GITEA_REPO:-$repo}"
fi

if [[ -z "$VERSION" ]]; then
  crate_version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$REPO_ROOT/easytier/Cargo.toml" | head -1)"
  VERSION="v${crate_version}"
  echo "guessed version from easytier/Cargo.toml: $VERSION"
fi

API="$GITEA_SERVER_URL/api/v1/repos/$GITEA_OWNER/$GITEA_REPO"
AUTH="Authorization: token $GITEA_TOKEN"
JSON="Content-Type: application/json"

echo "==> target : $GITEA_SERVER_URL/releases"   # NOTE: server URL is printed
echo "==> repo   : $GITEA_OWNER/$GITEA_REPO"      #       only at runtime, never
echo "==> version: $VERSION"                      #       stored in this file
echo "==> draft  : $DRAFT    publish: $PUBLISH"

# ------------------------------------------------------------------- build
if [[ -n "$ASSETS_DIR" ]]; then
  ASSETS_DIR="$(cd "$ASSETS_DIR" && pwd)"
  echo "==> publishing existing assets from $ASSETS_DIR"
elif [[ "$SKIP_BUILD" == true ]]; then
  ASSETS_DIR="$REPO_ROOT/target/release"
  echo "==> using existing binaries in $ASSETS_DIR"
else
  echo "==> building release binaries (host target)..."
  (
    cd "$REPO_ROOT"
    cargo build --release --features=jemalloc --package=easytier
    # easytier-web embeds the web dashboard; requires frontend/dist, see
    # .github/actions/prepare-pnpm. Skip gracefully when dist is missing.
    if [[ -f easytier-web/frontend/dist/index.html ]]; then
      cargo build --release --features=embed --package=easytier-web
    else
      echo "!! easytier-web/frontend/dist not built, skipping easytier-web embed"
    fi
  )
  ASSETS_DIR="$REPO_ROOT/target/release"
fi

# -------------------------------------------------------------------- zip
zipped=()
shopt -s nullglob
for artifact in "$ASSETS_DIR"/easytier-core "$ASSETS_DIR"/easytier-cli \
                "$ASSETS_DIR"/easytier-web "$ASSETS_DIR"/easytier-web-embed; do
  [[ -f "$artifact" ]] && zipped+=("$artifact")
done

if [[ ${#zipped[@]} -eq 0 ]]; then
  echo "error: no easytier binaries found in $ASSETS_DIR" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
for bin in "${zipped[@]}"; do
  name="$(basename "$bin")"
  cp "$bin" "$tmpdir/$name"
done

# name the zip like the GitHub release convention: <name>-<version>.zip
zip_name="easytier-${VERSION}.zip"
zip_out="$REPO_ROOT/$zip_name"
(
  cd "$tmpdir"
  zip -qr "$zip_out" .
)
echo "==> packaged $zip_out"
ls -lh "$zip_out"

# ---------------------------------------------------------------- API calls
api_request() {
  # api_request METHOD URL [CURL_ARGS...]
  local method="$1" url="$2"
  shift 2
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] $method $url"
    return 0
  fi
  curl -fsS -X "$method" "$url" -H "$AUTH" "$@"
}

echo "==> creating release $VERSION (draft=$DRAFT)..."
# The tag must exist AND point at the built commit, otherwise this Gitea
# stores an empty-sha1 release that never becomes visible. Push the tag
# from the local repo first (tag name = $VERSION at current HEAD), then
# create the release with a non-empty body.
ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin)"
git -C "$REPO_ROOT" tag -f "$VERSION"
git -C "$REPO_ROOT" -c "http.extraheader=Authorization: token $GITEA_TOKEN" push -f \
  "$ORIGIN_URL" "$VERSION" || echo "!! tag push failed (release requires an existing tag at this commit)"

HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
release_json="$(api_request POST "$API/releases" -H "$JSON" \
  -d "{\"tag_name\":\"$VERSION\",\"name\":\"EasyTier $VERSION\",\"body\":\"EasyTier $VERSION release build.\",\"draft\":$DRAFT,\"target_commitish\":\"$HEAD_SHA\"}" \
  || true)"

if [[ -z "$release_json" ]]; then
  echo "!! release create failed, trying to reuse existing release with the same tag"
  release_json="$(api_request GET "$API/releases/tags/$VERSION")"
fi

release_id="$(printf '%s' "$release_json" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -1)"
if [[ -z "$release_id" ]]; then
  echo "error: could not determine release id from API response" >&2
  echo "response: $release_json" >&2
  exit 1
fi
echo "==> release id: $release_id"

echo "==> uploading $zip_name"
# right after release creation Gitea can transiently 404 the attachment
# lookup; retry a few times.
uploaded=false
for attempt in 1 2 3 4 5; do
  if api_request POST "$API/releases/$release_id/assets?name=$zip_name" \
      -F "attachment=@$zip_out"; then
    uploaded=true
    break
  fi
  echo "!! upload attempt $attempt failed, retrying in 5s"
  sleep 5
done
if [[ "$uploaded" != true && "$DRY_RUN" != true ]]; then
  echo "error: could not upload $zip_name after 5 attempts" >&2
  exit 1
fi

if [[ "$PUBLISH" == true && "$DRAFT" == true ]]; then
  echo "==> publishing release"
  api_request PATCH "$API/releases/$release_id" -H "$JSON" -d '{"draft":false}'
fi

echo "==> done: $GITEA_SERVER_URL/$GITEA_OWNER/$GITEA_REPO/releases/tag/$VERSION"
echo "==> local artifact: $zip_out"