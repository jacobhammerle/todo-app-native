# Quick setup

```bash
git clone https://github.com/jacobhammerle/todo-app-native.git && cd todo-app-native
npm install
npm install -g eas-cli
eas init
```

`eas init` links or creates the EAS project and writes `extra.eas.projectId` into [app.json](app.json). Set your own bundle identifier in two places: `PRODUCT_BUNDLE_IDENTIFIER` in [ios/project.yml](ios/project.yml) (then `npm run xcodegen`) and `ios.bundleIdentifier` in [app.json](app.json). The scripts read the second one.

Check that your account has Expo Simulators:

```bash
eas simulator:availability --json
```

Add one secret to the project's `production` environment on expo.dev. The EAS worker's own token cannot create simulator sessions, so the workflow jobs use a [personal access token](https://docs.expo.dev/accounts/programmatic-access/) instead:

```bash
eas env:create production --name EXPO_TOKEN_SIMULATOR --value <token> --visibility secret
```

Optional, for the PR comment in `pr-live-preview.yml`: a GitHub [fine-grained token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) with pull-request write access.

```bash
eas env:create production --name GITHUB_TOKEN --value <token> --visibility secret
```

Try it from your machine first (an `eas login` is enough for these):

```bash
npm run build:simulator
npm run smoke -- --app build/SimpleTodo.app
```

Then on EAS:

```bash
eas build --platform ios --profile simulator
eas workflow:run simulator-smoke.yml
```

[Connect your GitHub repo](https://docs.expo.dev/eas/workflows/get-started/) under the project's settings on expo.dev to run the workflows on push and pull request.

## TestFlight

The `testflight` profile in [eas.json](eas.json) is a store build of the same Xcode project. It needs Apple credentials (`eas credentials -p ios`) and the numeric App Store Connect app id in `submit.testflight.ios.ascAppId`. It has not been run from this repo yet.

## Or hand it off to your agent

Paste this into your coding agent from inside the cloned repo:

```text
Set up this repo on my own EAS project by following SETUP.md step by step.
Run the commands yourself. When a step needs a secret (EXPO_TOKEN_SIMULATOR,
optionally GITHUB_TOKEN), stop and ask me for it; never make one up or print
one back. After each step, verify it: `eas whoami`, `eas simulator:availability`,
`eas env:list --environment production`, and `eas workflow:validate` on every
file in .eas/workflows/. Finish by running the smoke test and telling me the
verdict and where the screenshots are.
```
