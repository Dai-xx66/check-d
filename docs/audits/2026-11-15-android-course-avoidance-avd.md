# Android course-avoidance AVD acceptance

Date: 2026-11-15 (Asia/Shanghai)

## Environment

- AVD: `CheckD_Planning_Isolated` (`emulator-5554`)
- App: CheckD Android Debug, package `com.daixx66.check_d`
- Account mode: offline synthetic workspace; no CheckD cloud credentials used
- Synthetic one-time task `Planning_sync_acceptance` was created and appeared on the AVD Today page beside the pre-existing synthetic `Planning_demo` task. No pre-existing task record was edited.

## Test input and result

- Synthetic course: `Planning_course_2026g`, weekly Sunday occurrence, 20:30–21:00 local time on 2026-11-15.
- Task shown in preview: `Planning_demo`; the additional synthetic task was created to verify the isolated AVD could accept test task data, but was not used to replace or modify the preview input.
- Temporary preview-only inputs: 60 remaining minutes; date-only deadline 2026-11-15. The preview dialog states these inputs are not saved to CheckD.
- Candidate shown by the Android UI: 2026-11-15 21:09–22:09 local time.
- Overlap check: candidate starts after the course ends (21:09 >= 21:00); no overlap.
- Persistence boundary: the synthetic course and `Planning_sync_acceptance` task were saved only in the isolated AVD. No pre-existing task fields were changed, no local plan was confirmed, and no cloud operation was run.

The nine-minute gap after the course follows the planner's 15-minute slot grid anchored to the current time. The result is a local provisional suggestion, not a cloud-authorized schedule.

## Occurrence-rule coverage

The UI scenario uses the real CheckD course-management screens and the local Drift-backed planning preview. Automated tests additionally exercise the canonical `buildCourseOccurrencesForDate` implementation:

- `test/course_occurrence_phase_test.dart`: odd/even week parity relative to semester start; skip/cancellation; reschedule; extra course; custom times.
- `test/planning_snapshot_python_e2e_test.dart`: serialized CheckD occurrence reaches the planner and the returned candidate avoids it.
- `test/planning_context_repository_test.dart`: Drift repository aggregation plus candidate/course non-overlap assertion.

The targeted command `flutter test test/course_occurrence_phase_test.dart test/planning_context_repository_test.dart test/planning_snapshot_python_e2e_test.dart --reporter expanded` passed 11 tests.
