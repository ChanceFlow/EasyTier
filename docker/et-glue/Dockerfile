# Minimal Gitea Actions runner image for the Gitea <-> GitHub plumbing jobs.
#
# Used by exactly two workflows, both `runs-on: et-glue`:
#   .gitea/workflows/github-bridge.yml          (fast-forward the GitHub fork with main)
#   .gitea/workflows/mirror-github-release.yml  (copy GitHub release assets back to Gitea)
#
# The runner host maps its `et-glue` label to the image `et-glue:latest`
# (act_runner_glue/config.yaml: `et-glue:docker://et-glue:latest`), so that is
# the exact name that must exist in the storage of the runtime the runner
# talks to - which on this host is **rootful** podman, because act_runner runs
# with DOCKER_HOST=unix:///run/podman/podman.sock. A `podman build` as a normal
# user lands in rootless storage and is invisible to the runner; note it and
# load into root:
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
#   sudo podman load -i et-glue.tar.gz                     # rootful - the runner's runtime
#   sudo docker load -i et-glue.tar.gz                     # ...or docker, if that is what it uses
#
# Verified against podman's docker-compat API (the exact call act_runner makes):
# POST /containers/create with Image=et-glue:latest answers 201 once the image
# is loaded, so the short name does resolve to docker.io/library/et-glue:latest.
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
