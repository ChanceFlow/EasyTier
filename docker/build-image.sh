#!/usr/bin/env bash
# Build the prebaked easytier-builder image used by the `easytier-builder`
# act_runner label (see .gitea/workflows/release.yml).
#
# The repo build context is a clean export of the committed HEAD (git
# archive) used to warm the cargo registry cache, so job runs download no
# crates and rebuild nothing they do not have to.
#
# Override via env:
#   PROXY          optional egress proxy, e.g. http://host:7890 — NOT
#                  committed anywhere; pass it at build time if the job
#                  containers need a proxy to reach crates.io / github.com
#   NO_PROXY_LIST  comma list that must bypass the proxy (defaults cover
#                  the gitea docker DNS name, loopback and the runner's
#                  cache host)
#   IMAGE_TAG      output tag, default easytier-builder:1 (+ :latest)
#   ANDROID_NDK    path to an Android NDK root (default: newest under
#                  $HOME/android-sdk/ndk) — baked into the image as
#                  /opt/ndk for *-linux-android cross builds
set -euo pipefail
cd "$(dirname "$0")"

REPO_ROOT=$(git rev-parse --show-toplevel)
IMAGE_TAG=${IMAGE_TAG:-easytier-builder:1}
# Defaults carry no internal addresses. Pass LAN ranges at build time, e.g.
#   NO_PROXY_LIST="gitea,localhost,127.0.0.1,::1,act_runner,<forge-host>,<docker-subnet>" ./build-image.sh
NO_PROXY_LIST=${NO_PROXY_LIST:-gitea,localhost,127.0.0.1,::1,act_runner}
if [[ -z "${ANDROID_NDK:-}" ]]; then
  ANDROID_NDK=$(ls -d "$HOME"/android-sdk/ndk/* 2>/dev/null | sort -V | tail -1)
fi
if [[ -z "$ANDROID_NDK" || ! -x "$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang" ]]; then
  echo "error: no Android NDK found (set ANDROID_NDK=/path/to/ndk)" >&2
  exit 1
fi

WARMUP=$(mktemp -d /tmp/easytier-image-repo.XXXXXX)
trap 'rm -rf "$WARMUP"' EXIT
git -C "$REPO_ROOT" archive HEAD | tar -x -C "$WARMUP"

ARGS=(
  -f easytier-runner.Dockerfile
  --build-context repo="$WARMUP"
  --build-context ndk="$ANDROID_NDK"
  --build-arg no_proxy="$NO_PROXY_LIST"
  -t "$IMAGE_TAG"
  -t easytier-builder:latest
  .
)
if [[ -n "${PROXY:-}" ]]; then
  ARGS+=(--build-arg http_proxy="$PROXY" --build-arg https_proxy="$PROXY" --build-arg all_proxy="$PROXY")
fi

echo "repo    : $(git -C "$REPO_ROOT" rev-parse --short HEAD) (committed tree)"
echo "ndk     : $ANDROID_NDK"
echo "proxy   : ${PROXY:-<direct>}"
echo "no_proxy: ${NO_PROXY_LIST}"
echo "tag     : $IMAGE_TAG"

docker buildx build "${ARGS[@]}"