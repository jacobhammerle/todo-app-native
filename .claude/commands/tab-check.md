---
description: Screenshot every bottom tab on the live EAS simulator session
argument-hint: [session-id]
allowed-tools: Bash(bash scripts/tab-check-session.sh:*), Bash(bash scripts/tab-check-run.sh:*), Read
---

Validate the bottom navigation tabs on my live EAS cloud simulator session. Two scripts do all device work. Run them in order, read the screenshots, and report. Do not add, skip, or replace steps.

Optional session ID argument: `$ARGUMENTS`

1. Resolve the session: `bash scripts/tab-check-session.sh $ARGUMENTS`. It picks the ID above, else the ID in `.env.eas-simulator`, else the single in-progress session matching the platform and type that `scripts/tab-check-start.sh` recorded (default iOS + agent-device). It accepts only an `IN_PROGRESS` session with a reachable daemon (it waits up to 60 s for the daemon) and prints `session:`, `daemon:`, and `preview:` lines. If it exits non-zero, report its output verbatim and stop. Exit 4 means the daemon inside the session exited after 5 idle minutes; nothing in this command can revive it. Do NOT start a new session.
2. Drive the tabs: `bash scripts/tab-check-run.sh "<session scratchpad directory>/tab-shots"`. It relaunches the native app under test (installs it first if missing), presses Tasks, Done, Admin, verifies each screen by its marker text and selected state, saves `1-tasks.png`, `2-done.png`, `3-admin.png`, and checks the PNGs. If it exits non-zero, report its output verbatim and stop.
3. Read the 3 PNG files and confirm each shows its own screen with no blank view or error. On Admin, name the "Built by" and "EAS build ID" rows if they are visible.
4. Report: the session ID and name from step 1, the preview URL, one line per tab saying what it shows, and the 3 file paths.

If step 1 or 2 reports that the session is not an `agent-device` session, report that verbatim and stop; this command drives agent-device sessions only.

Rules: do NOT run `simulator:get`, `simulator:list`, `simulator:exec`, `agent-device`, or `npx` yourself. Do NOT load skills or take snapshots. Do NOT stop the simulator session — I keep it running for the demo.
