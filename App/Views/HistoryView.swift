import SwiftUI

/// 스캐너 창 "정리 이력": 기록별 일시·항목 수·확보 용량과 누적 합계.
struct HistoryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(ScannerSection.history.title)
                    .font(.title2.bold())
                    .accessibilityIdentifier("detail.title")
                Spacer()
                Text("누적 확보 \(ByteFormat.gigabytes(CleanupHistory.totalFreed(appState.history)))")
                    .font(.body.monospacedDigit().bold())
                    .accessibilityIdentifier("history.total")
            }
            .padding(20)
            Divider()
            if appState.history.isEmpty {
                ContentUnavailableView {
                    Label("정리 이력이 없습니다", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("개발 찌꺼기를 정리하면 여기에 기록됩니다.")
                }
                .accessibilityIdentifier("history.empty")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(appState.history.enumerated()), id: \.element.id) { index, record in
                    HistoryRow(record: record, index: index)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let record: CleanupRecord
    let index: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(record.date.formatted(date: .numeric, time: .shortened))
                .font(.body.monospacedDigit())
                .accessibilityIdentifier("history.row.\(index).date")
            VStack(alignment: .leading, spacing: 2) {
                Text("항목 \(record.items.count)개")
                    .accessibilityIdentifier("history.row.\(index).count")
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("history.row.\(index).targets")
            }
            Spacer()
            Text(ByteFormat.size(record.freedBytes))
                .font(.body.monospacedDigit())
                .accessibilityIdentifier("history.row.\(index).bytes")
        }
        .padding(.vertical, 4)
    }

    /// 정리한 대상 제목(중복 제거, 처음 나온 순서).
    private var summary: String {
        var seen = Set<String>()
        return record.items.map(\.targetTitle).filter { seen.insert($0).inserted }.joined(separator: ", ")
    }
}
