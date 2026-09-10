import SwiftUI
import WidgetKit
import ActivityKit

private let appGroup = "group.com.daixx66.checkd"

struct WidgetSnapshot: Codable {
  let schemaVersion: Int
  let generatedAt: String
  let dateKey: String
  let dateText: String
  let current: WidgetCurrent
  let next: WidgetNext?
  let today: WidgetToday
}

struct WidgetCurrent: Codable {
  let mode: String
  let title: String
  let subtitle: String
  let timeText: String?
  let sheepState: String
  let progress: Double?
  let concurrentTimer: WidgetTimer?
  let additionalTimerCount: Int
}

struct WidgetTimer: Codable {
  let id: String
  let title: String
  let status: String
  let elapsedSeconds: Int
}

struct WidgetNext: Codable {
  let type: String
  let title: String
  let timeText: String
  let location: String?
}

struct WidgetToday: Codable {
  let completedCount: Int
  let pendingCount: Int
}

struct CheckDEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot?
}

struct CheckDProvider: TimelineProvider {
  func placeholder(in context: Context) -> CheckDEntry {
    CheckDEntry(date: Date(), snapshot: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (CheckDEntry) -> Void) {
    completion(CheckDEntry(date: Date(), snapshot: loadSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CheckDEntry>) -> Void) {
    let entry = CheckDEntry(date: Date(), snapshot: loadSnapshot())
    let now = Date()
    let cadence = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
    let tomorrow = Calendar.current.nextDate(
      after: now,
      matching: DateComponents(hour: 0, minute: 1),
      matchingPolicy: .nextTime
    ) ?? cadence
    let nextUpdate = min(cadence, tomorrow)
    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
  }

  private func loadSnapshot() -> WidgetSnapshot? {
    guard let raw = UserDefaults(suiteName: appGroup)?.string(forKey: "snapshot"),
          let data = raw.data(using: .utf8) else { return nil }
    guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard snapshot.schemaVersion == 2,
          snapshot.dateKey == formatter.string(from: Date()),
          let generatedAt = ISO8601DateFormatter().date(from: snapshot.generatedAt),
          Date().timeIntervalSince(generatedAt) <= 6 * 60 * 60 else {
      return nil
    }
    return snapshot
  }
}

struct CheckDWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CheckDEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text("Check D")
          .font(.headline)
        Spacer()
        Text(entry.snapshot?.dateText ?? "今天")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let snapshot = entry.snapshot {
        currentSection(snapshot)
        if family != .systemSmall {
          nextSection(snapshot)
          Spacer(minLength: 0)
          HStack {
            Text("✓ 已完成 \(snapshot.today.completedCount)")
              .foregroundStyle(Color(red: 0.25, green: 0.58, blue: 0.43))
            Spacer()
            Text("待完成 \(snapshot.today.pendingCount)")
          }
            .font(.caption)
            .foregroundColor(.secondary)
        }
      } else {
        fallback
      }
    }
    .padding()
    .background(Color(red: 1, green: 0.986, blue: 0.986))
  }

  @ViewBuilder
  private func currentSection(_ snapshot: WidgetSnapshot) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(snapshot.current.subtitle)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.pink)
        Text(snapshot.current.title)
          .font(.headline)
          .lineLimit(1)
        if let time = snapshot.current.timeText, !time.isEmpty {
          Text(time).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      Image(sheepAsset(snapshot.current.sheepState))
        .resizable()
        .scaledToFit()
        .frame(width: family == .systemSmall ? 50 : 64, height: family == .systemSmall ? 42 : 54)
        .accessibilityHidden(true)
    }
    if let progress = snapshot.current.progress {
      ProgressView(value: progress).tint(.pink)
    }
    if isCourse(snapshot.current), let timer = snapshot.current.concurrentTimer, family != .systemSmall {
      Text(concurrentText(timer, extra: snapshot.current.additionalTimerCount))
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private func nextSection(_ snapshot: WidgetSnapshot) -> some View {
    if let next = snapshot.next {
      Divider()
      Text("接下来").font(.caption).foregroundColor(.secondary)
      Text(joinSegments(next.title, next.timeText, next.location))
        .font(.subheadline)
        .lineLimit(1)
    } else if snapshot.today.pendingCount > 0 {
      Divider()
      Text("今天还有 \(snapshot.today.pendingCount) 项待完成")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
  }

  private var fallback: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("今天慢慢来 ♡").font(.headline)
        Text("打开 Check D 更新今天状态").font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Image("sheep_idle").resizable().scaledToFit().frame(width: 60, height: 50)
    }
  }

  private func isCourse(_ current: WidgetCurrent) -> Bool {
    current.mode == "courseTeaching" || current.mode == "courseBreak"
  }

  private func concurrentText(_ timer: WidgetTimer, extra: Int) -> String {
    joinSegments(timer.status == "paused" ? "已暂停" : "同时专注", timer.title, duration(timer.elapsedSeconds), extra > 0 ? "另有 \(extra) 项" : nil)
  }

  private func duration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    return minutes >= 60 ? "\(minutes / 60)小时\(minutes % 60)分" : "\(minutes) 分钟"
  }

  private func sheepAsset(_ state: String) -> String {
    switch state {
    case "course": return "sheep_course"
    case "breakTime": return "sheep_break"
    case "focus": return "sheep_focus"
    case "paused": return "sheep_paused"
    default: return "sheep_idle"
    }
  }

  private func joinSegments(_ values: String?...) -> String {
    values.compactMap { value in
      guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty, value != "null", value != "undefined" else { return nil }
      return value
    }.joined(separator: " · ")
  }
}

struct CheckDHomeWidget: Widget {
  let kind = "CheckDHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CheckDProvider()) { entry in
      CheckDWidgetView(entry: entry)
        .widgetURL(URL(string: "checkd://today"))
    }
    .configurationDisplayName("Check D")
    .description("查看当前课程、计时和今日进度")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@available(iOSApplicationExtension 16.1, *)
struct CheckDLockScreenActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CheckDLockScreenAttributes.self) { context in
      CheckDLockScreenActivityView(state: context.state)
        .activityBackgroundTint(Color(red: 1, green: 0.96, blue: 0.95))
        .activitySystemActionForegroundColor(.pink)
        .widgetURL(URL(string: "checkd://today"))
    } dynamicIsland: { _ in
      // ActivityKit requires this declaration even though Dynamic Island is
      // intentionally deferred as a product surface in Stage 12.
      DynamicIsland {
        DynamicIslandExpandedRegion(.center) {
          Text("Check D")
        }
      } compactLeading: {
        Image(systemName: "heart.fill")
      } compactTrailing: {
        Image(systemName: "timer")
      } minimal: {
        Image(systemName: "heart.fill")
      }
    }
  }
}

@available(iOSApplicationExtension 16.1, *)
private struct CheckDLockScreenActivityView: View {
  let state: CheckDLockScreenAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 5) {
            Image(systemName: state.mode == "courseBreak" ? "cup.and.saucer.fill" : "heart.fill")
              .foregroundStyle(.pink)
            Text("Check D")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.pink)
            Spacer()
            Text(state.subtitle)
              .font(.caption.weight(.semibold))
          }
          Text(state.title)
            .font(.headline)
            .lineLimit(1)
          detailLine
        }
        Image(sheepAsset)
          .resizable()
          .scaledToFit()
          .frame(width: 72, height: 64)
          .accessibilityHidden(true)
      }

      if isCourse {
        courseProgress
        if state.concurrentTimerTitle != nil {
          Divider()
          concurrentTimerSummary
        }
        if let nextTitle = state.nextTitle, let next = state.nextStartAtEpochMs {
          Divider()
          Text("下节课  \(nextTitle) · \(clock(next))\(state.nextClassroom.map { " · \($0)" } ?? "")")
            .font(.caption)
            .lineLimit(1)
        }
      } else if state.additionalTimerCount > 0 {
        Text("另有 \(state.additionalTimerCount) 项正在计时")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  private var isCourse: Bool {
    state.mode == "courseTeaching" || state.mode == "courseBreak"
  }

  @ViewBuilder
  private var detailLine: some View {
    if isCourse, let start = state.startAtEpochMs, let end = state.endAtEpochMs {
      Text("\(clock(start)) — \(clock(end))\(state.classroom.map { " · \($0)" } ?? "")")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else if state.mode == "timerRunning", let since = state.runningSinceEpochMs {
      Text("已专注 \(Date(timeIntervalSince1970: TimeInterval(since) / 1000), style: .timer)")
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    } else {
      Text("累计 \(duration(state.elapsedSeconds))")
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }

  private var courseProgress: some View {
    VStack(spacing: 4) {
      HStack {
        Text(state.startAtEpochMs.map(clock) ?? "")
        Spacer()
        Text(state.endAtEpochMs.map(clock) ?? "")
      }
      .font(.caption2.monospacedDigit())
      .foregroundStyle(.secondary)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          HStack(spacing: 2) {
            ForEach(state.segments) { segment in
              Capsule()
                .fill(segment.kind == "breakTime" ? Color.orange.opacity(0.35) : Color.pink.opacity(0.22))
                .frame(width: max(6, proxy.size.width * segmentShare(segment)))
            }
          }
          Capsule()
            .fill(Color.pink)
            .frame(width: max(0, proxy.size.width * min(max(state.progress, 0), 1)))
          Image(sheepAsset)
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 28)
            .offset(x: max(0, proxy.size.width * min(max(state.progress, 0), 1) - 15), y: -10)
        }
      }
      .frame(height: 12)
    }
  }

  @ViewBuilder
  private var concurrentTimerSummary: some View {
    if let title = state.concurrentTimerTitle {
      HStack(spacing: 7) {
        Image(timerSheepAsset)
          .resizable()
          .scaledToFit()
          .frame(width: 30, height: 27)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
          Text(state.concurrentTimerStatus == "paused" ? "已暂停" : "同时专注")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(
              state.concurrentTimerStatus == "paused" ? Color.secondary : Color.pink
            )
          HStack(spacing: 4) {
            Text(title)
              .lineLimit(1)
            Spacer(minLength: 4)
            if state.concurrentTimerStatus == "running",
               let since = state.concurrentTimerRunningSinceEpochMs {
              Text(Date(timeIntervalSince1970: TimeInterval(since) / 1000), style: .timer)
                .monospacedDigit()
            } else {
              Text("累计 \(duration(state.concurrentTimerElapsedSeconds))")
                .monospacedDigit()
            }
          }
          .font(.caption)
        }
      }
      if state.additionalTimerCount > 0 {
        Text("另有 \(state.additionalTimerCount) 项正在计时")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var sheepAsset: String {
    switch state.sheepState {
    case "course": return "sheep_course"
    case "breakTime": return "sheep_break"
    case "paused": return "sheep_paused"
    default: return "sheep_focus"
    }
  }

  private var timerSheepAsset: String {
    state.concurrentTimerStatus == "paused" ? "sheep_paused" : "sheep_focus"
  }

  private func segmentShare(_ segment: CheckDLockScreenAttributes.Segment) -> CGFloat {
    let total = max(1, (state.endAtEpochMs ?? 0) - (state.startAtEpochMs ?? 0))
    return CGFloat(Double(segment.endAtEpochMs - segment.startAtEpochMs) / Double(total))
  }

  private func clock(_ epochMs: Int64) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000))
  }

  private func duration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
  }
}

@main
struct CheckDWidgetBundle: WidgetBundle {
  var body: some Widget {
    CheckDHomeWidget()
    if #available(iOSApplicationExtension 16.1, *) {
      CheckDLockScreenActivity()
    }
  }
}
