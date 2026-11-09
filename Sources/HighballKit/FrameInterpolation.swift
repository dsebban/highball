import Foundation

/// One program's DLSS Frame Generation settings on D3DMetal 4: D3DMetal's MetalFX frame interpolator
/// stands in for NVIDIA's DLSS-G when a game asks Streamline for it. Kept per program (a pin), never
/// for the whole environment: the presented-frame cap and the working folder that make it work for
/// one game are wrong for another.
///
/// What D3DMetal 4.0 beta 3 does, measured on an M6 with macOS 27.2 (2026-11-09):
/// - It reports `FrameGeneration.Available` to Streamline only when `nvngx_dlssg.dll` sits beneath the
///   executable's folder or the process's working folder (that folder, then up to 12 levels below,
///   at most 50,000 entries). Hellblade II ships it under `Engine/Plugins/…` beside its `Hellblade2`
///   folder, so started from its executable's folder the game hides its Frame Generation row; started
///   in the game's root folder it offers it. Galactic Racer has it beside its executable.
/// - `D3DM_MAX_FPS=N` holds every presented picture, generated ones included, for at least 1/N s: with
///   2x interpolation a cap of 60 means about 30 rendered frames, and a cap of 30 means 15.
/// - The Metal 4 path (`D3DM_MTL4`) is a separate switch; the tested setups keep it off.
/// - Streamline then asks Wine for D3DKMTQueryAdapterInfo type 70 (WDDM 2.7 caps: GPU scheduling).
///   CrossOver's win32u answers it (scheduling supported and on) only when `CX_ACTIVE_GRAPHICS_BACKEND`
///   is `d3dmetal`, a variable CrossOver sets for each process to the backend it chose (its
///   `cxcompatdb.so`, `set_graphics_backend`) and Highball's engine, which ships no `cxcompatdb.so`,
///   never sets. Unanswered, Streamline logs "Disabling DLSS-G since it is not supported on
///   current hardware" and Hellblade II hides Frame Generation; with the variable set, the same launch
///   offers it and interpolates (measured 2026-11-09). The profile sets it. The engine's only other
///   reader of the variable picks a Vulkan library when it is `wined3d`.
///
/// The game's own Frame Generation setting is still the player's to turn on, in its menu, and
/// Streamline still makes checks of its own: ready means D3DMetal's and Wine's parts only.
public struct FrameInterpolationProfile: Codable, Sendable, Hashable {
    /// D3DM_MAX_FPS: the cap on presented pictures, generated ones included. nil leaves the
    /// environment's cap.
    public var presentedCap: Int?
    /// D3DM_MTL4: nil keeps the engine's default, false turns the Metal 4 path off.
    public var metal4: Bool?
    /// The folder Wine starts the program in: relative to the executable's folder (`../../..`) or
    /// absolute. nil keeps the executable's folder.
    public var workingDirectory: String?

    public init(presentedCap: Int? = nil, metal4: Bool? = nil, workingDirectory: String? = nil) {
        self.presentedCap = presentedCap; self.metal4 = metal4; self.workingDirectory = workingDirectory
    }

    /// The variables this profile sets on a launch.
    public var environment: [String: String] {
        var env = ["CX_ACTIVE_GRAPHICS_BACKEND": "d3dmetal"]
        if let presentedCap { env["D3DM_MAX_FPS"] = String(presentedCap) }
        if let metal4 { env["D3DM_MTL4"] = metal4 ? "1" : "0" }
        return env
    }

    /// The folder a launch of `executable` starts in.
    public func workingDirectory(for executable: URL) -> URL {
        let exeDir = executable.deletingLastPathComponent()
        guard let dir = workingDirectory, !dir.isEmpty else { return exeDir }
        if dir.hasPrefix("/") { return URL(fileURLWithPath: dir, isDirectory: true).standardizedFileURL }
        return exeDir.appending(path: dir, directoryHint: .isDirectory).standardizedFileURL
    }

    /// Whether frame interpolation can come up for this launch, and why not when it cannot.
    public enum Status: Equatable, Sendable {
        /// D3DMetal will report frame generation as available to Streamline.
        case ready(d3dmetal: String, marker: URL)
        case unavailable(String)
    }

    /// The launch settings a pin with this profile gets: the variables and the working folder when
    /// the status is ready; otherwise none of them, so the program runs as it would without a profile.
    public struct Launch: Sendable {
        public let environment: [String: String]
        public let workingDirectory: URL
        public let status: Status
        /// One line for the launch log's header.
        public var note: String {
            switch status {
            case let .ready(version, marker):
                let vars = environment.keys.sorted().map { "\($0)=\(environment[$0]!)" }.joined(separator: " ")
                return "frame interpolation profile applied (D3DMetal \(version) reports frame generation available; the game's setting and Streamline still decide): \(marker.lastPathComponent) at \(marker.path), working folder \(workingDirectory.path)\(vars.isEmpty ? "" : ", " + vars)"
            case let .unavailable(why):
                return "frame interpolation profile not applied: \(why)"
            }
        }
    }

    /// Decides a launch: `renderer` is the mode the program gets, after every per-program override.
    public func launch(executable: URL, renderer: Renderer, engine: InstalledEngine, bottle: Bottle) -> Launch {
        let cwd = workingDirectory(for: executable)
        let status = Self.status(executable: executable, workingDirectory: cwd, renderer: renderer, engine: engine, bottle: bottle)
        if case .ready = status { return Launch(environment: environment, workingDirectory: cwd, status: status) }
        return Launch(environment: [:], workingDirectory: executable.deletingLastPathComponent(), status: status)
    }

    public static func status(executable: URL, workingDirectory: URL, renderer: Renderer, engine: InstalledEngine, bottle: Bottle) -> Status {
        guard renderer == .d3dmetal else { return .unavailable("the program runs on \(Renderer.displayName(renderer)), and frame interpolation needs D3DMetal 4") }
        guard let dir = engine.rendererDir("d3dmetal") else {
            return .unavailable(Renderer.d3dmetal.unavailableReason(in: engine) ?? "engine \(engine.id) has no D3DMetal")
        }
        guard let version = d3dmetalVersion(in: dir) else { return .unavailable("the D3DMetal in \(dir.path) has no readable version") }
        guard let major = Int(version.prefix { $0.isNumber }), major >= 4 else {
            return .unavailable("engine \(engine.id) serves D3DMetal \(version); frame interpolation needs D3DMetal 4")
        }
        guard bottle.settings.dlssEnabled, bottle.supportsDLSS(engine: engine, renderer: .d3dmetal) else {
            return .unavailable("DLSS (MetalFX) is off for this environment or its D3DMetal has no MetalFX bridge")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            return .unavailable("the working folder \(workingDirectory.path) is not there")
        }
        for root in [executable.deletingLastPathComponent(), workingDirectory] {
            if let marker = findMarker(under: root) { return .ready(d3dmetal: version, marker: marker) }
        }
        return .unavailable("\(markerName) is not within \(maxDepth) levels of \(executable.deletingLastPathComponent().path) or \(workingDirectory.path); set the profile's working folder to the game's root")
    }

    /// CFBundleShortVersionString of the overlay's D3DMetal.framework ("4.0b3").
    public static func d3dmetalVersion(in rendererDir: URL) -> String? {
        let plist = rendererDir.appending(path: "external/D3DMetal.framework/Resources/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    public static let markerName = "nvngx_dlssg.dll"
    /// D3DMetal 4.0 beta 3's search bounds below each folder.
    public static let maxDepth = 12
    public static let maxEntries = 50_000

    /// The marker D3DMetal would find under `root`: the folder itself first, then breadth-first down
    /// to `maxDepth` levels, giving up after `maxEntries` entries. Case-insensitive, as Windows names are.
    public static func findMarker(under root: URL) -> URL? {
        let fm = FileManager.default
        var level = [root], seen = 0
        for depth in 0...maxDepth {
            var next: [URL] = []
            for dir in level {
                guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    seen += 1
                    if seen > maxEntries { return nil }
                    let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if values?.isDirectory == true, values?.isSymbolicLink != true { next.append(entry) }
                    else if entry.lastPathComponent.lowercased() == markerName { return entry }
                }
            }
            if next.isEmpty || depth == maxDepth { break }
            level = next
        }
        return nil
    }
}
