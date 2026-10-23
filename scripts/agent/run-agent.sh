#!/usr/bin/env bash
# Runs one headless coding-agent session. This is the only place the
# scripts talk to an agent CLI. AGENT_RUNNER picks the CLI (default:
# claude); each runner is a small file in scripts/agent/runners/ that
# knows its own flags, credentials, and log format.
#
#   run-agent.sh check [optional]
#       exit 1 with a hint when the runner's credentials are missing
#   run-agent.sh run --prompt-file <f> --profile <p> [--max-turns <n>] [--timeout <d>]
#       run the agent on the prompt; never fails the caller (see Contract)
#
# Profiles say what the agent may do:
#   simulator  read and write files, run scripts/agent/argent.sh (drive a session)
#   review     read files, write the report
#   triage     read files, write the result
#
# Contract: the prompt names a file the agent must write (a verdict). The
# caller reads that file; the CLI's exit code and stdout are not the
# contract. --timeout is the hard backstop: a hung agent is killed, leaves
# no file, and the caller fails closed.
#
# AGENT_MODEL overrides the runner's default model. AGENT_DRY_RUN=1 prints
# the command instead of running it.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUNNER="${AGENT_RUNNER:-claude}"
RUNNER_FILE="$HERE/runners/${RUNNER}.sh"
if [ ! -f "$RUNNER_FILE" ]; then
  echo "run-agent.sh: unknown AGENT_RUNNER '${RUNNER}'; add scripts/agent/runners/${RUNNER}.sh"
  exit 1
fi
# shellcheck disable=SC1090
. "$RUNNER_FILE"   # defines runner_check and runner_command

COMMAND="${1:-}"
[ $# -gt 0 ] && shift
case "$COMMAND" in
  check)
    runner_check "${1:-}"
    ;;
  run)
    PROMPT_FILE=""; PROFILE=""; MAX_TURNS=50; TIMEOUT=10m
    while [ $# -gt 0 ]; do
      case "$1" in
        --prompt-file) PROMPT_FILE=$2; shift 2 ;;
        --profile) PROFILE=$2; shift 2 ;;
        --max-turns) MAX_TURNS=$2; shift 2 ;;
        --timeout) TIMEOUT=$2; shift 2 ;;
        *) echo "run-agent.sh: unknown option '$1'"; exit 1 ;;
      esac
    done
    if [ ! -s "$PROMPT_FILE" ]; then
      echo "run-agent.sh: prompt file '${PROMPT_FILE}' is missing or empty"
      exit 1
    fi
    case "$PROFILE" in
      simulator|review|triage) ;;
      *) echo "run-agent.sh: unknown profile '${PROFILE}'"; exit 1 ;;
    esac
    runner_check
    AGENT_CMD=(); AGENT_LOG_FORMATTER=""
    runner_command "$PROMPT_FILE" "$PROFILE" "$MAX_TURNS"
    # macOS has no `timeout`; the workers (Linux) do. `env` stands in so
    # the command array is never empty under `set -u`.
    TIMEOUT_CMD=(env)
    if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD=(timeout "$TIMEOUT"); fi
    if [ "${AGENT_DRY_RUN:-}" = "1" ]; then
      echo "--- would run (dry run) ---"
      printf '%q ' "${TIMEOUT_CMD[@]}" "${AGENT_CMD[@]}"; echo
      exit 0
    fi
    # The result file is the contract, so the CLI's exit code is ignored.
    if [ -n "$AGENT_LOG_FORMATTER" ]; then
      "${TIMEOUT_CMD[@]}" "${AGENT_CMD[@]}" | node "$AGENT_LOG_FORMATTER" || true
    else
      "${TIMEOUT_CMD[@]}" "${AGENT_CMD[@]}" || true
    fi
    ;;
  *)
    echo "usage: run-agent.sh check [optional] | run --prompt-file <f> --profile <p> [--max-turns <n>] [--timeout <d>]"
    exit 1
    ;;
esac
