import SwiftUI
import UIKit

struct GameDetailView: View {
    @Environment(GameLibrary.self) private var library
    @Environment(EmulatorProcess.self) private var emulator
    @Environment(\.dismiss) private var dismiss

    let game: Game

    @AppStorage("gow3LowLoadProfileEnabled") private var gow3LowLoadProfileEnabled = true
    @State private var showRemoveConfirmation = false
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                if let iconPath = game.iconPath, let uiImage = UIImage(contentsOfFile: iconPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.background.secondary)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 180)
                        .overlay(
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.title3.bold())

                HStack(spacing: 8) {
                    if let titleId = game.titleId {
                        Text(titleId)
                            .font(.caption.monospaced().bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Color.accentColor)
                    }

                    if let appVersion = game.appVersion {
                        Text("v\(appVersion)")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)
                    }
                }

                if let playTime = PlayTimeStore.formatted(forTitleId: game.titleId) {
                    Label(playTime, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isGodOfWarIIIRemastered {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $gow3LowLoadProfileEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("GOW III compatibility profile")
                                .font(.subheadline.weight(.semibold))
                            Text("Starts at 720p; starts at 540p if iPadOS reports serious heat. Uses upscaling and pipeline caching.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.orange)

                    Text(!gow3LowLoadProfileEnabled
                         ? "Profile is off. The previous per-game settings are restored when you launch."
                         : (isValidated720pBuild
                            ? "The known 720p game patch will be enabled for this title/version."
                            : "The 720p game patch is only enabled for CUSA01623 or CUSA01715 version 01.02; this build will receive the general profile only."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(game.absolutePkgPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                } icon: {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                }

                if !game.isAvailable {
                    Label("File not found on disk", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let launchError {
                Text(launchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            VStack(spacing: 10) {
                if emulator.isBusy && emulator.runningGameName == game.name {
                    Button(role: .destructive) {
                        emulator.stop()
                    } label: {
                        Label(
                            emulator.state == .extracting ? "Cancel Extraction" : "Stop Game",
                            systemImage: "stop.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        launch()
                    } label: {
                        Label("Launch Game", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!game.isAvailable || emulator.isBusy)
                }

                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(.background.secondary)
        .confirmationDialog(
            "Remove \"\(game.name)\" from your library?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                library.removeGame(game)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the imported copy of the .pkg file from the app.")
        }
    }

    private var isGodOfWarIIIRemastered: Bool {
        let id = game.titleId?.uppercased() ?? ""
        if ["CUSA01623", "CUSA01715", "CUSA01740"].contains(id) {
            return true
        }
        let normalized = game.name.lowercased()
        return (normalized.contains("god of war iii") || normalized.contains("god of war 3"))
            && normalized.contains("remastered")
    }

    private var isValidated720pBuild: Bool {
        guard let titleId = game.titleId?.uppercased(), let appVersion = game.appVersion else {
            return false
        }
        return ["CUSA01623", "CUSA01715"].contains(titleId) && appVersion == "01.02"
    }

    private func launch() {
        launchError = nil

        if isGodOfWarIIIRemastered && ProcessInfo.processInfo.thermalState == .critical {
            launchError = "iPadOS reports critical thermal pressure. Let the iPad cool before launching GOW III."
            return
        }

        if isGodOfWarIIIRemastered {
            guard let titleId = game.titleId else {
                launchError = "The game title ID could not be read, so the GOW III profile was not applied."
                return
            }

            do {
                if gow3LowLoadProfileEnabled {
                    try GOW3LowLoadProfile.apply(titleId: titleId, appVersion: game.appVersion)
                } else {
                    try GOW3LowLoadProfile.restore(titleId: titleId)
                }
            } catch {
                launchError = "Couldn't prepare the GOW III profile: \(error.localizedDescription)"
                return
            }
        }

        emulator.launch(pkgPath: game.absolutePkgPath, gameName: game.name)
    }
}

/// Creates a reversible per-game profile and (only for the versions checked by the community
/// patch) installs a 720p executable patch in shadPS4's existing auto-patch folder.
private enum GOW3LowLoadProfile {
    private static let fileManager = FileManager.default

    private static var applicationSupport: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static var configDirectory: URL {
        applicationSupport
            .appendingPathComponent("shadPS4", isDirectory: true)
            .appendingPathComponent("custom_configs", isDirectory: true)
    }

    private static var patchRepository: URL {
        applicationSupport
            .appendingPathComponent("shadPS4", isDirectory: true)
            .appendingPathComponent("patches", isDirectory: true)
            .appendingPathComponent("aether-gow3-optimized", isDirectory: true)
    }

    private static func paths(titleId: String) throws -> (config: URL, backup: URL, noPrevious: URL) {
        guard titleId.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw NSError(
                domain: "GOW3LowLoadProfile",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The game title ID is missing or invalid."]
            )
        }
        return (
            configDirectory.appendingPathComponent("\(titleId).json"),
            configDirectory.appendingPathComponent("\(titleId).gow3-backup"),
            configDirectory.appendingPathComponent("\(titleId).gow3-no-previous-config")
        )
    }

    static func apply(titleId: String, appVersion: String?) throws {
        let urls = try paths(titleId: titleId)
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        // Preserve a pre-existing per-game config once, so disabling this profile restores it.
        if !fileManager.fileExists(atPath: urls.backup.path)
            && !fileManager.fileExists(atPath: urls.noPrevious.path) {
            if fileManager.fileExists(atPath: urls.config.path) {
                try fileManager.copyItem(at: urls.config, to: urls.backup)
            } else {
                try Data("{}".utf8).write(to: urls.noPrevious, options: .atomic)
            }
        }

        var root: [String: Any] = [:]
        if fileManager.fileExists(atPath: urls.config.path) {
            let data = try Data(contentsOf: urls.config)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(
                    domain: "GOW3LowLoadProfile",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The existing per-game config isn't a JSON object."]
                )
            }
            root = object
        }

        // The community GOW3 fix reports success with 2048 MB of additional emulated DMEM;
        // one tester needed more. This setting is emulator memory, not a direct iPad RAM lock.
        var general = root["General"] as? [String: Any] ?? [:]
        general["extra_dmem_in_mbytes"] = 2048
        root["General"] = general

        var gpu = root["GPU"] as? [String: Any] ?? [:]
        // Use the lower 540p starting resolution when iPadOS already reports serious thermal
        // pressure. This is sampled at launch; the emulator cannot change the running game's
        // render targets dynamically, so it is a conservative startup choice rather than a
        // guarantee against heat-related throttling later in the session.
        let launchResolution: (width: Int, height: Int)
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            launchResolution = (960, 540)
        case .nominal, .fair, .unknown:
            launchResolution = (1280, 720)
        @unknown default:
            launchResolution = (1280, 720)
        }
        gpu["internal_screen_width"] = launchResolution.width
        gpu["internal_screen_height"] = launchResolution.height
        gpu["vblank_frequency"] = 60
        gpu["fsr_enabled"] = true
        gpu["rcas_enabled"] = true
        gpu["hdr_allowed"] = false
        gpu["dump_shaders"] = false
        gpu["readbacks_mode"] = 0
        gpu["direct_memory_access_enabled"] = false
        root["GPU"] = gpu

        var vulkan = root["Vulkan"] as? [String: Any] ?? [:]
        vulkan["pipeline_cache_enabled"] = true
        vulkan["pipeline_cache_archived"] = false
        root["Vulkan"] = vulkan

        // Only apply binary offsets for the two title IDs and exact app version used to verify
        // the public 720p patch. Other builds still get the configurable memory/render profile.
        try install720pPatchIfValidated(titleId: titleId, appVersion: appVersion)

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: urls.config, options: .atomic)
    }

    private static func install720pPatchIfValidated(titleId: String, appVersion: String?) throws {
        let id = titleId.uppercased()
        let supported = ["CUSA01623", "CUSA01715"].contains(id) && appVersion == "01.02"
        if !supported {
            if fileManager.fileExists(atPath: patchRepository.path) {
                try fileManager.removeItem(at: patchRepository)
            }
            return
        }

        try fileManager.createDirectory(at: patchRepository, withIntermediateDirectories: true)
        let index = #"{"God_of_War_III_Remastered.xml":["CUSA01623","CUSA01715"]}"#
        try Data(index.utf8).write(
            to: patchRepository.appendingPathComponent("files.json"), options: .atomic
        )
        try Data(Self.resolutionPatchXML.utf8).write(
            to: patchRepository.appendingPathComponent("God_of_War_III_Remastered.xml"), options: .atomic
        )
    }

    static func restore(titleId: String) throws {
        let urls = try paths(titleId: titleId)
        if fileManager.fileExists(atPath: urls.backup.path) {
            if fileManager.fileExists(atPath: urls.config.path) {
                try fileManager.removeItem(at: urls.config)
            }
            try fileManager.moveItem(at: urls.backup, to: urls.config)
        } else if fileManager.fileExists(atPath: urls.noPrevious.path) {
            if fileManager.fileExists(atPath: urls.config.path) {
                try fileManager.removeItem(at: urls.config)
            }
            try fileManager.removeItem(at: urls.noPrevious)
        }

        if fileManager.fileExists(atPath: patchRepository.path) {
            try fileManager.removeItem(at: patchRepository)
        }
    }

    // Community patch PR #145, tested for CUSA01623 v01.02; it lists CUSA01715 as a supported
    // title ID too. The exact app-version guard above deliberately prevents applying these byte
    // offsets to other builds, where code addresses may differ.
    private static let resolutionPatchXML = """
    <?xml version="1.0"?>
    <Patch>
        <TitleID>
            <ID>CUSA01623</ID>
            <ID>CUSA01715</ID>
        </TitleID>
        <Metadata Title="God of War III Remastered" Name="Resolution Patch (1280x720)" Note="Forces the base PS4 internal render target hierarchy and output resolution to 1280x720. Community patch; build-gated to CUSA01623/CUSA01715 version 01.02." Author="AetherPS4 GOW3 profile (based on community patch by kvicken)" PatchVer="1.1" AppVer="01.02" AppElf="eboot.bin" isEnabled="true">
            <PatchList>
                <Line Type="bytes" Address="0x005f0c5b" Value="00050000"/>
                <Line Type="bytes" Address="0x005f0c63" Value="d0020000"/>
                <Line Type="bytes" Address="0x005f0c6c" Value="0005"/>
                <Line Type="bytes" Address="0x005f0c73" Value="d002"/>
                <Line Type="bytes" Address="0x005643e3" Value="d0020000"/>
                <Line Type="bytes" Address="0x005643f0" Value="00050000"/>
                <Line Type="bytes" Address="0x005ff889" Value="00050000"/>
                <Line Type="bytes" Address="0x005ff88f" Value="d0020000"/>
                <Line Type="bytes" Address="0x007c46b4" Value="00050000"/>
                <Line Type="bytes" Address="0x007c46b8" Value="d0020000"/>
            </PatchList>
        </Metadata>
    </Patch>
    """
}
