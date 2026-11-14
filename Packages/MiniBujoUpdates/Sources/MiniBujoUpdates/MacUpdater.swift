#if os(macOS)
import AppKit
import Combine
import Sparkle

/// Keep the controller alive for the entire app lifetime; Sparkle owns update preferences.
@MainActor
public final class MacUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published public private(set) var canCheckForUpdates = false
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    private var beforeRelaunch: (() -> Void)?

    public override init() { super.init() }

    public func start(beforeRelaunch: @escaping () -> Void) {
        guard controller == nil else { return }
        self.beforeRelaunch = beforeRelaunch
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
        )
        self.controller = controller
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
        controller.startUpdater()
    }

    public func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    public func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        beforeRelaunch?()
    }
}
#endif
