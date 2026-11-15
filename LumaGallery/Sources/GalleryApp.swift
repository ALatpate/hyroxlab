import SwiftUI
import LumaUI

/// Development host: the real Luma root over demo data. Launch arguments pick the screen
/// (`-lumaScreen today.sleep -lumaScroll 400 -lumaData sparse`); see Tools/luma_screens.txt.
/// `-lumaData` is `demo`, `sparse` (a first week) or `partial` (a night whose record stops early).
@main
struct GalleryApp: App {
    @StateObject private var env = GalleryApp.makeEnv()

    private static func makeEnv() -> LumaEnv {
        let data = UserDefaults.standard.string(forKey: "lumaData")
        return LumaEnv.demo(sparse: data == "sparse", scenario: data == "partial" ? "partial" : nil)
    }

    var body: some Scene {
        WindowGroup {
            LumaRootView(env: env, launch: LumaLaunch.fromArguments())
        }
    }
}
