import Flutter
import UIKit
import WidgetKit
import ActivityKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "check_d/home_widget",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "saveSnapshot",
            let arguments = call.arguments as? [String: Any],
            let json = arguments["json"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let defaults = UserDefaults(suiteName: "group.com.daixx66.checkd") else {
        result(FlutterError(code: "APP_GROUP_UNAVAILABLE", message: "App Group is unavailable", details: nil))
        return
      }
      defaults.set(json, forKey: "snapshot")
      WidgetCenter.shared.reloadTimelines(ofKind: "CheckDHomeWidget")
      result(nil)
    }

    let lockScreenChannel = FlutterMethodChannel(
      name: "check_d/lock_screen_status",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    lockScreenChannel.setMethodCallHandler { call, result in
      guard call.method == "sync",
            let arguments = call.arguments as? [String: Any],
            let json = arguments["json"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard #available(iOS 16.1, *) else {
        result(FlutterError(code: "LIVE_ACTIVITY_UNSUPPORTED", message: "Live Activity requires iOS 16.1 or newer", details: nil))
        return
      }
      Task {
        do {
          try await LockScreenActivityController.sync(json: json)
          result(nil)
        } catch {
          result(FlutterError(code: "LIVE_ACTIVITY_SYNC_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

private struct LockScreenPayload: Codable {
  let mode: String
  let generatedAtEpochMs: Int64
  let course: Course?
  let timer: Timer?
  let nextCourse: NextCourse?
  let additionalTimerCount: Int?

  struct Course: Codable {
    let id: String
    let title: String
    let startAtEpochMs: Int64
    let endAtEpochMs: Int64
    let phase: String
    let progress: Double
    let segments: [Segment]
    let classroom: String?
  }

  struct Segment: Codable {
    let kind: String
    let startAtEpochMs: Int64
    let endAtEpochMs: Int64
  }

  struct Timer: Codable {
    let id: String
    let title: String
    let status: String
    let elapsedSeconds: Int
    let runningSinceEpochMs: Int64?
    let targetSeconds: Int?
  }

  struct NextCourse: Codable {
    let title: String
    let startAtEpochMs: Int64
    let classroom: String?
  }
}

@available(iOS 16.1, *)
private enum LockScreenActivityController {
  static func sync(json: String) async throws {
    let payload = try JSONDecoder().decode(LockScreenPayload.self, from: Data(json.utf8))
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw LockScreenActivityError.unavailable
    }
    guard payload.mode != "idle" else {
      await endAll()
      return
    }

    let state = contentState(for: payload)
    let activities = Activity<CheckDLockScreenAttributes>.activities
    if let activity = activities.first {
      if #available(iOS 16.2, *) {
        await activity.update(ActivityContent(state: state, staleDate: staleDate(for: payload)))
      } else {
        await activity.update(using: state)
      }
      for stale in activities.dropFirst() {
        await stale.end(using: state, dismissalPolicy: .immediate)
      }
      return
    }

    let attributes = CheckDLockScreenAttributes(activityID: UUID().uuidString)
    if #available(iOS 16.2, *) {
      _ = try Activity.request(
        attributes: attributes,
        content: ActivityContent(state: state, staleDate: staleDate(for: payload)),
        pushType: nil
      )
    } else {
      _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
    }
  }

  private static func endAll() async {
    for activity in Activity<CheckDLockScreenAttributes>.activities {
      if #available(iOS 16.2, *) {
        await activity.end(nil, dismissalPolicy: .immediate)
      } else {
        await activity.end(using: activity.contentState, dismissalPolicy: .immediate)
      }
    }
  }

  private static func staleDate(for payload: LockScreenPayload) -> Date? {
    guard payload.mode == "courseTeaching" || payload.mode == "courseBreak",
          let end = payload.course?.endAtEpochMs else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(end) / 1000)
  }

  private static func contentState(for payload: LockScreenPayload) -> CheckDLockScreenAttributes.ContentState {
    let course = payload.course
    let timer = payload.timer
    let isCourse = payload.mode == "courseTeaching" || payload.mode == "courseBreak"
    let title = course?.title ?? timer?.title ?? "Check D"
    let subtitle: String
    switch payload.mode {
    case "courseTeaching": subtitle = "上课中"
    case "courseBreak": subtitle = "课间休息"
    case "timerRunning": subtitle = "专注进行中"
    case "timerPaused": subtitle = "已暂停"
    default: subtitle = ""
    }
    let next = payload.nextCourse
    return CheckDLockScreenAttributes.ContentState(
      mode: payload.mode,
      title: title,
      subtitle: subtitle,
      startAtEpochMs: course?.startAtEpochMs,
      endAtEpochMs: course?.endAtEpochMs,
      elapsedSeconds: timer?.elapsedSeconds ?? 0,
      runningSinceEpochMs: timer?.runningSinceEpochMs,
      progress: course?.progress ?? 0,
      phase: course?.phase,
      classroom: course?.classroom,
      nextTitle: next?.title,
      nextStartAtEpochMs: next?.startAtEpochMs,
      nextClassroom: next?.classroom,
      sheepState: isCourse
        ? (payload.mode == "courseBreak" ? "breakTime" : "course")
        : (payload.mode == "timerPaused" ? "paused" : "focus"),
      concurrentTimerTitle: isCourse ? timer?.title : nil,
      concurrentTimerStatus: isCourse ? timer?.status : nil,
      concurrentTimerElapsedSeconds: isCourse ? (timer?.elapsedSeconds ?? 0) : 0,
      concurrentTimerRunningSinceEpochMs: isCourse ? timer?.runningSinceEpochMs : nil,
      additionalTimerCount: payload.additionalTimerCount ?? 0,
      segments: (course?.segments ?? []).map {
        CheckDLockScreenAttributes.Segment(
          kind: $0.kind,
          startAtEpochMs: $0.startAtEpochMs,
          endAtEpochMs: $0.endAtEpochMs
        )
      }
    )
  }
}

private enum LockScreenActivityError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "Live Activity is disabled in system settings"
  }
}
