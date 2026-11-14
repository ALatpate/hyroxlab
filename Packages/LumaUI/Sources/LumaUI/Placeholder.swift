import SwiftUI
import LumaCore

/// Pipeline bring-up stub; replaced by the real environment and root in the next commit.
public final class LumaEnv: ObservableObject {
    public static func demo(sparse: Bool) -> LumaEnv { LumaEnv() }
}

public struct LumaLaunch {
    public var screen: String
    public static func fromArguments() -> LumaLaunch { LumaLaunch(screen: UserDefaults.standard.string(forKey: "lumaScreen") ?? "today") }
}

public struct LumaRootView: View {
    let launch: LumaLaunch
    public init(env: LumaEnv, launch: LumaLaunch) { self.launch = launch }
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Luma \(launch.screen)").font(.system(size: 44, weight: .bold).width(.compressed)).foregroundStyle(.white)
        }
    }
}
