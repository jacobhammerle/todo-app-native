#!/usr/bin/env bash
# Runs the argent CLI without a global install. @swmansion/argent ships two
# bins, so plain `npx <pkg>` is ambiguous; -p + explicit bin is not.
# ARGENT_TOOLS_URL / ARGENT_AUTH_TOKEN in the environment route every tool
# call to the remote EAS simulator session's tool-server.
# The version is pinned. Seen in practice: @latest pointed at a tarball
# npm did not serve (404), which fails every QA lane. Override with
# ARGENT_VERSION when a newer release is verified.
# When ARGENT_CALL_LOG is set, every `argent run <tool>` appends the tool
# name to that file so callers can count device commands (QA swarm metrics).
if [ -n "${ARGENT_CALL_LOG:-}" ] && [ "${1:-}" = "run" ] && [ -n "${2:-}" ]; then
  printf '%s\n' "$2" >> "$ARGENT_CALL_LOG" 2>/dev/null || true
fi
exec npx --yes -p "@swmansion/argent@${ARGENT_VERSION:-0.23.0}" argent "$@"
