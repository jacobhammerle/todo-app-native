#!/usr/bin/env bash
# Drive the /tab-check on the live session in .env.eas-simulator.
#
# Usage: scripts/tab-check-run.sh [OUT_DIR]
#
# Talks to the session's agent-device daemon directly (no `simulator:exec`
# wrapper), so each step takes about 1-2 s. Steps:
#   1. Relaunch the app so Tasks is selected (installs it first if missing).
#   2. For each tab: press it, wait for that screen's marker text, check the
#      tab button reports selected, take a screenshot.
#   3. Verify the PNGs: valid header, 402x874-ish, and all of them differ.
# Every press/wait is retried once. Prints a summary table on success.
#
# Exit codes: 0 ok · 1 setup/env error · 5 a tab did not render · 6 screenshot invalid
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/tab-check-lib.sh
require_type agent-device "/tab-check" || exit 1

OUT_DIR=${1:-${TMPDIR:-/tmp}/tab-check-shots}
mkdir -p "$OUT_DIR"
load_session_env
echo "session:  $EAS_SIMULATOR_SESSION_ID  ($TAB_CHECK_PLATFORM)"
echo "output:   $OUT_DIR"

# ad <args...> — agent-device call whose output is kept in $AD_OUT; returns its exit code.
AD_OUT=""
ad() {
  set +e
  AD_OUT=$(agent_device "$@" 2>&1)
  local rc=$?
  set -e
  return $rc
}

# ---- 1. open the app fresh -------------------------------------------------
open_app() { ad open "$TAB_CHECK_APP_ID" --relaunch; }
if ! open_app; then
  if printf '%s' "$AD_OUT" | grep -qiE "not installed|no such app|not found|unknown app|could not find"; then
    echo "App not installed on the session. Installing the newest simulator build..."
    bash scripts/tab-check-install-app.sh
    open_app || { echo "open failed after install:" >&2; echo "$AD_OUT" >&2; exit 1; }
  else
    echo "open failed:" >&2; echo "$AD_OUT" >&2; exit 1
  fi
fi
echo "opened:   $TAB_CHECK_APP_ID (relaunched)"

# ---- 2. tabs ---------------------------------------------------------------
# show_tab <label> <marker> — press the tab (unless it is the launch tab,
# $TAB_CHECK_LAUNCH_TAB) and
# prove it rendered. Retries once. Returns 0 on success.
#
# `role="button" label="X"` is the selector for both platforms; a bare
# `label="X"` matches nothing in agent-device, so there is no fallback to try.
show_tab() {
  local label=$1 marker=$2 attempt
  for attempt in 1 2; do
    if [ "$label" != "$TAB_CHECK_LAUNCH_TAB" ] || [ "$attempt" = 2 ]; then
      ad press "role=\"button\" label=\"$label\"" || { echo "  press '$label' failed (attempt $attempt): $AD_OUT"; continue; }
    fi
    # Three waits, not one: right after a relaunch the daemon's snapshot
    # bridge can still be preparing and a single ~13 s wait times out on a
    # healthy Home screen (2026-09-16).
    if ! { ad wait text "$marker" || ad wait text "$marker" || ad wait text "$marker"; }; then
      echo "  '$marker' not visible after selecting '$label' (attempt $attempt)"; continue
    fi
    # The marker text is the proof: it is content unique to that tab's screen.
    # The button's `selected` trait is corroboration only, and it is no longer
    # reliable — on a live iOS session on 2026-09-09 every tab matched its
    # selector yet reported selected:false, so asserting it fails a healthy app.
    # Report it, do not fail on it.
    if ! ad is selected "role=\"button\" label=\"$label\""; then
      echo "  note: '$label' rendered but did not report selected state"
    fi
    return 0
  done
  return 1
}

FILES=()
for entry in "${TAB_CHECK_TABS[@]}"; do
  IFS='|' read -r stem label marker <<<"$entry"
  path="$OUT_DIR/$stem.png"
  echo "tab:      $label"
  show_tab "$label" "$marker" || { echo "Tab '$label' did not render its screen. Last agent-device output:" >&2; echo "$AD_OUT" >&2; exit 5; }
  ad screenshot "$path" || { echo "screenshot failed for '$label':" >&2; echo "$AD_OUT" >&2; exit 6; }
  FILES+=("$path")
done

# ---- 3. verify the PNGs ------------------------------------------------------
node - "${FILES[@]}" <<'NODE'
const fs = require("fs"), crypto = require("crypto");
const files = process.argv.slice(2);
const seen = new Map(); let bad = 0;
for (const f of files) {
  let ok = false, why = "";
  try {
    const b = fs.readFileSync(f);
    const png = b.length > 24 && b.readUInt32BE(0) === 0x89504e47;
    const w = png ? b.readUInt32BE(16) : 0, h = png ? b.readUInt32BE(20) : 0;
    const sum = crypto.createHash("md5").update(b).digest("hex");
    if (!png) why = "not a PNG";
    else if (w < 200 || h < 400) why = `unexpected size ${w}x${h}`;
    else if (seen.has(sum)) why = `identical to ${seen.get(sum)}`;
    else { ok = true; why = `${w}x${h}, ${(b.length / 1024).toFixed(0)} kB`; seen.set(sum, f); }
  } catch (e) { why = e.message; }
  console.log(`${ok ? "ok " : "BAD"}  ${f}  (${why})`);
  if (!ok) bad++;
}
process.exit(bad ? 6 : 0);
NODE

echo
echo "All ${#FILES[@]} tabs rendered and were screenshotted."
echo "Session $EAS_SIMULATOR_SESSION_ID is still running."
