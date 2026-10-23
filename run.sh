#!/usr/bin/env bash
# run.sh - build, setup and run everything in one go.
#
#   ./run.sh                    build + setup + run (default)
#   ./run.sh build              fetch + build every application
#                               (tools/build.sh + bench/<app>/build.sh)
#   ./run.sh setup              generate every application's inputs
#                               (bench/<app>/setup.sh)
#   ./run.sh run [budget]       run every benchmark (bench/<app>/bench*.sh),
#                               budget default 20 s per benchmark
#
# Everything is idempotent: builds and setups skip work that is already
# done, so re-running is cheap. The build stage needs the LLVM/Clang
# toolchain on PATH (see README.md, Toolchain).

set -e

# print a step marker followed by the current date and time
step() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

REPO_ROOT=$(cd "$(dirname "$0")" && pwd)
STAGE="${1:-all}"
BUDGET="${2:-20}"

cd "$REPO_ROOT"

case "$STAGE" in
  all)          STAGES="build setup run" ;;
  build|setup|run) STAGES="$STAGE" ;;
  *) echo "usage: $0 [all|build|setup|run] [budget_seconds]" >&2; exit 1 ;;
esac

# --- toolchain sanity hint for the build stage --------------------------------
if [[ "$STAGES" == *build* ]]; then
  command -v clang  >/dev/null || echo "warning: clang not on PATH (see README.md, Toolchain)" >&2
  command -v ld.lld >/dev/null || echo "warning: ld.lld not on PATH; override LDFLAGS_BOLT if you don't have lld (see README.md)" >&2
fi

for stage in $STAGES; do
  case "$stage" in
    build)
      step "===== BUILD ====="
      bash tools/build.sh
      for app in "$REPO_ROOT"/bench/*/; do
        [ -f "$app/build.sh" ] || continue
        step "----- $(basename "$app") -----"
        bash "$app/build.sh"
      done
      ;;
    setup)
      step "===== SETUP ====="
      for app in "$REPO_ROOT"/bench/*/; do
        [ -f "$app/setup.sh" ] || continue
        step "----- $(basename "$app") -----"
        bash "$app/setup.sh"
      done
      ;;
    run)
      step "===== RUN ====="
      for app in "$REPO_ROOT"/bench/*/; do
        for bench in "$app"/bench*.sh; do
          [ -f "$bench" ] || continue
          step "----- $(basename "$app")/$(basename "$bench") -----"
          bash "$bench" "$BUDGET"
        done
      done
      ;;
  esac
done

step "===== done ====="
