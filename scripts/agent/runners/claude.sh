#!/usr/bin/env bash
# Claude Code as the agent runner. Sourced by scripts/agent/run-agent.sh;
# do not run it directly.
#
# Credentials, as a secret in the production EAS environment:
#   CLAUDE_CODE_OAUTH_TOKEN   from `claude setup-token` (billed to a Claude subscription)
#   ANTHROPIC_API_KEY         an API key (billed to the API account)
# On a laptop with neither set, the local `claude` login is used.
# Default model: claude-sonnet-5 (AGENT_MODEL overrides it).

# runner_check [optional] -> exit 1 when no credential is available; with
# "optional", return 1 quietly instead.
runner_check() {
  if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    if [ -z "${EAS_BUILD_RUNNER:-}" ] && command -v claude >/dev/null 2>&1; then
      echo "No CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY; using the local claude login."
      return 0
    fi
    [ "${1:-}" = "optional" ] && return 1
    echo "Neither CLAUDE_CODE_OAUTH_TOKEN nor ANTHROPIC_API_KEY is set; add one as a secret."
    exit 1
  fi
  # Seen in practice: a rejected API key beside a valid OAuth token took every
  # QA lane down (401), because the CLI prefers the key. The OAuth token wins.
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then unset ANTHROPIC_API_KEY; fi
  return 0
}

# runner_command <prompt-file> <profile> <max-turns> -> sets AGENT_CMD (array)
# and AGENT_LOG_FORMATTER. The profile becomes an --allowedTools list.
runner_command() {
  local tools
  case "$2" in
    simulator) tools="Bash(bash scripts/agent/argent.sh*),Read,Glob,Grep,Write" ;;
    review|triage) tools="Read,Glob,Grep,Write" ;;
    *) echo "claude runner: unknown profile '$2'"; exit 1 ;;
  esac
  AGENT_CMD=(npx --yes @anthropic-ai/claude-code@latest
    -p "$(cat "$1")"
    --model "${AGENT_MODEL:-claude-sonnet-5}"
    --max-turns "$3"
    --output-format stream-json --verbose
    --allowedTools "$tools")
  AGENT_LOG_FORMATTER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claude-log-format.js"
}
