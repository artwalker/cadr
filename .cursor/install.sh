#!/usr/bin/env bash
# Idempotent Cloud Agent bootstrap for the cadr SBCL project.
#
# Prepares everything ./build.sh, ./build-server.sh, and the test/smoke
# scripts need: a modern SBCL, Quicklisp, the system OpenSSL/SQLite runtime,
# and the external Quicklisp systems the ASDF systems depend on.
set -euo pipefail

SBCL_VERSION="2.6.7"
SBCL_MIN_MAJOR=2
SBCL_MIN_MINOR=4
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"

log() { printf 'cadr install: %s\n' "$*"; }

sbcl_is_recent_enough() {
  command -v sbcl >/dev/null 2>&1 || return 1
  local version major remainder minor
  version="$(sbcl --noinform --version | awk '{print $2}')"
  version="${version%%.debian*}"
  major="${version%%.*}"
  remainder="${version#*.}"
  minor="${remainder%%.*}"
  [ "$major" -gt "$SBCL_MIN_MAJOR" ] ||
    { [ "$major" -eq "$SBCL_MIN_MAJOR" ] && [ "$minor" -ge "$SBCL_MIN_MINOR" ]; }
}

log "installing system packages"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  build-essential \
  curl \
  git \
  jq \
  libssl-dev \
  libsqlite3-dev \
  zlib1g-dev

if sbcl_is_recent_enough; then
  log "SBCL $(sbcl --noinform --version | awk '{print $2}') already satisfies >= ${SBCL_MIN_MAJOR}.${SBCL_MIN_MINOR}"
else
  log "installing SBCL ${SBCL_VERSION} (prebuilt x86-64 Linux binary)"
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "$tmp"' EXIT
  curl -fL --retry 4 --retry-delay 4 \
    -o "$tmp/sbcl.tar.bz2" \
    "https://downloads.sourceforge.net/project/sbcl/sbcl/${SBCL_VERSION}/sbcl-${SBCL_VERSION}-x86-64-linux-binary.tar.bz2"
  tar -xjf "$tmp/sbcl.tar.bz2" -C "$tmp"
  ( cd "$tmp/sbcl-${SBCL_VERSION}-x86-64-linux" && sudo bash install.sh )
  hash -r
  log "installed $(sbcl --noinform --version)"
fi

if [ ! -f "$QUICKLISP_SETUP" ]; then
  log "installing Quicklisp"
  tmp_ql="$(mktemp -d)"
  curl -fL --retry 4 --retry-delay 4 \
    -o "$tmp_ql/quicklisp.lisp" \
    https://beta.quicklisp.org/quicklisp.lisp
  sbcl --noinform --non-interactive \
    --load "$tmp_ql/quicklisp.lisp" \
    --eval "(quicklisp-quickstart:install :path (merge-pathnames \"quicklisp/\" (user-homedir-pathname)))"
  rm -rf -- "$tmp_ql"
else
  log "Quicklisp already present at ${QUICKLISP_SETUP}"
fi

log "prefetching external Quicklisp dependencies"
sbcl --noinform --non-interactive \
  --load "$QUICKLISP_SETUP" \
  --eval '(ql:quickload (list "babel" "bordeaux-threads" "cl-jpeg" "cl-ppcre" "cl+ssl" "fiveam" "flexi-streams" "png-read" "sqlite" "trivial-gray-streams" "usocket") :silent t)' \
  --eval '(format t "~&cadr install: Quicklisp dependencies ready.~%")'

# build.lisp loads slynk/mrepl before dumping ./cadr. The admitted snapshot is
# Quicklisp 2026-01-01 sly-20260101-git (docs/dependency-audit.md).
QL_ROOT="$(CDPATH= cd -- "$(dirname -- "$QUICKLISP_SETUP")" && pwd)"
if ! sbcl --noinform --non-interactive --load "$QUICKLISP_SETUP" \
  --eval '(handler-case (asdf:find-system "slynk/mrepl") (error () (uiop:quit 1)))' \
  --eval '(uiop:quit 0)' >/dev/null 2>&1; then
  log "installing sly-20260101-git into Quicklisp local-projects (slynk/mrepl)"
  mkdir -p "$QL_ROOT/local-projects"
  tmp_sly="$(mktemp -d)"
  curl -fL --retry 4 --retry-delay 4 \
    -o "$tmp_sly/sly.tgz" \
    "https://beta.quicklisp.org/archive/sly/2026-01-01/sly-20260101-git.tgz"
  tar -xzf "$tmp_sly/sly.tgz" -C "$tmp_sly"
  rm -rf "$QL_ROOT/local-projects/sly-20260101-git"
  mv "$tmp_sly"/sly-20260101-git "$QL_ROOT/local-projects/"
  rm -rf -- "$tmp_sly"
fi

log "done. Build with: QUICKLISP_SETUP=\"${QUICKLISP_SETUP}\" ./build.sh"
