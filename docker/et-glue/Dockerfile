# Minimal Gitea Actions runner image for the Gitea <-> GitHub plumbing jobs.
#
# Used by exactly two workflows, both `runs-on: et-glue`:
#   .gitea/workflows/github-bridge.yml          (fast-forward the GitHub fork with main)
#   .gitea/workflows/mirror-github-release.yml  (copy GitHub release assets back to Gitea)
#
# The runner host maps its `et-glue` label to the image `et-glue:latest`, so
# that is the exact name that must exist on the host:
#
#   docker build -t et-glue:latest docker/et-glue          # or: podman build
#
# Building on another machine? Ship the image as a docker-archive. Save it
# under its fully-qualified name, otherwise `docker load` restores it as
# `localhost/et-glue:latest` and the runner will not find it:
#
#   podman tag et-glue:latest docker.io/library/et-glue:latest
#   podman save --format docker-archive -o et-glue.tar docker.io/library/et-glue:latest
#   gzip -9 et-glue.tar                                    # ~24 MB -> ~11 MB
#   # on the runner host:
#   docker load -i et-glue.tar.gz                          # docker reads gzip
#   podman load -i et-glue.tar.gz                          # podman ignores the name; then:
#   #   podman tag docker.io/library/et-glue:latest et-glue:latest
#
# What the two jobs actually invoke is the whole spec: bash (`[[ ]]`,
# `set -euo pipefail`), git (clone/push over https), curl, jq (release JSON)
# and CA roots for TLS. sed/awk/mktemp/sleep/printf come from busybox.
# Both workflows are pure `run:` steps — no `uses:` action — so no Node.js
# runtime is needed. python3 was dropped in favour of jq to keep the image
# small (jq is ~1 MB, the python3 package is tens of MB).
#
# Alpine's /bin/sh is busybox ash, which cannot parse the bash arrays both
# workflows use (`GH+=(-H ...)` is a syntax error there) and whose `[[` is not
# bash's. So both workflows pin `defaults: run: shell: bash` — if you ever drop
# that pin, the jobs break here first (verified: ash exits 2 on the mirror job).
# A Dockerfile SHELL directive does NOT help: it only affects RUN/CMD, not how
# the runner execs `run:` steps, and OCI-format builds ignore it entirely.
FROM alpine:3.21

RUN apk add --no-cache \
        bash \
        ca-certificates \
        curl \
        git \
        jq \
    # The runner checks the workspace out as a different uid than the one that
    # owns it, and the bridge job clones into a temp dir; without this git
    # aborts with "detected dubious ownership".
    && git config --system --add safe.directory '*'

CMD ["/bin/bash"]
