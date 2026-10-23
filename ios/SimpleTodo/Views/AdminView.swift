import SwiftUI

struct AdminView: View {
    @Environment(TodoStore.self) private var store
    @State private var presetToLoad: SeedPreset?

    private let installation = Installation.current

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Bundle ID") {
                        Text(installation.bundleIdentifier)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    LabeledContent("Version", value: "\(installation.version) (\(installation.build))")
                    LabeledContent("Configuration", value: installation.configuration)
                    LabeledContent("Environment", value: installation.environment)
                    LabeledContent("Device", value: "\(installation.device) · iOS \(installation.systemVersion)")
                } header: {
                    Text("This installation")
                } footer: {
                    Text("A native SwiftUI app with no React Native and no JavaScript. EAS Build compiles it and Expo Simulators runs it, the same as the Expo version of this app.")
                }

                Section {
                    LabeledContent("Built by", value: installation.builtBy)
                    if installation.source == "eas" {
                        LabeledContent("EAS profile") {
                            Text(installation.easBuildProfile)
                                .font(.subheadline.monospaced())
                        }
                        LabeledContent("EAS build ID") {
                            Text(installation.easBuildId)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent("Commit") {
                        Text(installation.shortCommit)
                            .font(.subheadline.monospaced())
                    }
                    LabeledContent("Built at", value: installation.builtAt.isEmpty ? "unknown" : installation.builtAt)
                } header: {
                    Text("Build provenance")
                } footer: {
                    Text("scripts/write-build-info.sh stamps these values into Info.plist during every xcodebuild. On EAS Build they come from EAS_BUILD_ID, EAS_BUILD_PROFILE, and EAS_BUILD_GIT_COMMIT_HASH, so a screenshot from an Expo Simulator says exactly which build it shows.")
                }

                demoDataSection
            }
            .navigationTitle("Admin")
            .alert(
                "Load \"\(presetToLoad?.label ?? "")\"?",
                isPresented: Binding(
                    get: { presetToLoad != nil },
                    set: { if !$0 { presetToLoad = nil } }
                ),
                presenting: presetToLoad
            ) { preset in
                Button("Cancel", role: .cancel) {}
                Button("Load") { store.reset(to: preset) }
            } message: { preset in
                let count = preset.tasks.count
                Text("This replaces every task with the \(count) \(taskWord(count)) in this preset.")
            }
        }
    }

    /// Loads a seed preset from `Seed.swift` into the task list.
    private var demoDataSection: some View {
        Section {
            ForEach(SeedPreset.allCases) { preset in
                let isLoaded = preset == store.loadedPreset
                let count = preset.tasks.count
                Button {
                    presetToLoad = preset
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.label)
                                .foregroundStyle(.primary)
                            Text("\(count) \(taskWord(count))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isLoaded {
                            Text("Loaded")
                                .fontWeight(.semibold)
                                .foregroundStyle(Brand.success)
                        } else {
                            Text("Load")
                                .foregroundStyle(Brand.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(preset.label)
                .accessibilityValue(isLoaded ? "Loaded" : "\(count) \(taskWord(count))")
                .accessibilityIdentifier("preset-\(preset.rawValue)")
            }
            FormAction(label: "Reset demo data") {
                presetToLoad = store.loadedPreset
            }
            .accessibilityIdentifier("reset-demo-data")
        } header: {
            Text("Demo data")
        } footer: {
            Text("Presets live in ios/SimpleTodo/Model/Seed.swift. Edit that file to change the demo tasks, or load a preset here to reset the list mid-demo.")
        }
    }
}
