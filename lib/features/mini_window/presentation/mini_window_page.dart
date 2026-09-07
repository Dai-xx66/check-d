import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/app_providers.dart';
import '../../../core/platform/desktop_mini_window.dart';
import '../../../core/theme/app_theme.dart';
import '../../courses/application/course_providers.dart';
import '../../schedule/application/day_schedule_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_models.dart';
import '../data/mini_window_repository.dart';
import '../domain/mini_window_models.dart';

class MiniWindowApp extends StatelessWidget {
  const MiniWindowApp({required this.ownerId, super.key});
  final String ownerId;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Check D 悬浮组件',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const MiniWindowPage(),
  );
}

class MiniWindowPage extends ConsumerStatefulWidget {
  const MiniWindowPage({super.key});
  @override
  ConsumerState<MiniWindowPage> createState() => _MiniWindowPageState();
}

class _MiniWindowPageState extends ConsumerState<MiniWindowPage>
    with WindowListener {
  static const _compactSize = Size(360, 126);
  static const _normalWidth = 390.0;
  static const _normalMinHeight = 260.0;
  static const _normalMaxHeight = 560.0;
  Timer? _ticker;
  Timer? _positionDebounce;
  MiniWindowSnapshot? _snapshot;
  MiniWindowPreferences _preferences = const MiniWindowPreferences();
  bool _loading = true;
  bool _expandedTimers = false;
  Size? _appliedWindowSize;

  MiniWindowRepository get _repository => MiniWindowRepository(
    database: ref.read(appDatabaseProvider),
    userId: ref.read(currentDataOwnerProvider),
    tasks: ref.read(taskRepositoryProvider),
    courses: ref.read(courseRepositoryProvider),
    semesters: ref.read(semesterRepositoryProvider),
    schedule: ref.read(dayScheduleRepositoryProvider),
  );

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    final controller = await WindowController.fromCurrentEngine();
    await controller.setWindowMethodHandler((call) async {
      if (call.method == 'focusMini') {
        await windowManager.show();
        await windowManager.focus();
        return true;
      }
      return null;
    });
    await _setMainWindowCompanionState(isOpen: true);
    _preferences = await _repository.loadPreferences();
    await _applyWindowOptions();
    await _reload();
    // Refreshing widget state never focuses the window.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _reload());
  }

  Future<void> _applyWindowOptions() async {
    final size = _preferences.compact
        ? _compactSize
        : _normalSizeFor(_snapshot);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: size,
        minimumSize: size,
        maximumSize: size,
        title: 'Check D 悬浮组件',
        alwaysOnTop: true,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
    );
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(true);
    final restored = await _restorePosition(_preferences, size);
    if (!restored) await windowManager.setAlignment(Alignment.topRight);
    await windowManager.show();
    _appliedWindowSize = size;
  }

  Future<bool> _restorePosition(
    MiniWindowPreferences preferences,
    Size size,
  ) async {
    if (preferences.x == null || preferences.y == null) return false;
    final displays = await screenRetriever.getAllDisplays();
    final isVisible = displays.any((display) {
      final position = display.visiblePosition;
      final displaySize = display.visibleSize;
      if (position == null || displaySize == null) return false;
      return preferences.x! >= position.dx &&
          preferences.y! >= position.dy &&
          preferences.x! + size.width <= position.dx + displaySize.width &&
          preferences.y! + size.height <= position.dy + displaySize.height;
    });
    if (!isVisible) return false;
    await windowManager.setPosition(Offset(preferences.x!, preferences.y!));
    return true;
  }

  Future<void> _reload() async {
    try {
      final snapshot = await _repository.load();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _loading = false;
        });
      }
      if (!_preferences.compact) {
        await _applyNormalHeight(snapshot);
      }
    } on Object {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _notifyMain() async {
    try {
      await miniWindowChannel.invokeMethod<void>('refreshMain');
    } on Object {
      // Polling remains the fallback when the main window is already closed.
    }
  }

  Future<void> _setMainWindowCompanionState({required bool isOpen}) async {
    try {
      await miniWindowChannel.invokeMethod<void>(
        isOpen ? 'floatingWidgetOpened' : 'floatingWidgetClosed',
      );
    } on Object {
      // The primary window may already be unavailable while this child closes.
    }
  }

  Future<void> _toggleCompact() async {
    final compact = !_preferences.compact;
    final size = compact ? _compactSize : _normalSizeFor(_snapshot);
    setState(() => _preferences = _preferences.copyWith(compact: compact));
    await _repository.savePreferences(_preferences);
    await _applyWindowSize(size);
  }

  Future<void> _toggleTimerExpansion() async {
    setState(() => _expandedTimers = !_expandedTimers);
    final snapshot = _snapshot;
    if (snapshot != null && !_preferences.compact) {
      await _applyNormalHeight(snapshot);
    }
  }

  Size _normalSizeFor(MiniWindowSnapshot? snapshot) {
    if (snapshot == null) return const Size(_normalWidth, _normalMinHeight);
    final visibleTimerCount = _expandedTimers || snapshot.timers.length <= 3
        ? snapshot.timers.length
        : 3;
    final nowHeight = snapshot.isIdle
        ? 34.0
        : snapshot.currentCourses.length * 82.0 +
              visibleTimerCount * 64.0 +
              (snapshot.timers.length > 3 ? 34.0 : 0);
    final nextHeight = (snapshot.nextCourse == null ? 0.0 : 62.0) +
        (snapshot.pendingItems.isEmpty
            ? (snapshot.nextCourse == null ? 28.0 : 0.0)
            : 38.0 + snapshot.pendingItems.take(2).length * 24.0);
    final height = (56 + 28 + nowHeight + 18 + 28 + nextHeight + 18 + 28 + 54)
        .clamp(_normalMinHeight, _normalMaxHeight)
        .toDouble();
    return Size(_normalWidth, height);
  }

  Future<void> _applyNormalHeight(MiniWindowSnapshot snapshot) async {
    final size = _normalSizeFor(snapshot);
    if (_appliedWindowSize == size) return;
    await _applyWindowSize(size);
  }

  Future<void> _applyWindowSize(Size size) async {
    final previous = _appliedWindowSize;
    final growing = previous == null || size.height > previous.height;
    if (growing) {
      await windowManager.setMaximumSize(size);
      await windowManager.setMinimumSize(size);
    } else {
      await windowManager.setMinimumSize(size);
      await windowManager.setMaximumSize(size);
    }
    await windowManager.setSize(size);
    _appliedWindowSize = size;
    await _keepWindowVisible(size);
  }

  Future<void> _keepWindowVisible(Size size) async {
    final current = await windowManager.getPosition();
    final displays = await screenRetriever.getAllDisplays();
    for (final display in displays) {
      final origin = display.visiblePosition;
      final displaySize = display.visibleSize;
      if (origin == null || displaySize == null) continue;
      final isOnDisplay = current.dx >= origin.dx - size.width &&
          current.dx <= origin.dx + displaySize.width &&
          current.dy >= origin.dy - size.height &&
          current.dy <= origin.dy + displaySize.height;
      if (!isOnDisplay) continue;
      final x = current.dx
          .clamp(origin.dx, origin.dx + displaySize.width - size.width)
          .toDouble();
      final y = current.dy
          .clamp(origin.dy, origin.dy + displaySize.height - size.height)
          .toDouble();
      if (x != current.dx || y != current.dy) {
        await windowManager.setPosition(Offset(x, y));
      }
      return;
    }
    await windowManager.setAlignment(Alignment.topRight);
  }

  Future<void> _changeTimer(MiniTimerItem item) async {
    if (item.kind == MiniTimerKind.task) {
      final repository = ref.read(taskRepositoryProvider);
      if (item.status == TimerStatus.running) {
        await repository.pauseTimer(item.id);
      }
      if (item.status == TimerStatus.paused) {
        await repository.resumeTimer(item.id);
      }
    } else {
      final repository = ref.read(dayScheduleRepositoryProvider);
      if (item.status == TimerStatus.running) {
        await repository.pauseAdHocTimer(item.id);
      }
      if (item.status == TimerStatus.paused) {
        await repository.resumeAdHocTimer(item.id);
      }
    }
    await _notifyMain();
    await _reload();
  }

  Future<void> _openMain() => miniWindowChannel.invokeMethod<void>('openMain');

  @override
  void onWindowMoved() {
    _positionDebounce?.cancel();
    _positionDebounce = Timer(const Duration(milliseconds: 250), () async {
      final position = await windowManager.getPosition();
      _preferences = _preferences.copyWith(x: position.dx, y: position.dy);
      await _repository.savePreferences(_preferences);
    });
  }

  @override
  void onWindowClose() {
    unawaited(_setMainWindowCompanionState(isOpen: false));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _positionDebounce?.cancel();
    unawaited(_setMainWindowCompanionState(isOpen: false));
    windowManager.removeListener(this);
    miniWindowChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final body = _loading || snapshot == null
        ? const Center(child: CircularProgressIndicator())
        : _preferences.compact
        ? _CompactContent(snapshot: snapshot, onExpand: _toggleCompact)
        : _NormalContent(
            snapshot: snapshot,
            expandedTimers: _expandedTimers,
            onToggleTimers: _toggleTimerExpansion,
            onCompact: _toggleCompact,
            onTimerAction: _changeTimer,
            onOpenMain: _openMain,
            onClose: windowManager.close,
          );
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: body),
    );
  }
}

class _CompactContent extends StatelessWidget {
  const _CompactContent({required this.snapshot, required this.onExpand});
  final MiniWindowSnapshot snapshot;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final running = snapshot.runningTimers;
    final course = snapshot.currentCourses.firstOrNull;
    final courseText = course == null
        ? null
        : '${course.title} · ${course.phase == MiniCoursePhase.active ? '上课中' : '课间'}';
    final timerText = running.length == 1
        ? '${running.first.title} · ${_duration(running.first.elapsedSeconds)}'
        : running.length > 1
        ? '${running.length}项进行中 · 最长${_duration(running.first.elapsedSeconds)}'
        : snapshot.pausedTimers.isNotEmpty
        ? '${snapshot.pausedTimers.length}项已暂停'
        : null;
    final text = switch ((courseText, timerText)) {
      (final String course, final String timer) => '$course\n$timer',
      (final String course, null) => course,
      (null, final String timer) => timer,
      (null, null) =>
        snapshot.nextCourse == null
            ? '当前没有进行中的事项'
            : '下一节：${snapshot.nextCourse!.title} · ${_formatMinute(snapshot.nextCourse!.startMinute)}',
    };
    return InkWell(
      onTap: onExpand,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
      ),
    );
  }
}

class _NormalContent extends StatelessWidget {
  const _NormalContent({
    required this.snapshot,
    required this.expandedTimers,
    required this.onToggleTimers,
    required this.onCompact,
    required this.onTimerAction,
    required this.onOpenMain,
    required this.onClose,
  });
  final MiniWindowSnapshot snapshot;
  final bool expandedTimers;
  final VoidCallback onToggleTimers;
  final VoidCallback onCompact;
  final ValueChanged<MiniTimerItem> onTimerAction;
  final VoidCallback onOpenMain;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final visibleTimers = expandedTimers || snapshot.timers.length <= 3
        ? snapshot.timers
        : snapshot.timers.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetHeader(
            now: snapshot.now,
            onCompact: onCompact,
            onOpenMain: onOpenMain,
            onClose: onClose,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionLabel('现在'),
                  if (snapshot.isIdle)
                    const _QuietText('当前没有进行中的课程或计时事项')
                  else ...[
                    for (final course in snapshot.currentCourses)
                      _CourseCard(course: course, onOpenMain: onOpenMain),
                    for (final timer in visibleTimers)
                      _TimerRow(
                        timer: timer,
                        onAction: () => onTimerAction(timer),
                        onOpenMain: onOpenMain,
                      ),
                    if (snapshot.timers.length > 3)
                      TextButton(
                        onPressed: onToggleTimers,
                        child: Text(
                          expandedTimers
                              ? '收起计时事项'
                              : '还有 ${snapshot.timers.length - 3} 项进行中',
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  const _SectionLabel('接下来'),
                  if (snapshot.nextCourse != null)
                    _NextCourse(
                      course: snapshot.nextCourse!,
                      onOpenMain: onOpenMain,
                    ),
                  if (snapshot.pendingItems.isNotEmpty)
                    _PendingItems(
                      items: snapshot.pendingItems.take(2).toList(),
                      hiddenCount: snapshot.pendingItems.length - 2,
                      onOpenMain: onOpenMain,
                    ),
                  if (snapshot.nextCourse == null &&
                      snapshot.pendingItems.isEmpty)
                    const _QuietText('今天暂时没有下一项安排'),
                  const SizedBox(height: 12),
                  const _SectionLabel('今天'),
                  _TodaySummary(snapshot: snapshot),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetHeader extends StatelessWidget {
  const _WidgetHeader({
    required this.now,
    required this.onCompact,
    required this.onOpenMain,
    required this.onClose,
  });
  final DateTime now;
  final VoidCallback onCompact;
  final VoidCallback onOpenMain;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: DragToMoveArea(
          child: InkWell(
            onTap: onOpenMain,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Check D',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _clock(now),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      IconButton(
        onPressed: onCompact,
        icon: const Icon(Icons.unfold_less_rounded, size: 19),
        tooltip: '收起为状态摘要',
      ),
      IconButton(
        onPressed: onClose,
        icon: const Icon(Icons.close_rounded, size: 19),
        tooltip: '关闭悬浮组件',
      ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
  );
}

class _QuietText extends StatelessWidget {
  const _QuietText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(color: AppColors.muted)),
  );
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.onOpenMain});
  final MiniCourseItem course;
  final VoidCallback onOpenMain;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: InkWell(
      onTap: onOpenMain,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    course.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  course.phase == MiniCoursePhase.breakTime ? '课间休息' : '上课中',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              course.phase == MiniCoursePhase.breakTime &&
                      course.nextSegmentMinute != null
                  ? '${_formatMinute(course.startMinute)}–${_formatMinute(course.endMinute)} · ${_formatMinute(course.nextSegmentMinute!)}继续'
                  : '${_formatMinute(course.startMinute)}–${_formatMinute(course.endMinute)}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            _CourseProgress(course: course),
          ],
        ),
      ),
    ),
  );
}

class _CourseProgress extends StatelessWidget {
  const _CourseProgress({required this.course});
  final MiniCourseItem course;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final phase in course.timing.phases)
        Expanded(
          flex: (phase.endMinute - phase.startMinute).clamp(1, 24 * 60),
          child: Container(
            height: 6,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: phase.kind.name == 'breakTime'
                  ? AppColors.blueMist.withValues(alpha: .35)
                  : AppColors.primary.withValues(alpha: .45),
            ),
          ),
        ),
    ],
  );
}

class _TimerRow extends StatefulWidget {
  const _TimerRow({
    required this.timer,
    required this.onAction,
    required this.onOpenMain,
  });
  final MiniTimerItem timer;
  final VoidCallback onAction;
  final VoidCallback onOpenMain;
  @override
  State<_TimerRow> createState() => _TimerRowState();
}

class _TimerRowState extends State<_TimerRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final timer = widget.timer;
    final action = timer.hoverAction;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          onTap: widget.onOpenMain,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  timer.status == TimerStatus.running
                      ? Icons.play_circle_fill_rounded
                      : Icons.pause_circle_outline_rounded,
                  color: timer.status == TimerStatus.running
                      ? AppColors.primary
                      : AppColors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        timer.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        timer.status == TimerStatus.running
                            ? '${_duration(timer.elapsedSeconds)}${timer.targetSeconds == null ? '' : ' / ${_duration(timer.targetSeconds!)}'}'
                            : '已暂停 · ${_duration(timer.elapsedSeconds)}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: _hovered && action != null ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: IgnorePointer(
                    ignoring: !_hovered || action == null,
                    child: TextButton(
                      onPressed: widget.onAction,
                      child: Text(
                        action == MiniTimerQuickAction.pause ? '暂停' : '继续',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextCourse extends StatelessWidget {
  const _NextCourse({required this.course, required this.onOpenMain});
  final MiniCourseItem course;
  final VoidCallback onOpenMain;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      onTap: onOpenMain,
      dense: true,
      leading: const Icon(Icons.school_outlined, color: AppColors.blueMist),
      title: Text(course.title),
      subtitle: Text(
        _isToday(course.date)
            ? _formatMinute(course.startMinute)
            : '明天 ${_formatMinute(course.startMinute)}',
      ),
    ),
  );
}

class _PendingItems extends StatelessWidget {
  const _PendingItems({
    required this.items,
    required this.hiddenCount,
    required this.onOpenMain,
  });
  final List<MiniPendingItem> items;
  final int hiddenCount;
  final VoidCallback onOpenMain;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: InkWell(
      onTap: onOpenMain,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.circle_outlined,
                      size: 16,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.targetSeconds != null)
                      Text(
                        _duration(item.targetSeconds!),
                        style: const TextStyle(color: AppColors.muted),
                      ),
                  ],
                ),
              ),
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '还有 $hiddenCount 项待完成',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.snapshot});
  final MiniWindowSnapshot snapshot;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        snapshot.totalTaskCount == 0
            ? '今天还没有需要完成的事项'
            : '${snapshot.completedTaskCount} / ${snapshot.totalTaskCount} 已完成',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

String _duration(int seconds) {
  final value = seconds.clamp(0, 1 << 31);
  final hours = value ~/ 3600;
  final minutes = value % 3600 ~/ 60;
  final rest = value % 60;
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}'
      : '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

String _formatMinute(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
String _clock(DateTime now) => _formatMinute(now.hour * 60 + now.minute);
bool _isToday(DateTime value) {
  final now = DateTime.now();
  return value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
}
