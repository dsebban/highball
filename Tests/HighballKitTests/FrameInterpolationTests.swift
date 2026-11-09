import XCTest
@testable import HighballKit

/// Per-program D3DMetal frame interpolation profiles and the local D3DMetal import. D3DMetal 4.0
/// beta 3 offers DLSS Frame Generation only when nvngx_dlssg.dll is beneath the executable's folder
/// or the working folder: Hellblade II keeps it under Engine/Plugins beside its Hellblade2 folder and
/// hid the option when started from its executable's folder (2026-11-09).
final class FrameInterpolationTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appending(path: "hb-fi-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func touch(_ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data())
    }

    private func manifest() throws -> EngineManifest {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "spike/engines/x64-crossover26.3-r30.json")
        return try EngineManifest.load(from: url)
    }

    /// A GPTK `redist/lib`-shaped folder with D3DMetal at `version`.
    private func gptk(_ version: String, at dir: URL) throws -> URL {
        for f in ["external/D3DMetal.framework/Versions/A/D3DMetal", "external/libd3dshared.dylib",
                  "wine/x86_64-windows/d3d12.dll", "wine/x86_64-windows/dxgi.dll", "wine/x86_64-windows/d3d11.dll",
                  "wine/x86_64-windows/nvngx.dll", "wine/x86_64-unix/d3d12.so", "wine/x86_64-unix/dxgi.so", "wine/x86_64-unix/nvngx.so"] {
            try touch(dir.appending(path: f))
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
        try fm.createDirectory(at: dir.appending(path: "external/D3DMetal.framework/Versions/A/Resources"), withIntermediateDirectories: true)
        try plist.write(to: dir.appending(path: "external/D3DMetal.framework/Versions/A/Resources/Info.plist"))
        try fm.createSymbolicLink(at: dir.appending(path: "external/D3DMetal.framework/Resources"), withDestinationURL: dir.appending(path: "external/D3DMetal.framework/Versions/A/Resources"))
        return dir
    }

    private func engine(d3dmetal version: String) throws -> InstalledEngine {
        var m = try manifest()
        m.acceptedLicenses = [EngineManifest.gatedRenderers["d3dmetal"]!]
        let engineRoot = root.appending(path: "engine-\(UUID().uuidString)")
        _ = try gptk(version, at: engineRoot.appending(path: "renderers/d3dmetal"))
        try fm.createDirectory(at: engineRoot.appending(path: "renderers/dxmt/wine"), withIntermediateDirectories: true)
        return InstalledEngine(manifest: m, root: engineRoot)
    }

    private func bottle(dlss: Bool = true, fpsCap: Int = 0) -> Bottle {
        var settings = BottleSettings(name: "fi", engineID: "x64-crossover26.3-r30")
        settings.renderer = .d3dmetal
        settings.dlssEnabled = dlss
        settings.fpsCap = fpsCap
        return Bottle(url: root.appending(path: "bottle"), settings: settings)
    }

    /// Hellblade II's layout: the executable three folders below the root, the marker under Engine/.
    private func hellblade() throws -> URL {
        let game = root.appending(path: "Senua's Saga Hellblade II")
        try touch(game.appending(path: "Engine/Plugins/Runtime/Nvidia/StreamlineCore/Binaries/ThirdParty/Win64/nvngx_dlssg.dll"))
        let exe = game.appending(path: "Hellblade2/Binaries/Win64/Hellblade2-Win64-Shipping.exe")
        try touch(exe)
        return exe
    }

    func testHellbladeOffersFrameGenerationOnlyFromItsRootFolder() throws {
        let exe = try hellblade(), eng = try engine(d3dmetal: "4.0b3"), b = bottle()
        let fromExeFolder = FrameInterpolationProfile(presentedCap: 60, metal4: false)
            .launch(executable: exe, renderer: .d3dmetal, engine: eng, bottle: b)
        guard case .unavailable = fromExeFolder.status else { return XCTFail("the marker is not beneath Binaries/Win64: \(fromExeFolder.status)") }
        XCTAssertEqual(fromExeFolder.environment, [:], "an unusable profile must not cap the game")
        XCTAssertEqual(fromExeFolder.workingDirectory.path, exe.deletingLastPathComponent().path)

        let fromRoot = FrameInterpolationProfile(presentedCap: 60, metal4: false, workingDirectory: "../../..")
            .launch(executable: exe, renderer: .d3dmetal, engine: eng, bottle: b)
        guard case let .ready(version, marker) = fromRoot.status else { return XCTFail("\(fromRoot.status)") }
        XCTAssertEqual(version, "4.0b3")
        XCTAssertEqual(marker.lastPathComponent, "nvngx_dlssg.dll")
        XCTAssertEqual(fromRoot.workingDirectory.path, root.appending(path: "Senua's Saga Hellblade II").standardizedFileURL.path)
        // Without CX_ACTIVE_GRAPHICS_BACKEND the engine's Wine leaves the GPU-scheduling query unanswered
        // and Streamline turns DLSS-G off.
        XCTAssertEqual(fromRoot.environment, ["D3DM_MAX_FPS": "60", "D3DM_MTL4": "0", "CX_ACTIVE_GRAPHICS_BACKEND": "d3dmetal"])
    }

    /// Galactic Racer keeps the marker beside its executable: no working folder needed.
    func testAMarkerBesideTheExecutableIsEnough() throws {
        let exe = root.appending(path: "STAR WARS Galactic Racer/Griffin/Binaries/Win64/SWGR-Win64-Shipping.exe")
        try touch(exe)
        try touch(exe.deletingLastPathComponent().appending(path: "NVNGX_DLSSG.DLL"))
        let launch = FrameInterpolationProfile(presentedCap: 120, metal4: false)
            .launch(executable: exe, renderer: .d3dmetal, engine: try engine(d3dmetal: "4.0b3"), bottle: bottle())
        guard case .ready = launch.status else { return XCTFail("\(launch.status)") }
        XCTAssertEqual(launch.environment["D3DM_MAX_FPS"], "120")
    }

    /// Anything short of D3DMetal 4 with its MetalFX bridge leaves the program as it was.
    func testAProfileFallsBackWhenTheStackCannotInterpolate() throws {
        let exe = try hellblade()
        let profile = FrameInterpolationProfile(presentedCap: 60, metal4: false, workingDirectory: "../../..")
        let cases: [(String, Renderer, InstalledEngine, Bottle)] = [
            ("D3DMetal 3", .d3dmetal, try engine(d3dmetal: "3.0"), bottle()),
            ("DXMT", .dxmt, try engine(d3dmetal: "4.0b3"), bottle()),
            ("DLSS off", .d3dmetal, try engine(d3dmetal: "4.0b3"), bottle(dlss: false)),
        ]
        for (label, renderer, eng, b) in cases {
            let launch = profile.launch(executable: exe, renderer: renderer, engine: eng, bottle: b)
            guard case .unavailable = launch.status else { XCTFail("\(label): \(launch.status)"); continue }
            XCTAssertEqual(launch.environment, [:], label)
            XCTAssertEqual(launch.workingDirectory.path, exe.deletingLastPathComponent().path, label)
        }
    }

    /// The search stops at D3DMetal's depth: 12 folders below the root is found, 13 is not.
    func testTheMarkerSearchIsBoundedLikeD3DMetals() throws {
        func nested(_ depth: Int) throws -> URL {
            var dir = root.appending(path: "depth\(depth)")
            let top = dir
            for i in 0..<depth { dir = dir.appending(path: "d\(i)") }
            try touch(dir.appending(path: "nvngx_dlssg.dll"))
            return top
        }
        XCTAssertNotNil(FrameInterpolationProfile.findMarker(under: try nested(12)))
        XCTAssertNil(FrameInterpolationProfile.findMarker(under: try nested(13)))
    }

    /// The profile's cap reaches the launch over the environment's own cap.
    func testTheProfileCapWinsOverTheEnvironmentCap() throws {
        let exe = try hellblade(), eng = try engine(d3dmetal: "4.0b3"), b = bottle(fpsCap: 30)
        let launch = FrameInterpolationProfile(presentedCap: 60, metal4: false, workingDirectory: "../../..")
            .launch(executable: exe, renderer: .d3dmetal, engine: eng, bottle: b)
        let env = try b.environment(engine: eng, renderer: nil, extra: launch.environment)
        XCTAssertEqual(env["D3DM_MAX_FPS"], "60")
        XCTAssertEqual(env["D3DM_MTL4"], "0")
        XCTAssertEqual(env["D3DM_ENABLE_METALFX"], "1")
        XCTAssertEqual(try b.environment(engine: eng, renderer: nil)["D3DM_MAX_FPS"], "30", "other programs keep the environment's cap")
    }

    func testPinsWrittenBeforeProfilesStillDecode() throws {
        let old = try JSONDecoder().decode(Pin.self, from: Data(#"{"name":"Game","path":"/g/game.exe"}"#.utf8))
        XCTAssertNil(old.interpolation)
        var pin = old
        pin.interpolation = FrameInterpolationProfile(presentedCap: 60, metal4: false, workingDirectory: "../../..")
        let back = try JSONDecoder().decode(Pin.self, from: JSONEncoder().encode(pin))
        XCTAssertEqual(back.interpolation, pin.interpolation)
    }

    // MARK: Local D3DMetal

    func testALocalD3DMetalMustBeTheVersionTheEngineNames() throws {
        let wanted = try XCTUnwrap(try manifest().components["d3dmetal"])
        let good = try EngineStore.localD3DMetal(at: try gptk("4.0b3", at: root.appending(path: "b3")), matching: wanted)
        XCTAssertEqual(good.url.path, root.appending(path: "b3").path)
        XCTAssertTrue(good.version?.hasPrefix("D3DMetal-4.0b3 (local") == true)
        XCTAssertEqual(good.sha256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "the framework binary's digest (empty here)")
        XCTAssertThrowsError(try EngineStore.localD3DMetal(at: try gptk("4.0b2", at: root.appending(path: "b2")), matching: wanted))
        let partial = try gptk("4.0b3", at: root.appending(path: "partial"))
        try fm.removeItem(at: partial.appending(path: "wine/x86_64-windows/d3d12.dll"))
        XCTAssertThrowsError(try EngineStore.localD3DMetal(at: partial, matching: wanted))
    }

    /// An installed engine's manifest names the linked folder as D3DMetal's url, so a reinstall from
    /// it (the app's Reinstall engine) must take the local path, with its licence and file checks,
    /// rather than verify a folder as a downloaded archive (which fails only after downloading the rest).
    func testAReinstallTakesTheLocalD3DMetalPathWithItsChecks() async throws {
        var m = try manifest()
        let gptkDir = try gptk("4.0b3", at: root.appending(path: "gptk"))
        m.components["d3dmetal"] = try EngineStore.localD3DMetal(at: gptkDir, matching: try XCTUnwrap(m.components["d3dmetal"]))
        let store = EngineStore(paths: HighballPaths(home: root.appending(path: "home")))
        let licence = EngineManifest.gatedRenderers["d3dmetal"]!
        do {
            _ = try await store.install(m, accepted: [])
            XCTFail("installed D3DMetal without its licence")
        } catch {
            XCTAssertTrue("\(error)".contains("licence"), "\(error)")
        }
        try fm.removeItem(at: gptkDir)
        do {
            _ = try await store.install(m, accepted: [licence])
            XCTFail("installed with the linked D3DMetal gone")
        } catch {
            XCTAssertTrue("\(error)".contains("D3DMetal files in \(gptkDir.path)"), "\(error)")
        }
    }
}
