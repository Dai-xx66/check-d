import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum MascotState {
  idle,
  encouraging,
  happy,
  celebrating,
  resting,
  writing,
  working,
}

/// Stable presentation states used by Check D v1. Feature code selects a
/// semantic state; the asset treatment stays contained in this widget.
enum SheepState { idle, focus, paused, course, breakTime, complete }

abstract final class MascotSize {
  static const double micro = 38;
  static const double xs = 46;
  static const double small = 50;
  static const double sm = 52;
  static const double compact = 54;
  static const double md = 64;
  static const double standard = 72;
  static const double compactLarge = 78;
  static const double card = 82;
  static const double lg = 92;
  static const double sidebar = 108;
  static const double hero = 116;
  static const double feature = 126;
  static const double heroLarge = 164;
}

const checkDSheepFallbackAsset = 'assets/images/pink_lamb_piano.png';

const checkDSheepAssets = <SheepState, String>{
  SheepState.idle: 'assets/images/sheep_idle.png',
  SheepState.focus: 'assets/images/sheep_focus.png',
  SheepState.paused: 'assets/images/sheep_paused.png',
  SheepState.course: 'assets/images/sheep_course.png',
  SheepState.breakTime: 'assets/images/sheep_break.png',
  SheepState.complete: 'assets/images/sheep_complete.png',
};

String sheepAssetFor(SheepState state) => checkDSheepAssets[state]!;

SheepState resolveCheckDSheepState({
  bool hasCurrentCourse = false,
  bool isCourseBreak = false,
  bool hasRunningTimer = false,
  bool hasPausedTimer = false,
  bool allTasksComplete = false,
}) {
  if (hasCurrentCourse) {
    return isCourseBreak ? SheepState.breakTime : SheepState.course;
  }
  if (hasRunningTimer) return SheepState.focus;
  if (hasPausedTimer) return SheepState.paused;
  if (allTasksComplete) return SheepState.complete;
  return SheepState.idle;
}

class CheckDSheep extends StatefulWidget {
  const CheckDSheep({
    required this.state,
    this.size = MascotSize.standard,
    this.compact = false,
    this.framed = true,
    this.assetOverrideForTesting,
    super.key,
  });

  final SheepState state;
  final double size;
  final bool compact;
  final bool framed;
  @visibleForTesting
  final String? assetOverrideForTesting;

  @override
  State<CheckDSheep> createState() => _CheckDSheepState();
}

class _CheckDSheepState extends State<CheckDSheep>
    with TickerProviderStateMixin {
  late final AnimationController _breathing;
  late final AnimationController _feedback;
  bool _reducedMotion = false;
  bool _motionInitialized = false;

  @override
  void initState() {
    super.initState();
    _breathing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _feedback = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations == true;
    if (!_motionInitialized || reducedMotion != _reducedMotion) {
      _motionInitialized = true;
      _reducedMotion = reducedMotion;
      _startStateMotion();
    }
  }

  @override
  void didUpdateWidget(covariant CheckDSheep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _startStateMotion();
  }

  void _startStateMotion() {
    _breathing.stop();
    _breathing.value = 0;
    _feedback.stop();
    _feedback.value = 0;
    if (_reducedMotion) return;
    if (widget.state != SheepState.paused &&
        widget.state != SheepState.complete) {
      _breathing.duration = switch (widget.state) {
        SheepState.course => const Duration(milliseconds: 1900),
        SheepState.focus => const Duration(milliseconds: 2300),
        SheepState.breakTime => const Duration(milliseconds: 3200),
        _ => const Duration(milliseconds: 2800),
      };
      _breathing.forward().then((_) {
        if (mounted &&
            widget.state != SheepState.paused &&
            widget.state != SheepState.complete &&
            !_reducedMotion) {
          _breathing.reverse();
        }
      });
    }
    if (widget.state == SheepState.complete) _feedback.forward();
  }

  @override
  void dispose() {
    _breathing.dispose();
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _sheepPresentation(widget.state);
    final artwork = Image.asset(
      widget.assetOverrideForTesting ?? sheepAssetFor(widget.state),
      key: ValueKey('check-d-sheep-${widget.state.name}'),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Image.asset(
        checkDSheepFallbackAsset,
        fit: BoxFit.contain,
      ),
    );
    final framedArtwork = widget.framed
        ? Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: presentation.tint,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    widget.compact ? widget.size * .11 : widget.size * .08,
                  ),
                  child: artwork,
                ),
              ),
              Positioned(
                right: -1,
                top: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(widget.compact ? 3 : 4),
                    child: Icon(
                      presentation.icon,
                      size: widget.compact
                          ? widget.size * .18
                          : widget.size * .2,
                      color: presentation.accent,
                    ),
                  ),
                ),
              ),
            ],
          )
        : Padding(
            padding: EdgeInsets.all(widget.compact ? widget.size * .02 : 0),
            child: artwork,
          );
    final switched = AnimatedSwitcher(
      duration: _reducedMotion ? AppMotion.quick : AppMotion.emphasis,
      reverseDuration: _reducedMotion ? AppMotion.quick : AppMotion.standard,
      switchInCurve: AppMotion.curve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: _reducedMotion
            ? child
            : SlideTransition(
                position: Tween(
                  begin: const Offset(0, .045),
                  end: Offset.zero,
                ).animate(animation),
                child: ScaleTransition(
                  scale: Tween(begin: .96, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
      ),
      child: KeyedSubtree(key: ValueKey(widget.state), child: framedArtwork),
    );
    final animated = _reducedMotion
        ? switched
        : AnimatedBuilder(
            animation: Listenable.merge([_breathing, _feedback]),
            child: switched,
            builder: (context, child) {
              final breathStrength = switch (widget.state) {
                SheepState.idle => .015,
                SheepState.focus => .008,
                SheepState.course => .01,
                SheepState.breakTime => .012,
                _ => 0.0,
              };
              final breath = _breathing.value * breathStrength;
              final sway = widget.state == SheepState.course
                  ? _breathing.value * 1.2
                  : 0.0;
              final feedback = Curves.easeOutCubic.transform(_feedback.value);
              final jump = widget.state == SheepState.complete
                  ? -7 * (1 - (2 * feedback - 1).abs())
                  : 0.0;
              final pop = widget.state == SheepState.complete
                  ? .035 * (1 - feedback)
                  : 0.0;
              return Transform.translate(
                offset: Offset(sway, jump),
                child: Transform.scale(scale: 1 + breath + pop, child: child),
              );
            },
          );
    return Semantics(
      image: true,
      label: '小羊状态：${presentation.label}',
      child: SizedBox.square(dimension: widget.size, child: animated),
    );
  }
}

({String label, Color tint, Color accent, IconData icon}) _sheepPresentation(
  SheepState state,
) => switch (state) {
  SheepState.idle => (
    label: '空闲',
    tint: AppColors.cream,
    accent: AppColors.orange,
    icon: Icons.favorite_outline_rounded,
  ),
  SheepState.focus => (
    label: '专注',
    tint: AppColors.blush,
    accent: AppColors.primary,
    icon: Icons.auto_awesome_rounded,
  ),
  SheepState.paused => (
    label: '暂停',
    tint: AppColors.lavender,
    accent: AppColors.purple,
    icon: Icons.coffee_rounded,
  ),
  SheepState.course => (
    label: '上课',
    tint: AppColors.blueMist,
    accent: AppColors.accentBlue,
    icon: Icons.menu_book_rounded,
  ),
  SheepState.breakTime => (
    label: '课间',
    tint: AppColors.mint,
    accent: AppColors.green,
    icon: Icons.spa_outlined,
  ),
  SheepState.complete => (
    label: '完成',
    tint: AppColors.blush,
    accent: AppColors.green,
    icon: Icons.check_rounded,
  ),
};

/// A single presentation entry point for the app's original pink lamb asset.
/// State-specific assets can replace this treatment without changing pages.
class MascotWidget extends StatelessWidget {
  const MascotWidget({
    required this.state,
    this.size = 88,
    this.compact = false,
    super.key,
  });

  final MascotState state;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final celebration = state == MascotState.celebrating;
    final tint = switch (state) {
      MascotState.resting => AppColors.lavender,
      MascotState.working || MascotState.writing => AppColors.blueMist,
      MascotState.happy || MascotState.celebrating => AppColors.blush,
      _ => AppColors.cream,
    };
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: tint,
              shape: BoxShape.circle,
              boxShadow: const [AppShadows.soft],
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? 7 : 5),
              child: Image.asset(
                'assets/images/pink_lamb_piano.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          if (celebration) ...[
            const Positioned(
              top: -4,
              left: 0,
              child: Icon(
                Icons.star_rounded,
                size: 17,
                color: AppColors.creamYellow,
              ),
            ),
            const Positioned(
              right: -2,
              top: 10,
              child: Icon(
                Icons.music_note_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ),
          ],
          if (state == MascotState.encouraging)
            const Positioned(
              right: 1,
              bottom: 2,
              child: Icon(
                Icons.favorite_rounded,
                size: 15,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }
}

class MascotEmptyState extends StatelessWidget {
  const MascotEmptyState({
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
    child: Row(
      children: [
        const CheckDSheep(
          state: SheepState.idle,
          size: MascotSize.xs,
          compact: true,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                message,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}
