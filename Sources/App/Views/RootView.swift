import SwiftUI

/// The app root. Later phases will insert splash/onboarding/profile gating here;
/// for now this is just the themed backdrop hosting the home hub.
struct RootView: View {
    var body: some View {
        ZStack {
            Theme.Color.bg.ignoresSafeArea()
            HomeView()
        }
    }
}
