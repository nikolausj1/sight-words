import SwiftUI
import SwiftData

/// The parent dashboard (§6.12): "Needs help" (most-missed first), "Almost
/// fluent" (with fluent-day progress), and a collapsed "Mastered" count.
/// Tapping any word opens a detail popover. Scoped to the active profile,
/// embedded in the parent area's right column.
struct DashboardView: View {
    let profile: Profile?
    let service: LearningService

    @Environment(\.horizontalSizeClass) private var hSizeClass
    /// Compact (iPhone portrait): word rows reflow their meta (accuracy/day
    /// count/last-seen) onto a second line instead of cramming one row.
    /// Regular (iPad): identical to before.
    private var isCompact: Bool { hSizeClass == .compact }

    @State private var masteredOpen = false
    @State private var selectedWord: WordProgressRecord?

    private var progress: [WordProgressRecord] {
        guard let profile else { return [] }
        return service.introducedProgress(for: profile)
    }

    private var needsHelp: [WordProgressRecord] {
        progress.filter { $0.needsReview || $0.stateRaw == WordState.learning.rawValue }
            .sorted { $0.timesMissed > $1.timesMissed }
    }
    private var almostFluent: [WordProgressRecord] {
        progress.filter { $0.stateRaw == WordState.developing.rawValue
                        || $0.stateRaw == WordState.fluent.rawValue }
            .sorted { $0.fluentDayCount > $1.fluentDayCount }
    }
    private var mastered: [WordProgressRecord] {
        progress.filter { $0.stateRaw == WordState.mastered.rawValue }
            .sorted { $0.wordText.lowercased() < $1.wordText.lowercased() }
    }

    var body: some View {
        VStack(spacing: Theme.Metric.gap) {
            if progress.isEmpty {
                emptyState
            } else {
                if !needsHelp.isEmpty {
                    card("Needs help", tint: Theme.Color.accent) {
                        VStack(spacing: 8) { ForEach(needsHelp) { wordRow($0) } }
                    }
                }
                if !almostFluent.isEmpty {
                    card("Almost fluent", tint: Theme.Color.primary) {
                        VStack(spacing: 8) { ForEach(almostFluent) { wordRow($0) } }
                    }
                }
                if !mastered.isEmpty {
                    card("Mastered", tint: Theme.Color.correct, badge: mastered.count) {
                        masteredSection
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .popover(item: $selectedWord) { wp in
            WordDetailView(word: wp)
                .frame(minWidth: 340, minHeight: 320)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 34)).foregroundStyle(Theme.Color.inkSoft)
            Text("Start the first session to see progress here.")
                .font(Theme.Font.body()).foregroundStyle(Theme.Color.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Metric.pad)
        .cardSurface()
    }

    private var masteredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { masteredOpen.toggle() }
            } label: {
                HStack {
                    Text("\(mastered.count) word\(mastered.count == 1 ? "" : "s") mastered")
                        .font(Theme.Font.label(15)).foregroundStyle(Theme.Color.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .rotationEffect(.degrees(masteredOpen ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if masteredOpen {
                VStack(spacing: 8) { ForEach(mastered) { wordRow($0) } }
            }
        }
    }

    @ViewBuilder
    private func wordRow(_ wp: WordProgressRecord) -> some View {
        if isCompact {
            Button {
                selectedWord = wp
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(wp.wordText)
                            .font(Theme.Font.label(16)).foregroundStyle(Theme.Color.ink)
                        Spacer()
                        Text(accuracyLabel(wp))
                            .font(Theme.Font.label(13)).foregroundStyle(Theme.Color.inkSoft)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Color.inkSoft.opacity(0.6))
                    }
                    HStack(spacing: 6) {
                        if wp.stateRaw == WordState.fluent.rawValue || wp.stateRaw == WordState.developing.rawValue {
                            Text("\(min(wp.fluentDayCount, 3)) of 3 days")
                                .font(Theme.Font.label(11)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.Color.primary))
                        }
                        if let last = wp.lastSeenAt {
                            Text(last.formatted(.relative(presentation: .named)))
                                .font(Theme.Font.label(11)).foregroundStyle(Theme.Color.inkSoft)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.Color.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                selectedWord = wp
            } label: {
                HStack(spacing: 10) {
                    Text(wp.wordText)
                        .font(Theme.Font.label(16)).foregroundStyle(Theme.Color.ink)
                    Spacer()
                    Text(accuracyLabel(wp))
                        .font(Theme.Font.label(13)).foregroundStyle(Theme.Color.inkSoft)
                    if wp.stateRaw == WordState.fluent.rawValue || wp.stateRaw == WordState.developing.rawValue {
                        Text("\(min(wp.fluentDayCount, 3)) of 3 days")
                            .font(Theme.Font.label(12)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.Color.primary))
                    }
                    if let last = wp.lastSeenAt {
                        Text(last.formatted(.relative(presentation: .named)))
                            .font(Theme.Font.label(12)).foregroundStyle(Theme.Color.inkSoft)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkSoft.opacity(0.6))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.Color.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func accuracyLabel(_ wp: WordProgressRecord) -> String {
        guard wp.timesSeen > 0 else { return "—" }
        let pct = Int((Double(wp.timesCorrect) / Double(wp.timesSeen) * 100).rounded())
        return "\(pct)%"
    }

    @ViewBuilder
    private func card<Content: View>(_ title: String, tint: Color, badge: Int = 0,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(Theme.Font.label(13)).tracking(1.5)
                    .foregroundStyle(Theme.Color.inkSoft)
                if badge > 0 && title != "Mastered" {
                    Text("\(badge)")
                        .font(Theme.Font.label(12)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(tint))
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Metric.pad).cardSurface()
    }
}

/// Word detail popover (§6.12): state, accuracy, average response time, last 5
/// results as colored dots, times seen, and first-seen date.
private struct WordDetailView: View {
    let word: WordProgressRecord

    private var state: WordState { WordState(rawValue: word.stateRaw) ?? .new }
    private var stateLabel: String {
        switch state {
        case .new: "New"; case .learning: "Learning"; case .developing: "Developing"
        case .fluent: "Fluent"; case .mastered: "Mastered"
        }
    }
    private var stateColor: Color {
        switch state {
        case .new: Theme.Color.gentle; case .learning: Theme.Color.accent
        case .developing: Theme.Color.primary; case .fluent: Theme.Color.correct
        case .mastered: Theme.Color.correct
        }
    }
    private var accuracy: String {
        guard word.timesSeen > 0 else { return "—" }
        return "\(Int((Double(word.timesCorrect) / Double(word.timesSeen) * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(word.wordText).font(Theme.Font.display(30)).foregroundStyle(Theme.Color.ink)
                Spacer()
                Text(stateLabel.uppercased())
                    .font(Theme.Font.label(12)).tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(stateColor))
            }
            HStack(spacing: 24) {
                stat("Accuracy", accuracy)
                stat("Avg. time", String(format: "%.1fs", Double(word.avgResponseMs) / 1000))
                stat("Times seen", "\(word.timesSeen)")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("LAST 5 RESULTS").font(Theme.Font.label(12)).tracking(1.2)
                    .foregroundStyle(Theme.Color.inkSoft)
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { i in
                        let results = word.recentResults
                        let idx = results.count - 5 + i
                        Circle()
                            .fill(idx >= 0 ? dotColor(results[idx]) : Theme.Color.gentle.opacity(0.25))
                            .frame(width: 22, height: 22)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("FIRST SEEN").font(Theme.Font.label(12)).tracking(1.2)
                    .foregroundStyle(Theme.Color.inkSoft)
                Text(word.firstSeenAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                    .font(Theme.Font.body()).foregroundStyle(Theme.Color.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Metric.pad)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.Font.number(22)).foregroundStyle(Theme.Color.ink)
            Text(label).font(Theme.Font.label(12)).foregroundStyle(Theme.Color.inkSoft)
        }
    }

    private func dotColor(_ result: String) -> Color {
        switch result {
        case "gotIt": return Theme.Color.correct
        case "almost": return Theme.Color.accent
        default: return Theme.Color.gentle
        }
    }
}
