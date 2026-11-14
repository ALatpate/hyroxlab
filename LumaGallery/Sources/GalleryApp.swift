import SwiftUI
import LumaUI

/// Development host: the real Luma root over demo data. Launch arguments pick the screen
/// (`-lumaScreen today.sleep -lumaScroll 400 -lumaData sparse`); see Tools/luma_screens.txt.
@main
struct GalleryApp: App {
    @StateObject private var env = LumaEnv.demo(sparse: UserDefaults.standard.string(forKey: "lumaData") == "sparse")

    var body: some Scene {
        WindowGroup {
            LumaRootView(env: env, launch: LumaLaunch.fromArguments())
        }
    }
}
