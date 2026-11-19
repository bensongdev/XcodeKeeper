import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section("알림") {
                Stepper(value: $settings.freeSpaceThresholdGB, in: AppSettings.freeSpaceThresholdRange, step: 5) {
                    LabeledContent("여유 공간 알림 기준") {
                        Text("\(settings.freeSpaceThresholdGB)GB")
                            .monospacedDigit()
                            .accessibilityIdentifier("settings.freeSpaceThreshold.value")
                    }
                }
                .accessibilityIdentifier("settings.freeSpaceThreshold")
                Stepper(value: $settings.swapThresholdGB, in: AppSettings.swapThresholdRange) {
                    LabeledContent("스왑 경고 기준") {
                        Text("\(settings.swapThresholdGB)GB")
                            .monospacedDigit()
                            .accessibilityIdentifier("settings.swapThreshold.value")
                    }
                }
                .accessibilityIdentifier("settings.swapThreshold")
                Toggle("백그라운드 스캔 (6시간마다)", isOn: $settings.backgroundScanEnabled)
                    .accessibilityIdentifier("settings.backgroundScan")
            }
            Section("일반") {
                Toggle("로그인 시 실행", isOn: loginItemBinding)
                    .accessibilityIdentifier("settings.loginItem")
                if appState.loginItemStatus == .requiresApproval {
                    Text("시스템 설정 > 일반 > 로그인 항목에서 허용하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.loginItem.approval")
                }
                if let error = appState.loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("settings.loginItem.error")
                }
                Toggle("메뉴바에 여유 공간 숫자 표시", isOn: $settings.showFreeSpaceInMenuBar)
                    .accessibilityIdentifier("settings.showFreeSpace")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 440, height: height)
        .onAppear { appState.refreshLoginItemStatus() }
    }

    /// Form은 스크롤 뷰라 내용 높이를 스스로 정하지 않으므로, 덧붙는 안내 줄만큼 높이를 늘린다.
    private var height: CGFloat {
        var height: CGFloat = 330
        if appState.loginItemStatus == .requiresApproval { height += 34 }
        if appState.loginItemError != nil { height += 34 }
        return height
    }

    /// 승인 대기(requiresApproval)도 등록된 상태로 보고 켬으로 표시한다.
    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { appState.loginItemStatus != .disabled },
            set: { appState.setLoginItemEnabled($0) }
        )
    }
}
