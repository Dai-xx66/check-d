import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct CheckDLockScreenAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    let mode: String
    let title: String
    let subtitle: String
    let startAtEpochMs: Int64?
    let endAtEpochMs: Int64?
    let elapsedSeconds: Int
    let runningSinceEpochMs: Int64?
    let progress: Double
    let phase: String?
    let classroom: String?
    let nextTitle: String?
    let nextStartAtEpochMs: Int64?
    let nextClassroom: String?
    let sheepState: String
    let concurrentTimerTitle: String?
    let concurrentTimerStatus: String?
    let concurrentTimerElapsedSeconds: Int
    let concurrentTimerRunningSinceEpochMs: Int64?
    let additionalTimerCount: Int
    let segments: [Segment]
  }

  struct Segment: Codable, Hashable, Identifiable {
    let kind: String
    let startAtEpochMs: Int64
    let endAtEpochMs: Int64

    var id: String { "\(kind)-\(startAtEpochMs)-\(endAtEpochMs)" }
  }

  let activityID: String
}
