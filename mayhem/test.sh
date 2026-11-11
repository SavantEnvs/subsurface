#!/usr/bin/env bash
#
# mayhem/test.sh — RUN Subsurface's own CLI test suite (cli/tests/test_cli.py) against the subsurface-cli binary
# that mayhem/build.sh built with normal flags. Asserts known-input -> known-output values (dive counts, JSON
# fields, profile output, input-handling checks), so a no-op or exit(0) patch fails. Never builds.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

CLI="$SRC/build-tests/cli/cli/subsurface-cli"
[ -x "$CLI" ] || { echo "test runner missing: $CLI (mayhem/build.sh should have built it)" >&2; emit_ctrf "subsurface-cli test_cli.py" 0 1 0; exit 1; }

out=$(python3 cli/tests/test_cli.py --cli-path "$CLI" --test-data "$SRC/dives/SampleDivesV2.ssrf" 2>&1)
printf '%s\n' "$out"

res=$(printf '%s\n' "$out" | sed -n 's/^Test Results: \([0-9]*\) passed, \([0-9]*\) failed.*/\1 \2/p' | tail -1)
if [ -z "$res" ]; then
  echo "could not parse test_cli.py summary" >&2
  emit_ctrf "subsurface-cli test_cli.py" 0 1 0
  exit 1
fi
read -r passed failed <<<"$res"
[ "$passed" -gt 0 ] || failed=$((failed + 1))
emit_ctrf "subsurface-cli test_cli.py" "$passed" "$failed" 0
