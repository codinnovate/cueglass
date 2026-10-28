import AppKit
import Observation

/// Polls process and system state once a second while the diagnostics widget is on screen.
///
/// Session and settings state is observable on its own; only values with no change
/// notifications (process metrics, TCC grants, displays, overlay visibility) are sampled here.
@MainActor
@Observable
final class DiagnosticsMonitor {
    private(set) var process: ProcessMetricsSnapshot = .empty
    private(set) var permissions: [PermissionKind: PermissionState] = [:]
    private(set) var displayCount = 0
    private(set) var isOverlayVisible = false

    @ObservationIgnored private var sampler = ProcessMetricsSampler()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let permissionService: PermissionService
    @ObservationIgnored private let overlayVisible: () -> Bool

    static let pollInterval: TimeInterval = 1

    init(permissionService: PermissionService, overlayVisible: @escaping () -> Bool) {
        self.permissionService = permissionService
        self.overlayVisible = overlayVisible
    }

    var isRunning: Bool { pollTask != nil }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(seconds: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        process = sampler.sample()
        var states: [PermissionKind: PermissionState] = [:]
        for kind in PermissionKind.allCases {
            states[kind] = permissionService.state(for: kind)
        }
        permissions = states
        displayCount = NSScreen.screens.count
        isOverlayVisible = overlayVisible()
    }
}
