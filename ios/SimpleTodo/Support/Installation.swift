import UIKit

/// What this installation is: bundle, version, build configuration, and the
/// build provenance that scripts/write-build-info.sh stamps into Info.plist.
/// The Tasks footer and the Admin tab show it, so a screenshot taken on an
/// Expo Simulator says exactly which build produced it.
struct Installation {
    let bundleIdentifier: String
    let version: String
    let build: String
    let configuration: String
    let environment: String
    let device: String
    let systemVersion: String
    /// "eas" when EAS Build produced the binary, "local" for xcodebuild.
    let source: String
    let easBuildId: String
    let easBuildProfile: String
    let gitCommit: String
    let builtAt: String

    static let current = Installation()

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        func string(_ key: String) -> String {
            (info[key] as? String) ?? ""
        }
        bundleIdentifier = bundle.bundleIdentifier ?? "unknown"
        version = string("CFBundleShortVersionString")
        build = string("CFBundleVersion")
        #if DEBUG
        configuration = "Debug"
        #else
        configuration = "Release"
        #endif
        #if targetEnvironment(simulator)
        environment = "iOS Simulator"
        #else
        environment = "Device"
        #endif
        device = UIDevice.current.model
        systemVersion = UIDevice.current.systemVersion
        source = string("BuildSource")
        easBuildId = string("EASBuildID")
        easBuildProfile = string("EASBuildProfile")
        gitCommit = string("GitCommit")
        builtAt = string("BuiltAt")
    }

    var builtBy: String {
        switch source {
        case "eas": return "EAS Build"
        case "local": return "Local xcodebuild"
        default: return "Unknown"
        }
    }

    var shortCommit: String {
        gitCommit.isEmpty ? "no commit" : String(gitCommit.prefix(7))
    }

    /// One line of facts for the Tasks footer, like the original app's
    /// "channel · runtime · update" line.
    var summaryLine: String {
        let origin = source == "eas" ? "eas \(easBuildProfile)" : source
        return "\(origin) · \(version) (\(build)) · \(shortCommit)"
    }
}
