#!/usr/bin/env bash
# Shared pieces of the @expo-bot scripts. Source it; do not run it.
# Builds on scripts/agent/qa-lib.sh (evidence_tool, normalize_verdict,
# verdict_badge, load_argent_session, argent_device, wait_for_home) and
# scripts/expo-simulator/lib.sh (eas, app_id, use_simulator_token,
# start_session, wait_for_session, json_field, set_output, fmt_dur).
#
# Every bot post shares one layout: "## 🤖 <stage>", a bold Verdict or
# Status line, a short bullet list (PR, evidence, build), a thumbnail row,
# the full report folded away, and a "_Posted by_" footer. The verdict
# grammar, the thumbnails, the evidence site, and the PR comment shape
# come from the eas-simulator-evidence package (a devDependency).

# shellcheck disable=SC1091
. scripts/agent/qa-lib.sh

# repo_slug -> "owner/repo": GH_REPO when set, else package.json "repository".
repo_slug() { node scripts/agent/gh.mjs repo; }

# bot_handle -> the mention that drives the bot ("@expo-bot" by default).
# One spot to change it: "botHandle" in package.json. BOT_HANDLE in the
# environment overrides it (the bridge passes the parsed value along).
bot_handle() {
  if [ -n "${BOT_HANDLE:-}" ]; then printf '%s' "$BOT_HANDLE"; return; fi
  node -p "require('./package.json').botHandle || '@expo-bot'"
}

# expo_build_url <build-id> -> the build's page on expo.dev, from app.json.
expo_build_url() {
  local owner slug
  owner=$(node -p "require('./app.json').expo.owner")
  slug=$(node -p "require('./app.json').expo.slug")
  printf 'https://expo.dev/accounts/%s/projects/%s/builds/%s' "$owner" "$slug" "$1"
}

# require_env NAME "<how to fix>" -> exit 1 with the hint when NAME is empty.
require_env() {
  if [ -z "${!1:-}" ]; then
    echo "$1 is not set; $2"
    exit 1
  fi
}

# require_build "<what>" -> exit 1 when the upstream build job failed
# (BUILD_STATUS, a workflow job status) or BUILD_ID is empty. There is no
# repack here: the EAS Build is the whole app.
require_build() {
  if [ "${BUILD_STATUS:-}" = "failure" ]; then
    echo "Upstream build failed; no $1."
    exit 1
  fi
  if [ -z "${BUILD_ID:-}" ]; then
    echo "BUILD_ID is empty; no $1."
    exit 1
  fi
}

# use_agent_token [optional] -> the agent runner's credentials must be
# present (scripts/agent/run-agent.sh check knows the runner's variable
# names). With "optional", AGENT_AVAILABLE is exported as 1 or 0 instead
# of failing, so a caller can skip the agent step.
use_agent_token() {
  if [ "${1:-}" = "optional" ]; then
    if bash scripts/agent/run-agent.sh check optional; then
      export AGENT_AVAILABLE=1
    else
      export AGENT_AVAILABLE=0
      echo "No agent credentials: the agent step is skipped."
    fi
    return 0
  fi
  bash scripts/agent/run-agent.sh check
}

# evidence_thumbs <dir> <site_url> -> up to four screenshots from <dir>, in
# capture order, as linked thumbnails served by the evidence site. Prints
# nothing when there are no images.
evidence_thumbs() { evidence_tool thumbs "$1" "$2" --max 4; }

# cap_diff <file> -> keep a diff within the prompt budget (150 kB).
cap_diff() {
  if [ "$(wc -c < "$1")" -gt 150000 ]; then
    head -c 150000 "$1" > "$1.capped"
    printf '\n\n[diff truncated at 150 kB]\n' >> "$1.capped"
    mv "$1.capped" "$1"
  fi
}

# json_file_field <file> <field> -> one top-level string field of a JSON file.
json_file_field() {
  node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))[process.argv[2]] ?? '')" "$1" "$2"
}
