import SwiftUI

/// 스캐너 창 "시뮬레이터": 런타임 표와 기기 표, 행별 삭제.
struct SimulatorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task {
            if appState.simulatorState == .notLoaded { await appState.loadSimulators() }
        }
        .sheet(isPresented: confirmationBinding) {
            if let confirmation = appState.simulatorConfirmation {
                SimulatorDeleteConfirmSheet(confirmation: confirmation)
                    .environment(appState)
            }
        }
    }

    static let toolMissingGuide = String(localized: """
        시뮬레이터를 관리하려면 Xcode가 설치되어 있고 선택되어 있어야 합니다. Xcode를 설치한 뒤 터미널에서 \
        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer 를 실행하세요.
        """)

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { appState.simulatorConfirmation != nil },
            set: { if !$0 { appState.cancelSimulatorDeletion() } }
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ScannerSection.simulators.title)
                .font(.title2.bold())
                .accessibilityIdentifier("detail.title")
            Spacer()
            if appState.isSimulatorBusy {
                ProgressView().controlSize(.small)
                Text("삭제 중…")
                    .accessibilityIdentifier("simulators.busy")
            }
            Button("새로고침") { Task { await appState.loadSimulators() } }
                .disabled(appState.isSimulatorBusy || appState.simulatorState == .loading)
                .accessibilityIdentifier("simulators.refresh")
        }
        .padding(20)
    }

    @ViewBuilder private var content: some View {
        switch appState.simulatorState {
        case .notLoaded, .loading:
            ProgressView("불러오는 중…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("simulators.loading")
        case .toolMissing(let message):
            // ContentUnavailableView는 설명 문구들을 한 요소로 합쳐 각각 읽을 수 없으므로 직접 그린다.
            VStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Xcode 개발자 도구가 필요합니다")
                    .font(.title3.bold())
                    .accessibilityIdentifier("simulators.toolMissing.title")
                // fixedSize(vertical:)를 쓰면 분할 뷰가 이상적인 크기를 물을 때 높이가 수천 pt가 되어
                // 사이드바와 머리글이 화면 밖으로 밀려난다. 폭을 고정해 줄바꿈 높이를 정한다.
                Text(Self.toolMissingGuide)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(width: 440)
                    .accessibilityIdentifier("simulators.toolMissing.guide")
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(width: 440)
                    .accessibilityIdentifier("simulators.toolMissing.detail")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("시뮬레이터 목록을 읽지 못했습니다", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
                    .accessibilityIdentifier("simulators.failed.detail")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let inventory):
            loaded(inventory)
        }
    }

    private func loaded(_ inventory: SimulatorInventory) -> some View {
        VStack(spacing: 0) {
            // List 행 안에 두면 여러 줄 stderr의 아래쪽이 잘린다.
            if let error = appState.simulatorError {
                SimulatorErrorBanner(message: error)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            runtimeAndDeviceList(inventory)
        }
    }

    private func runtimeAndDeviceList(_ inventory: SimulatorInventory) -> some View {
        List {
            Section {
                ForEach(inventory.runtimes) { RuntimeRow(runtime: $0) }
            } header: {
                let total = inventory.runtimes.reduce(Int64(0)) { $0 + $1.sizeBytes }
                Text("런타임 \(inventory.runtimes.count)개 · \(ByteFormat.gigabytes(total))")
                    .accessibilityIdentifier("simulators.runtimes.header")
            }
            Section {
                ForEach(inventory.devices) { DeviceRow(device: $0) }
            } header: {
                HStack {
                    Text("기기 \(inventory.devices.count)개")
                        .accessibilityIdentifier("simulators.devices.header")
                    Spacer()
                    Button("사용 불가 기기 모두 삭제 (\(inventory.unavailableDevices.count))") {
                        appState.requestSimulatorDeletion(
                            .unavailableDevices(count: inventory.unavailableDevices.count)
                        )
                    }
                    .disabled(inventory.unavailableDevices.isEmpty || appState.isSimulatorBusy)
                    .accessibilityIdentifier("simulators.deleteUnavailable")
                }
            }
        }
        .accessibilityIdentifier("simulators.list")
    }
}

private struct RuntimeRow: View {
    @Environment(AppState.self) private var appState
    let runtime: SimRuntime

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(runtime.displayName)
                    .accessibilityIdentifier("runtime.\(runtime.id).name")
                Text(runtime.build ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 100, alignment: .leading)
            if runtime.isCurrent {
                Badge(text: String(localized: "현재 사용 중"), color: .blue)
                    .accessibilityIdentifier("runtime.\(runtime.id).current")
            }
            if !runtime.isDeletable {
                Badge(text: String(localized: "삭제 불가"), color: .secondary)
            }
            Spacer()
            Text("기기 \(runtime.deviceCount)개")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("runtime.\(runtime.id).devices")
            Text(runtime.lastUsedAt.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .trailing)
            Text(ByteFormat.size(runtime.sizeBytes))
                .font(.body.monospacedDigit())
                .lineLimit(1)
                .frame(width: 60, alignment: .trailing)
                .accessibilityIdentifier("runtime.\(runtime.id).size")
            Button {
                appState.requestSimulatorDeletion(.runtime(runtime))
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!runtime.isDeletable || appState.isSimulatorBusy)
            .accessibilityLabel(Text("\(runtime.displayName) 런타임 삭제"))
            .accessibilityIdentifier("runtime.\(runtime.id).delete")
        }
        .padding(.vertical, 2)
    }
}

private struct DeviceRow: View {
    @Environment(AppState.self) private var appState
    let device: SimDevice

    var body: some View {
        HStack(spacing: 10) {
            Text(device.name)
                .accessibilityIdentifier("device.\(device.id).name")
            Text(device.runtimeName)
                .foregroundStyle(.secondary)
            if !device.isAvailable {
                Badge(text: String(localized: "사용 불가"), color: .orange)
                    .accessibilityIdentifier("device.\(device.id).unavailable")
            }
            Spacer()
            Text(device.stateText)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("device.\(device.id).state")
            Button {
                appState.requestSimulatorDeletion(.device(device))
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(appState.isSimulatorBusy)
            .accessibilityLabel(Text("\(device.name) 기기 삭제"))
            .accessibilityIdentifier("device.\(device.id).delete")
        }
        .padding(.vertical, 2)
    }
}

private struct SimulatorErrorBanner: View {
    @Environment(AppState.self) private var appState
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("삭제하지 못했습니다", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("simulators.error.title")
                Spacer()
                Button {
                    appState.simulatorError = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("오류 닫기"))
            }
            Text(message)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("simulators.error.stderr")
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 런타임·기기 삭제 확인 창. 현재 사용 중인 런타임은 두 번째 확인 문구를 보여 준다.
private struct SimulatorDeleteConfirmSheet: View {
    @Environment(AppState.self) private var appState
    let confirmation: SimulatorConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.bold())
                .accessibilityIdentifier("simulators.confirm.title")
            if let detail {
                Text(detail)
                    .accessibilityIdentifier("simulators.confirm.detail")
            }
            Text("휴지통을 거치지 않고 바로 삭제됩니다. 되돌릴 수 없습니다.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("simulators.confirm.permanent")
            if confirmation.isSecondStep {
                Label {
                    Text("현재 Xcode가 기본으로 쓰는 런타임입니다. 지우면 이 버전의 시뮬레이터에서 앱을 실행할 수 없고, 다시 쓰려면 수 GB를 다시 내려받아야 합니다.")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("simulators.confirm.inUseWarning")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
            }
            HStack {
                Spacer()
                Button("취소") { appState.cancelSimulatorDeletion() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("simulators.confirm.cancel")
                Button(confirmation.isSecondStep ? "그래도 삭제" : "삭제", role: .destructive) {
                    Task { await appState.confirmSimulatorDeletion() }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("simulators.confirm.ok")
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var title: String {
        switch confirmation.deletion {
        case .runtime(let runtime): String(localized: "\(runtime.displayName) 런타임을 삭제할까요?")
        case .device(let device): String(localized: "\(device.name) 기기를 삭제할까요?")
        case .unavailableDevices(let count): String(localized: "사용 불가 기기 \(count)개를 삭제할까요?")
        }
    }

    private var detail: String? {
        switch confirmation.deletion {
        case .runtime(let runtime):
            String(localized: "용량 \(ByteFormat.gigabytes(runtime.sizeBytes)) · 연결된 기기 \(runtime.deviceCount)개")
        case .device(let device): device.runtimeName
        case .unavailableDevices: String(localized: "xcrun simctl delete unavailable")
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}
