import SwiftUI
import LumaUI

/// Development host: the real Luma root over demo data. Launch arguments pick the screen
/// (`-lumaScreen today.sleep -lumaScroll 400 -lumaData sparse`); see Tools/luma_screens.txt.
/// `-lumaData` is `demo`, `sparse` (a first week), or a staged situation: `partial` (a night whose
/// record stops early), `locked` and `stuck` (the athlete's records cannot be opened).
@main
struct GalleryApp: App {
    @StateObject private var env = GalleryApp.makeEnv()

    private static func makeEnv() -> LumaEnv {
        LumaType.followsTextSize = true
        let data = UserDefaults.standard.string(forKey: "lumaData")
        let staged = ["partial", "locked", "stuck"].contains(data ?? "") ? data : nil
        return LumaEnv.demo(sparse: data == "sparse", scenario: staged)
    }

    var body: some Scene {
        WindowGroup {
            LumaRootView(env: env, launch: LumaLaunch.fromArguments())
        }
    }
}
