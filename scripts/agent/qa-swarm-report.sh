#!/usr/bin/env bash
# Stitches the four QA swarm lanes into one report: per-lane verdict
# lines, the parallel-vs-serial wall clock, the fleet's simulator minutes,
# and a thumbnail row. Prints it and emits step outputs for the doc job.
# Requires, for lanes 1..4 (order: tasks, add, done, admin):
#   L<n>_STATUS, L<n>_VERDICT, L<n>_EVIDENCE, L<n>_METRICS, L<n>_SECONDS,
#   L<n>_SIM_MIN, L<n>_THUMBS
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/qa-lib.sh

LABELS=("iOS · Tasks" "iOS · Add" "iOS · Done" "iOS · Admin")
COUNT=${#LABELS[@]}
FLEET="${COUNT} iOS simulators"

# An uninterpolated "${{ ... }}" or an empty value both mean "not set".
clean() { case "$1" in *'${{'*) printf '' ;; *) printf '%s' "$1" ;; esac; }

PASSED=0; SERIAL=0; PARALLEL=0; TIMED=0; SIM_TOTAL=0; THUMBS=""
LANE_LINES=()

for n in $(seq 1 "$COUNT"); do
  label=${LABELS[$((n - 1))]}
  status=$(clean "$(eval "printf '%s' \"\${L${n}_STATUS:-}\"")")
  verdict=$(clean "$(eval "printf '%s' \"\${L${n}_VERDICT:-}\"")")
  evidence=$(clean "$(eval "printf '%s' \"\${L${n}_EVIDENCE:-}\"")")
  metrics=$(clean "$(eval "printf '%s' \"\${L${n}_METRICS:-}\"")")
  seconds=$(clean "$(eval "printf '%s' \"\${L${n}_SECONDS:-}\"")")
  sim_min=$(clean "$(eval "printf '%s' \"\${L${n}_SIM_MIN:-}\"")")
  thumbs=$(clean "$(eval "printf '%s' \"\${L${n}_THUMBS:-}\"")")

  [ -n "$verdict" ] && verdict=$(normalize_verdict "$verdict")
  if [ -z "$verdict" ]; then
    case "$status" in
      success) verdict="PASS: lane finished (no verdict text captured)" ;;
      *) verdict="FAIL: lane ended with status '${status:-unknown}' before writing a verdict" ;;
    esac
  fi
  case "$verdict" in PASS:*) PASSED=$((PASSED + 1)) ;; esac

  if [[ "$seconds" =~ ^[0-9]+$ ]]; then
    TIMED=$((TIMED + 1)); SERIAL=$((SERIAL + seconds))
    [ "$seconds" -gt "$PARALLEL" ] && PARALLEL=$seconds
  fi
  if [[ "$sim_min" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    SIM_TOTAL=$(awk "BEGIN { printf \"%.1f\", $SIM_TOTAL + $sim_min }")
  fi

  line="**${label}** — $(verdict_badge "$verdict")"
  [ -n "$metrics" ] && line="${line}  ·  ${metrics}"
  [ -n "$evidence" ] && line="${line}  ·  [Evidence](${evidence})"
  LANE_LINES+=("$line")
  [ -n "$thumbs" ] && THUMBS="${THUMBS:+${THUMBS} }${thumbs}"
done

if [ "$PASSED" -eq "$COUNT" ]; then
  HEADLINE="PASS: ${COUNT} of ${COUNT} lanes passed"
else
  HEADLINE="FAIL: $((COUNT - PASSED)) of ${COUNT} lanes failed"
fi

if [ "$TIMED" -gt 0 ] && [ "$PARALLEL" -gt 0 ]; then
  SPEEDUP=$(awk "BEGIN { printf \"%.1f\", $SERIAL / $PARALLEL }")
  TIMING="$(fmt_dur "$PARALLEL") wall clock in parallel vs $(fmt_dur "$SERIAL") one lane after another (${SPEEDUP}× faster)"
  [ "$TIMED" -lt "$COUNT" ] && TIMING="${TIMING}; ${TIMED} of ${COUNT} lanes reported timings"
else
  TIMING="no lane reported timings"
fi

echo "================ QA SWARM ================"
echo "$HEADLINE"
echo "${PASSED}/${COUNT} lanes passed · ${TIMING} · ${FLEET}, ${SIM_TOTAL} simulator-minutes total"
for l in "${LANE_LINES[@]}"; do echo "- $l"; done
echo "=========================================="

set_output headline "$HEADLINE"
set_output timing "$TIMING"
set_output fleet "${FLEET}, ${SIM_TOTAL} simulator-minutes"
set_output thumbs "$THUMBS"
for n in $(seq 1 "$COUNT"); do
  set_output "lane_${n}" "${LANE_LINES[$((n - 1))]}"
done
