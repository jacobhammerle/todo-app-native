# Simple Todo, native edition

Read https://docs.expo.dev/preview/simulators/works-with/native-ios-and-android/ before changing how the app reaches Expo Simulators, and the versioned EAS docs before writing workflow YAML.

- The app is a SwiftUI project in `ios/SimpleTodo/`: three tabs (`Views/TasksView.swift`, `DoneView.swift`, `AdminView.swift`), an in-memory store in `Model/TodoStore.swift`, and demo presets in `Model/Seed.swift`. There is no Expo SDK, no React Native, and no JavaScript; `package.json` and `app.json` are EAS tooling metadata only. Do not add them.
- `ios/SimpleTodo.xcodeproj` is generated from `ios/project.yml` with XcodeGen. Edit the spec, run `npm run xcodegen`, and commit both.
- Before you finish a change: `npm run build:simulator` must succeed, and `eas workflow:validate` must pass on every file in `.eas/workflows/` you touched. To see a UI change, run `npm run smoke -- --app build/SimpleTodo.app` (an Expo Simulator session; it bills while it runs and stops itself) or use the argent MCP server with a local simulator.
- Keep accessibility identifiers on controls the scripts target (`task-title-input`, `add-task`, `clear-history`, `preset-*`); `scripts/expo-simulator/smoke-test.sh` and the prompts in the README depend on them. Keep that script's expectations in step with the UI text and the default seed preset.
- `scripts/write-build-info.sh` is an Xcode run-script phase that stamps build provenance into the built Info.plist. Keep the keys it writes in sync with `Support/Installation.swift`.
- Use the argent MCP server for local simulator work and the Expo MCP server (`.mcp.json`) for EAS builds, workflows, and simulator sessions. Keep the app small; it exists to be built and run by EAS.
