---
description: Walk the native app's three tabs on an Expo Simulator, screenshot each, and report. Usage: /tab-check [build-id | archive-url | path/to/SimpleTodo.app]
---

Run the tab check on an Expo Simulator (a cloud iOS Simulator) and narrate each step for the person watching.

Argument: `$ARGUMENTS`. It is one of an EAS build id, an HTTPS URL to a `.tar.gz` of the app, or a local `.app` path. When it is empty, use the newest finished iOS simulator build:

```
npx --yes eas-cli@25.3.0 build:list --platform ios --simulator --status finished --limit 1 --json --non-interactive
```

Steps. Run each command with Bash, show its result in one line, and move on. Do not read project files; everything you need is here.

1. Say which source you are using and start the session. The script boots the device, installs and launches the app, and waits for the Tasks screen:
   - build id: `bash scripts/expo-simulator/smoke-test.sh --build-id <id> --out artifacts/tab-check --keep`
   - URL: `bash scripts/expo-simulator/smoke-test.sh --archive-url <url> --out artifacts/tab-check --keep`
   - local app: `bash scripts/expo-simulator/smoke-test.sh --app <path> --out artifacts/tab-check --keep`
   The script adds the task "Verified on an Expo Simulator", completes it, opens Done, opens Admin, and screenshots each step into `artifacts/tab-check/`. Its last lines are the verdict. The session stays up because of `--keep`.
2. Read `artifacts/tab-check/report.md` and show the verdict, the session id, and the browser preview link on their own lines, so the person can open the device in a browser.
3. Look at `artifacts/tab-check/01-tasks.png`, `04-done.png`, and `05-admin.png` with the Read tool. For each tab, say in one or two sentences what the screenshot shows: the summary card counts on Tasks, the completed list on Done, and the "Built by", "EAS profile", and "EAS build ID" rows on Admin.
4. Check one more thing live through the session (the dotenv `.env.eas-simulator` still points at it):
   `npx --yes eas-cli@25.3.0 simulator:exec npx --yes agent-device@0.21.31 open com.sunrisesolutions.simpletodo.native --platform ios --foreground`
   Confirm the tab bar lists Tasks, Done, and Admin in its snapshot.
5. Stop the session and clear the dotenv:
   `npx --yes eas-cli@25.3.0 simulator:stop --non-interactive && printf '# managed by eas-cli\n' > .env.eas-simulator`
6. Finish with a short recap: the verdict, the three screenshots by path, and the build that was tested. If any step failed, say which one and quote the error.

Rules: the session bills while it runs, so never skip step 5, even after a failure. Do not derive tap coordinates from screenshots; the script and agent-device use the accessibility tree.
