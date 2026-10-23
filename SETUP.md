# Quick setup

The same steps as the Expo repo's [SETUP.md](https://github.com/jacobhammerle/todo-app/blob/main/SETUP.md), minus what a native app does not need.

```bash
git clone https://github.com/jacobhammerle/todo-app-native.git && cd todo-app-native
npm install
npm install -g eas-cli
eas init
```

`eas init` links or creates the EAS project and writes `extra.eas.projectId` into [app.json](app.json). There is no `eas update:configure` step: the app has no JavaScript, so there is nothing to update over the air.

Set your own bundle identifier in two places: `PRODUCT_BUNDLE_IDENTIFIER` in [ios/project.yml](ios/project.yml) (then `npm run xcodegen`) and `ios.bundleIdentifier` in [app.json](app.json). The scripts read the second one. There is no `android.package`; this repo is iOS only.

Check that your account has Expo Simulators:

```bash
eas simulator:availability --json
```

Add [secrets](https://docs.expo.dev/eas/environment-variables/) to the project's `production` environment on expo.dev. One is required, two are optional:

- `CLAUDE_CODE_OAUTH_TOKEN`: the agent's credential, from [`claude setup-token`](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token). The QA swarm needs it; without it every lane stops at its first step with `Neither CLAUDE_CODE_OAUTH_TOKEN nor ANTHROPIC_API_KEY is set`. An `ANTHROPIC_API_KEY` works too, and the OAuth token wins when both are set.
- `EXPO_TOKEN_SIMULATOR`: optional, a [personal access token](https://docs.expo.dev/accounts/programmatic-access/). The workflow jobs start simulator sessions with the EAS worker's own token, and the runs on this project have worked that way. Add it if a run fails at `simulator:start` with "Not authorized"; the scripts use it first when it is set.
- `GITHUB_TOKEN`: optional, a [fine-grained token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) with pull-request write access, for the PR comment in `pr-live-preview.yml`.

```bash
eas env:create production --name CLAUDE_CODE_OAUTH_TOKEN --value <token> --visibility secret
eas env:create production --name EXPO_TOKEN_SIMULATOR --value <token> --visibility secret
eas env:create production --name GITHUB_TOKEN --value <token> --visibility secret
```

Two things from the Expo repo's setup are not needed here. There is no `APP_VARIANT` variable, because there are no fingerprint jobs. There are no GitHub repository secrets, because there is no `@expo-bot` bridge.

[Connect your GitHub repo](https://docs.expo.dev/eas/workflows/get-started/) under the project's settings on expo.dev, then push.

Try it from your machine first (an `eas login` is enough for these):

```bash
npm run build:simulator
npm run smoke -- --app build/SimpleTodo.app
```

Then on EAS:

```bash
eas workflow:run qa-swarm.yml
eas workflow:run simulator-smoke.yml
```

## TestFlight

The `testflight` profile in [eas.json](eas.json) is a store build of the same Xcode project. It needs Apple credentials (`eas credentials -p ios`) and the numeric App Store Connect app id in `submit.testflight.ios.ascAppId`. It has not been run from this repo yet, and the Expo repo's TestFlight feedback loop is not ported.

## Or hand it off to your agent

Paste this into your coding agent from inside the cloned repo:

```text
Set up this repo on my own EAS project by following SETUP.md step by step.
Run the commands yourself. When a step needs a secret (CLAUDE_CODE_OAUTH_TOKEN,
optionally EXPO_TOKEN_SIMULATOR and GITHUB_TOKEN), stop and ask me for it;
never make one up or print one back. After each step, verify it: `eas whoami`,
`eas simulator:availability`, `eas env:list --environment production`, and
`eas workflow:validate` on every file in .eas/workflows/. Finish by running
the QA swarm and telling me the per-lane results.
```
