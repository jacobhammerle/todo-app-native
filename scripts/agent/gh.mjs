// Minimal GitHub REST helper for EAS workflow jobs.
// Requires: GITHUB_TOKEN. The repository is GH_REPO (owner/repo) when set,
// else the "repository" field of package.json in the current directory.
// Usage:
//   node scripts/agent/gh.mjs repo                             (print owner/repo)
//   node scripts/agent/gh.mjs comment <number> "<body>"        (PR or issue)
//   node scripts/agent/gh.mjs get-pr <pr_number>
//   node scripts/agent/gh.mjs get-pr-diff <pr_number>
//   node scripts/agent/gh.mjs get-issue <issue_number>
//   node scripts/agent/gh.mjs create-pr "<title>" <head> <base> "<body>"

import { readFileSync } from "node:fs";

// package.json "repository" accepts a string ("github:owner/repo", a URL) or
// an object with a url; every form that names GitHub resolves here.
function repoFromPackageJson() {
  try {
    const pkg = JSON.parse(readFileSync("package.json", "utf8"));
    const url =
      typeof pkg.repository === "string"
        ? pkg.repository
        : (pkg.repository?.url ?? "");
    const match = url.match(
      /(?:github(?:\.com)?[/:])([^/\s]+\/[^/\s#]+?)(?:\.git)?(?:[#/].*)?$/,
    );
    return match ? match[1] : "";
  } catch {
    return "";
  }
}

const token = process.env.GITHUB_TOKEN;
const repo = process.env.GH_REPO || repoFromPackageJson();
const userAgent = "simple-todo-native-eas-workflows";

const [cmd, ...args] = process.argv.slice(2);

if (cmd === "repo") {
  if (!repo) {
    console.error(
      'No repository: set GH_REPO or package.json "repository" (github:owner/repo).',
    );
    process.exit(1);
  }
  console.log(repo);
  process.exit(0);
}
if (!token || !repo) {
  console.error(
    'GITHUB_TOKEN must be set, and the repository must come from GH_REPO or package.json "repository".',
  );
  process.exit(1);
}

async function api(method, path, body) {
  const res = await fetch(`https://api.github.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "Content-Type": "application/json",
      "User-Agent": userAgent,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    console.error(`GitHub API ${method} ${path} failed: ${res.status}`);
    console.error(JSON.stringify(json, null, 2));
    process.exit(1);
  }
  return json;
}

switch (cmd) {
  case "comment": {
    const [number, body] = args;
    const comment = await api(
      "POST",
      `/repos/${repo}/issues/${number}/comments`,
      { body },
    );
    console.log(JSON.stringify({ url: comment.html_url }));
    break;
  }
  case "get-pr": {
    const [number] = args;
    const pr = await api("GET", `/repos/${repo}/pulls/${number}`);
    console.log(
      JSON.stringify({
        title: pr.title,
        body: pr.body,
        branch: pr.head.ref,
        sha: pr.head.sha,
        headRepo: pr.head.repo?.full_name ?? "",
        state: pr.state,
      }),
    );
    break;
  }
  case "get-pr-diff": {
    // Raw unified diff on stdout (not JSON), via GitHub's diff media type.
    const [number] = args;
    const res = await fetch(
      `https://api.github.com/repos/${repo}/pulls/${number}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/vnd.github.diff",
          "User-Agent": userAgent,
        },
      },
    );
    if (!res.ok) {
      console.error(`GitHub API diff for PR #${number} failed: ${res.status}`);
      process.exit(1);
    }
    process.stdout.write(await res.text());
    break;
  }
  case "get-issue": {
    // Title, body, labels, and recent human comments (bot reports are
    // dropped so a re-triage does not read its own output as evidence).
    const [number] = args;
    const issue = await api("GET", `/repos/${repo}/issues/${number}`);
    const comments = await api(
      "GET",
      `/repos/${repo}/issues/${number}/comments?per_page=30`,
    );
    console.log(
      JSON.stringify({
        title: issue.title,
        body: issue.body,
        labels: (issue.labels ?? []).map((l) => l.name),
        comments: comments
          .filter((c) => !c.body?.startsWith("## 🤖"))
          .map((c) => ({ author: c.user?.login, body: c.body })),
      }),
    );
    break;
  }
  case "create-pr": {
    const [title, head, base, body] = args;
    const res = await fetch(`https://api.github.com/repos/${repo}/pulls`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": userAgent,
      },
      body: JSON.stringify({ title, head, base, body }),
    });
    const json = await res.json().catch(() => ({}));
    if (res.ok) {
      console.log(JSON.stringify({ url: json.html_url, number: json.number }));
      break;
    }
    // 422 usually means a PR for this head already exists (a re-run of the
    // same issue); return the open one instead of failing.
    if (res.status === 422) {
      const owner = repo.split("/")[0];
      const existing = await api(
        "GET",
        `/repos/${repo}/pulls?head=${owner}:${head}&state=open`,
      );
      if (existing.length) {
        console.log(
          JSON.stringify({
            url: existing[0].html_url,
            number: existing[0].number,
          }),
        );
        break;
      }
    }
    console.error(`GitHub API POST /pulls failed: ${res.status}`);
    console.error(JSON.stringify(json, null, 2));
    process.exit(1);
  }
  default:
    console.error(`Unknown command: ${cmd}`);
    process.exit(1);
}
