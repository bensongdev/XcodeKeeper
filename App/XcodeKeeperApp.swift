import SwiftUI
import UserNotifications

enum WindowID {
    static let scanner = "scanner"
}

// 단위 테스트는 이 앱을 테스트 호스트로 실행한다. 그때는 메뉴바 아이콘이나 창을 띄우지 않고 앞으로 나오지도 않게 해서
// 테스트 중에도 사용자의 작업을 방해하지 않는다. 실제 디스크를 읽는 앱 상태도 만들지 않는다.
// UI 테스트로 실행한 앱에는 이 환경 변수가 없다.
@main
enum AppEntry {
    @MainActor
    static func main() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            TestHostApp.main()
        } else {
            XcodeKeeperApp.main()
        }
    }
}

private struct TestHostApp: App {
    @NSApplicationDelegateAdaptor(TestHostDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
private final class TestHostDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Dock에 나타나지 않고 활성화(앞으로 나오기)도 하지 않는다.
        NSApp.setActivationPolicy(.prohibited)
    }
}

struct XcodeKeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let launch = LaunchConfiguration.current()
    @State private var appState: AppState

    init() {
        let state = launch.makeAppState()
        _appState = State(initialValue: state)
        if launch.runsBackgroundWork {
            AlertClickRouter.shared.handler = { targetIDs in
                Task { await state.handleAlertClick(targetIDs: targetIDs) }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            // AppLifecycle도 AppState를 읽으므로 environment 안쪽에 둔다(바깥이면 실행 직후 크래시).
            MenuBarLabel()
                .modifier(AppLifecycle(launch: launch))
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("XcodeKeeper", id: WindowID.scanner) {
            ScannerWindow()
                .environment(appState)
        }
        .defaultSize(width: 760, height: 540)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

/// 알림 클릭을 앱 상태로 넘긴다. 앱이 알림 클릭으로 실행되면 처리기가 연결되기 전에 클릭이 올 수 있어 보관한다.
@MainActor
final class AlertClickRouter {
    static let shared = AlertClickRouter()
    private var pending: [String]?

    var handler: (([String]) -> Void)? {
        didSet {
            if let pending, let handler {
                self.pending = nil
                handler(pending)
            }
        }
    }

    func deliver(_ targetIDs: [String]) {
        if let handler { handler(targetIDs) } else { pending = targetIDs }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 알림 클릭으로 실행될 때도 응답을 받으려면 실행이 끝나기 전에 위임자를 정한다.
        guard LaunchConfiguration.current().runsBackgroundWork else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let targetIDs = response.notification.request.content.userInfo[UserNotifier.targetIDsKey] as? [String] ?? []
        await MainActor.run { AlertClickRouter.shared.deliver(targetIDs) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// 실행 직후 할 일과 창 열기 요청 처리. 메뉴바 아이콘은 실행 직후 항상 그려지므로 여기에 붙인다.
private struct AppLifecycle: ViewModifier {
    let launch: LaunchConfiguration
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .task {
                appState.startMonitoring()
                appState.refreshLoginItemStatus()
                if launch.runsBackgroundWork { appState.startBackgroundScans() }
                openUITestWindow()
                if let targetIDs = launch.alertClickTargetIDs {
                    await appState.handleAlertClick(targetIDs: targetIDs)
                }
            }
            // AppKit 알림 처리기는 openWindow를 쓸 수 없으므로 앱 상태의 요청 번호로 연다.
            // 라벨이 그려지기 전에 요청이 올 수 있어 initial로 처음 값도 확인한다.
            .onChange(of: appState.scannerWindowRequest, initial: true) { _, request in
                guard request > 0 else { return }
                openWindow(id: WindowID.scanner)
                NSApp.activate()
            }
    }

    /// UI 테스트에서 시작 시 지정한 창을 연다.
    private func openUITestWindow() {
        switch launch.windowToOpen {
        case WindowID.scanner: openWindow(id: WindowID.scanner)
        case "settings": openSettings()
        default: return
        }
        NSApp.activate()
    }
}
