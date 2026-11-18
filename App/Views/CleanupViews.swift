import SwiftUI

/// 정리 확인 창: 항목 수, 예상 확보 용량, 명령 삭제 안내, Xcode 실행 경고.
struct CleanupConfirmSheet: View {
    @Environment(AppState.self) private var appState
    let xcodeRunningWarning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("선택한 항목을 정리할까요?")
                .font(.title3.bold())
                .accessibilityIdentifier("cleanup.confirm.title")
            VStack(alignment: .leading, spacing: 4) {
                Text("항목 \(appState.scanResults.selectedItemCount)개")
                    .accessibilityIdentifier("cleanup.confirm.count")
                Text("예상 확보 용량 \(ByteFormat.gigabytes(appState.scanResults.selectedBytes))")
                    .font(.body.monospacedDigit().bold())
                    .accessibilityIdentifier("cleanup.confirm.bytes")
            }
            Text("파일은 휴지통으로 옮깁니다. 휴지통을 비우기 전까지는 되돌릴 수 있습니다.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("cleanup.confirm.trashNote")
            if appState.selectionIncludesCommandTarget {
                Label {
                    Text("사용 불가 시뮬레이터 기기는 휴지통을 거치지 않고 `xcrun simctl delete unavailable`로 바로 삭제됩니다.")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("cleanup.confirm.commandNote")
                } icon: {
                    Image(systemName: "terminal")
                }
            }
            if xcodeRunningWarning {
                Label {
                    Text("Xcode가 실행 중입니다. DerivedData를 정리하기 전에 Xcode를 종료하는 것이 좋습니다. 열려 있는 프로젝트의 빌드와 인덱싱이 깨질 수 있습니다.")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("cleanup.confirm.xcodeWarning")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            HStack {
                Spacer()
                Button("취소") { appState.dismissCleanupConfirmation() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cleanup.confirm.cancel")
                Button(xcodeRunningWarning ? "그래도 정리" : "휴지통으로 정리") { appState.confirmCleanup() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("cleanup.confirm.ok")
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

/// 정리 결과: 확보 용량, 휴지통 안내, 실패 목록.
struct CleanupResultBanner: View {
    @Environment(AppState.self) private var appState
    let outcome: CleanupOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: outcome.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(outcome.failures.isEmpty ? .green : .orange)
                    .accessibilityHidden(true)
                Text("확보됨 \(ByteFormat.gigabytes(outcome.freedBytes))")
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("cleanup.result.freed")
                if outcome.wasCancelled {
                    Text("(취소됨)")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("cleanup.result.cancelled")
                }
                Spacer()
                Button("휴지통 열기") { appState.openTrash() }
                    .accessibilityIdentifier("cleanup.result.openTrash")
                Button {
                    appState.dismissCleanupResult()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("결과 닫기"))
                .accessibilityIdentifier("cleanup.result.dismiss")
            }
            Text("휴지통을 비워야 실제로 공간이 확보됩니다.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cleanup.result.trashNote")
            if !outcome.failures.isEmpty {
                Text("\(outcome.failures.count)개 항목을 정리하지 못했습니다")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("cleanup.result.failures")
                ForEach(Array(outcome.failures.enumerated()), id: \.offset) { index, failure in
                    Text("\(failure.targetTitle) · \(failure.itemName): \(failure.reason)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("cleanup.result.failure.\(index)")
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cleanup.result")
    }
}
