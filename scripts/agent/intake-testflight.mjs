// Turns one TestFlight submission (screenshot feedback or crash report)
// into a GitHub issue and hands it to expo-bot-issue.yml.
//
//   1. fetch the submission with eas-cli (trigger id, else the newest)
//   2. download its screenshots so the triage agent can look at them
//   3. triage with an agent: bug vs feature, title, repro, guidance,
//      and whether an open testflight issue already reports it
//   4. file the issue (labels: testflight + bug|enhancement) — or, for a
//      duplicate, add the submission to the existing issue and stop
//   5. dispatch expo-bot-issue.yml with auto_verify=true
//
// Requires: FEEDBACK_KIND (screenshot|crash), GITHUB_TOKEN,
//           BASE_BRANCH, an EXPO_TOKEN that can read the ASC API key
// Optional: GH_REPO (owner/repo; default: package.json "repository"),
//           ASC_FEEDBACK_ID (trigger context; may arrive uninterpolated),
//           AGENT_AVAILABLE=1 from use_agent_token optional (agent triage)
// Writes /tmp/testflight/result.json:
//   { kind, issue_number, issue_url, run_url, duplicate }
// For a duplicate, issue_number/url name the existing issue, run_url is
// that issue's URL (nothing was dispatched), and duplicate is true.
// Logs go to stderr so stdout stays quiet for the calling shell.
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

// The mention that drives the bot: "botHandle" in package.json.
const BOT =
  process.env.BOT_HANDLE ||
  JSON.parse(readFileSync("package.json", "utf8")).botHandle ||
  "@expo-bot";

const WORK = "/tmp/testflight";
const SHOTS = `${WORK}/screenshots`;
rmSync(WORK, { recursive: true, force: true });
mkdirSync(SHOTS, { recursive: true });

const kind = process.env.FEEDBACK_KIND === "crash" ? "crash" : "screenshot";
const easCommand =
  kind === "crash" ? "testflight:crashes" : "testflight:feedback";
const baseBranch = process.env.BASE_BRANCH || "main";
const log = (...a) => console.error(...a);

const result = {
  kind: "bug",
  issue_number: "",
  issue_url: "",
  run_url: "",
  duplicate: false,
};
const writeResult = () =>
  writeFileSync(`${WORK}/result.json`, JSON.stringify(result, null, 2));
writeResult();

// ── 1. Fetch ──────────────────────────────────────────────────────────
// eas-cli prints progress to stderr with --json, but be defensive and
// start parsing at the first JSON bracket.
function parseJson(text) {
  const starts = ["{", "["].map((c) => text.indexOf(c)).filter((i) => i >= 0);
  if (!starts.length) throw new Error("no JSON in eas-cli output");
  return JSON.parse(text.slice(Math.min(...starts)));
}
// One pinned eas-cli, the same one scripts/expo-simulator/lib.sh's `eas`
// wrapper runs (intake-testflight.sh exports EAS_CLI_VERSION from it).
const EAS_CLI = `eas-cli@${process.env.EAS_CLI_VERSION || "25.3.0"}`;
function eas(args) {
  const out = execFileSync(
    "npx",
    ["--yes", EAS_CLI, ...args, "--json", "--non-interactive"],
    {
      encoding: "utf8",
      maxBuffer: 50 * 1024 * 1024,
      stdio: ["ignore", "pipe", "inherit"],
    },
  );
  return parseJson(out);
}
const fetchOne = (id) => eas([easCommand, id, "--type", kind]);
const fetchList = () => eas([easCommand, "--limit", "20"]);
const newest = (items) =>
  [...items].sort(
    (a, b) => new Date(b.createdDate ?? 0) - new Date(a.createdDate ?? 0),
  )[0];

// Seen in practice: EAS passed the trigger expression through as literal
// text; anything that still contains the context name is not an id.
let triggerId = process.env.ASC_FEEDBACK_ID ?? "";
if (!triggerId || triggerId.includes("app_store_connect")) triggerId = "";

// Single lookups return { feedback: {...} } or { crash: {...}, logText };
// lists return { feedback: [...] } or { crashes: [...] }.
let single = null;
if (triggerId) {
  try {
    single = fetchOne(triggerId);
    log(`Fetched ${kind} ${triggerId} from the trigger context.`);
  } catch {
    log(
      `Lookup of ${kind} ${triggerId} failed; falling back to the newest submission.`,
    );
  }
}
if (!single) {
  const list = fetchList();
  const items =
    list.feedback ?? list.crashes ?? (Array.isArray(list) ? list : []);
  if (!items.length) {
    log(`No TestFlight ${kind} submissions found; nothing to file.`);
    process.exit(1);
  }
  const pick = newest(items);
  if (kind === "crash") {
    // Only the single-id lookup carries the symbolicated log.
    try {
      single = fetchOne(pick.id);
    } catch {
      single = { crash: pick };
    }
  } else {
    single = { feedback: pick };
  }
}
const submission = single.feedback ?? single.crash ?? single;
const logText = single.logText ?? "";
writeFileSync(`${WORK}/submission.json`, JSON.stringify(single, null, 2));

// ── 2. Screenshots ────────────────────────────────────────────────────
const screenshotUrls = (submission.screenshots ?? [])
  .map((s) => (typeof s === "string" ? s : s.url))
  .filter(Boolean);
const shotPaths = [];
screenshotUrls.forEach((url, i) => {
  const ext = /\.(jpe?g)(\?|$)/i.test(url) ? "jpg" : "png";
  const path = `${SHOTS}/${i + 1}.${ext}`;
  try {
    execFileSync("curl", ["-fsSL", "--max-time", "60", "-o", path, url], {
      stdio: "inherit",
    });
    shotPaths.push(path);
  } catch {
    log(`Could not download screenshot ${i + 1}; the issue keeps the link.`);
  }
});

// ── 3. Triage ─────────────────────────────────────────────────────────
const tester =
  submission.testerEmail ?? submission.testerName ?? "unknown tester";
const buildVersion = submission.buildVersion ?? "unknown build";
const device = [
  submission.deviceModel,
  submission.osVersion && `iOS ${submission.osVersion}`,
]
  .filter(Boolean)
  .join(", ");
const comment = submission.comment ? String(submission.comment) : "";
// GitHub rejects bodies over 65536 characters; the useful frames are at
// the top of a crash log anyway.
const MAX_LOG = 30000;
const logExcerpt = logText.slice(0, MAX_LOG);

const facts = [
  `Kind of submission: ${kind}`,
  `Tester: ${tester}`,
  `Build: ${buildVersion}`,
  device ? `Device: ${device}` : null,
  submission.createdDate ? `Submitted: ${submission.createdDate}` : null,
  "",
  "Tester comment:",
  comment || "(no comment provided)",
  logExcerpt ? "" : null,
  logExcerpt ? "Crash log (first 12 kB):" : null,
  logExcerpt ? logExcerpt.slice(0, 12000) : null,
]
  .filter((l) => l !== null)
  .join("\n");

// Open issues from earlier submissions, so the triage agent can mark a
// repeat report instead of filing a near-identical issue for the same request.
let openIssues = [];
try {
  openIssues = JSON.parse(
    execFileSync(
      "node",
      ["scripts/agent/gh.mjs", "list-issues", "testflight", "30"],
      {
        encoding: "utf8",
        maxBuffer: 10 * 1024 * 1024,
      },
    ),
  );
} catch {
  log("Could not list open testflight issues; skipping the duplicate check.");
}
const openIssuesSection = openIssues.length
  ? `\n\n## Open TestFlight issues\n\n${openIssues
      .map((i) => {
        // The tester's own words are the "> " quote lines near the top.
        const quote = i.excerpt
          .split("\n")
          .filter((l) => l.startsWith("> "))
          .map((l) => l.slice(2))
          .join(" ")
          .slice(0, 240);
        return `- #${i.number} — ${i.title}${quote ? `\n  Tester: "${quote}"` : ""}`;
      })
      .join("\n")}\n`
  : "\n\n## Open TestFlight issues\n\n(none)\n";

let triage = null;
if (process.env.AGENT_AVAILABLE === "1") {
  const triageFile = "/tmp/testflight/triage.json";
  const promptFile = "/tmp/testflight/triage-prompt.md";
  const prompt =
    readFileSync(".eas/testflight-triage-prompt.md", "utf8") +
    openIssuesSection +
    `\n\n## Submission\n\n${facts}\n\nScreenshots saved locally (open them to look): ${
      shotPaths.join(", ") || "none"
    }\n\nWrite the JSON object to ${triageFile}.\n`;
  writeFileSync(promptFile, prompt);
  rmSync(triageFile, { force: true });
  log("Running the triage agent...");
  // The result file is the contract; run-agent.sh ignores the CLI's exit code.
  spawnSync(
    "bash",
    [
      "scripts/agent/run-agent.sh",
      "run",
      "--prompt-file",
      promptFile,
      "--profile",
      "triage",
      "--max-turns",
      "20",
      "--timeout",
      "6m",
    ],
    { encoding: "utf8", stdio: "inherit" },
  );
  try {
    const parsed = JSON.parse(readFileSync(triageFile, "utf8"));
    if (parsed && typeof parsed === "object" && parsed.title) triage = parsed;
  } catch {
    log("Triage agent wrote no usable JSON; filing a plain issue.");
  }
}

// Crashes are bugs by definition; the agent only shapes the wording.
const issueKind =
  kind === "crash" ? "bug" : triage?.kind === "feature" ? "feature" : "bug";
result.kind = issueKind;
writeResult();

// Only an issue from the list counts as a duplicate target; a made-up
// number would attach the submission to an unrelated thread.
const duplicateOf =
  openIssues.find((i) => i.number === Number(triage?.duplicate_of)) ?? null;

// ── 4. File the issue ─────────────────────────────────────────────────
const fallbackTitle =
  kind === "crash"
    ? `TestFlight crash: ${device || "unknown device"} on build ${buildVersion}`
    : `TestFlight feedback: ${(comment || "screenshot submitted").slice(0, 80)}`;
const title = String(triage?.title ?? fallbackTitle).slice(0, 120);

const shotLinks = screenshotUrls.map(
  (url, i) =>
    // An HTML img with a width keeps a portrait phone screenshot
    // thumbnail-sized; the link keeps click-to-open-full-size.
    `<a href="${url}"><img src="${url}" alt="screenshot-${i + 1}" width="260" /></a>`,
);
const expiry = submission.screenshots?.[0]?.expirationDate;
const steps = Array.isArray(triage?.repro_steps) ? triage.repro_steps : [];

const workflowName =
  kind === "crash" ? "testflight-crash" : "testflight-feedback";

// One metadata line, the tester's words as a quote, the screenshots, a
// two-line triage, the repro steps. Everything long (screenshot notes,
// crash log, raw payload) folds away.
// null marks a line that does not apply; '' is a deliberate blank line.
const oneLine = (s) => String(s).replace(/\s+/g, " ").trim();
const meta = [
  `**Tester** ${tester}`,
  `**Build** ${buildVersion}`,
  device ? `**Device** ${device}` : null,
  submission.createdDate
    ? `**Submitted** ${String(submission.createdDate).slice(0, 10)}`
    : null,
]
  .filter(Boolean)
  .join(" · ");
const triageLine = triage
  ? `**Triage** — ${issueKind === "feature" ? "feature request" : "bug"}${
      triage.screen ? ` · ${oneLine(triage.screen)} screen` : ""
    }`
  : null;
const body = [
  `## TestFlight ${kind === "crash" ? "crash" : "feedback"}`,
  "",
  meta,
  "",
  ...(comment
    ? comment.split("\n").map((l) => `> ${l}`)
    : ["> _No comment provided._"]),
  "",
  ...(shotLinks.length ? [shotLinks.join(" "), ""] : []),
  triageLine,
  triage?.summary ? oneLine(triage.summary) : null,
  steps.length ? "" : null,
  steps.length
    ? issueKind === "feature"
      ? "**Where it would live**"
      : "**Reproduction steps**"
    : null,
  ...steps.map((s, i) => `${i + 1}. ${s}`),
  "",
  // The log is the payload of a crash report, but it is long: keep it one
  // click away so the triage stays readable.
  logExcerpt ? "<details><summary>Crash log</summary>" : null,
  logExcerpt ? "" : null,
  logExcerpt ? "```" : null,
  logExcerpt ? logExcerpt : null,
  logExcerpt ? "```" : null,
  logText.length > MAX_LOG
    ? `_Log truncated to the first ${MAX_LOG} characters._`
    : null,
  logExcerpt ? "" : null,
  logExcerpt ? "</details>" : null,
  logExcerpt ? "" : null,
  "<details><summary>Screenshot notes and raw submission</summary>",
  "",
  triage?.screenshot_notes
    ? `**Screenshots** — ${oneLine(triage.screenshot_notes)}`
    : null,
  // Apple's screenshot URLs are presigned and expire.
  shotLinks.length && expiry ? `_Screenshot links expire ${expiry}._` : null,
  triage?.screenshot_notes || (shotLinks.length && expiry) ? "" : null,
  "```json",
  JSON.stringify(submission, null, 2),
  "```",
  "",
  "</details>",
  "",
  `_Filed by the ${workflowName} EAS workflow._`,
]
  .filter((line) => line !== null)
  .join("\n");

if (duplicateOf) {
  // Same shape as the other bot posts. The existing issue already has a
  // triage (and often a PR), so nothing is dispatched: a human can comment
  // @expo-bot there to re-run it.
  const dupBody = [
    "## 🤖 Duplicate TestFlight submission",
    "",
    `**Status:** 🔁 Another tester report of this ${issueKind === "feature" ? "request" : "bug"} — not filed as a new issue, and not re-triaged.`,
    "",
    meta,
    "",
    ...(comment
      ? comment.split("\n").map((l) => `> ${l}`)
      : ["> _No comment provided._"]),
    "",
    ...(shotLinks.length ? [shotLinks.join(" "), ""] : []),
    triage?.summary ? oneLine(triage.summary) : null,
    "",
    `_Posted by the ${workflowName} EAS workflow. Comment \`${BOT}\` here to triage again._`,
  ]
    .filter((line) => line !== null)
    .join("\n");
  execFileSync(
    "node",
    ["scripts/agent/gh.mjs", "comment", String(duplicateOf.number), dupBody],
    {
      encoding: "utf8",
    },
  );
  result.duplicate = true;
  result.kind = `duplicate of #${duplicateOf.number}`;
  result.issue_number = String(duplicateOf.number);
  result.issue_url = duplicateOf.url;
  result.run_url = duplicateOf.url;
  writeResult();
  log(
    `Duplicate of #${duplicateOf.number}; added the submission there and stopped: ${duplicateOf.url}`,
  );
  process.exit(0);
}

const labels = [
  "testflight",
  issueKind === "feature" ? "enhancement" : "bug",
].join(",");
const issueOut = execFileSync(
  "node",
  ["scripts/agent/gh.mjs", "create-issue", title, body, labels],
  { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 },
);
const issue = JSON.parse(issueOut.trim().split("\n").pop());
result.issue_number = String(issue.number);
result.issue_url = issue.url;
writeResult();
log(`Filed issue #${issue.number}: ${issue.url}`);

// ── 5. Dispatch expo-bot ──────────────────────────────────────────────
// This job runs on a default-branch checkout, so the uploaded project is
// the code the issue is validated against and the base for the fix PR.
const instruction = String(triage?.instruction ?? "")
  .replace(/\s+/g, " ")
  .trim();
const dispatch = spawnSync(
  "npx",
  [
    "--yes",
    EAS_CLI,
    "workflow:run",
    ".eas/workflows/expo-bot-issue.yml",
    "--input",
    `issue_number=${issue.number}`,
    "--input",
    `instruction=${instruction}`,
    "--input",
    `base_branch=${baseBranch}`,
    "--input",
    "auto_verify=true",
    "--non-interactive",
  ],
  { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 },
);
const dispatchText = `${dispatch.stdout ?? ""}\n${dispatch.stderr ?? ""}`;
process.stderr.write(dispatchText);
const runUrl = dispatchText.match(/https:\/\/expo\.dev[^\s]*/)?.[0] ?? "";

const commentOn = (text) =>
  execFileSync(
    "node",
    ["scripts/agent/gh.mjs", "comment", String(issue.number), text],
    {
      encoding: "utf8",
    },
  );

// One comment shape for every bot post: "## 🤖 <stage>", a bold status or
// verdict line, a short list, and a "_Posted by ..._" footer. The result
// comment from expo-bot-issue.yml uses the same "Agent triage" heading.
const feature = issueKind === "feature";
if (dispatch.status === 0 && runUrl) {
  result.run_url = runUrl;
  writeResult();
  commentOn(`## 🤖 Agent triage

**Status:** 🔄 ${
    feature
      ? "Confirming the capability is missing today"
      : "Replicating the report"
  } on an EAS cloud simulator — [follow the run](${runUrl})

_Verdict and evidence land here; ${
    feature ? "once confirmed, an implementation" : "if it replicates, a fix"
  } PR follows and is verified on a second simulator. Posted by the ${workflowName} EAS workflow._`);
} else {
  commentOn(`## 🤖 Agent triage

⚠️ **Could not start the triage workflow.** The dispatch error is in the ${workflowName} run logs on EAS. Comment \`${BOT}\` here to retry.

_Posted by the ${workflowName} EAS workflow._`);
  log("expo-bot-issue dispatch failed.");
}
