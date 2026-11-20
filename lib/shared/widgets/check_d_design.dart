import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum CheckDSurfaceLevel { plain, raised, glassSoft, glassFloating, glassActive }

enum CheckDIconType {
  today,
  calendar,
  statistics,
  profile,
  add,
  course,
  recurring,
  oneOff,
  timer,
  widget,
  settings,
  schedule,
  semester,
  tag,
  defaultItem,
  reminder,
  alarm,
  permission,
  appearance,
  mascot,
  backup,
  privacy,
  help,
  about,
  focus,
  completion,
  checkIn,
  streak,
  insight,
  back,
  forward,
  refresh,
}

abstract final class CheckDLayout {
  static const mobileBottomBarHeight = 74.0;
  static const mobileFloatingLayerGap = 12.0;

  static double mobileBottomNavigationExtent(BuildContext context) {
    return mobileBottomBarHeight + MediaQuery.viewPaddingOf(context).bottom;
  }
}

PageRoute<T> checkDPageRoute<T>({required WidgetBuilder builder}) =>
    PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionDuration: AppMotion.standard,
      reverseTransitionDuration: AppMotion.quick,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
          return child;
        }
        final eased = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: eased,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.018, 0),
              end: Offset.zero,
            ).animate(eased),
            child: child,
          ),
        );
      },
    );

class CheckDIcon extends StatelessWidget {
  const CheckDIcon(
    this.type, {
    this.size = 22,
    this.color,
    this.active = false,
    this.backing = false,
    this.semanticLabel,
    super.key,
  });

  final CheckDIconType type;
  final double size;
  final Color? color;
  final bool active;
  final bool backing;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? (active ? AppColors.primary : AppColors.muted);
    final icon = Icon(_iconFor(type), size: size, color: resolvedColor);
    final child = backing
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: resolvedColor.withValues(alpha: .11),
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: size + 20,
              child: Center(child: icon),
            ),
          )
        : icon;
    return Semantics(label: semanticLabel, image: false, child: child);
  }
}

IconData _iconFor(CheckDIconType type) => switch (type) {
  CheckDIconType.today => Icons.today_outlined,
  CheckDIconType.calendar => Icons.calendar_month_outlined,
  CheckDIconType.statistics => Icons.bar_chart_outlined,
  CheckDIconType.profile => Icons.person_outline_rounded,
  CheckDIconType.add => Icons.add_rounded,
  CheckDIconType.course => Icons.menu_book_outlined,
  CheckDIconType.recurring => Icons.repeat_rounded,
  CheckDIconType.oneOff => Icons.event_note_outlined,
  CheckDIconType.timer => Icons.timer_outlined,
  CheckDIconType.widget => Icons.desktop_windows_outlined,
  CheckDIconType.settings => Icons.settings_outlined,
  CheckDIconType.schedule => Icons.schedule_outlined,
  CheckDIconType.semester => Icons.school_outlined,
  CheckDIconType.tag => Icons.sell_outlined,
  CheckDIconType.defaultItem => Icons.tune_outlined,
  CheckDIconType.reminder => Icons.notifications_none_rounded,
  CheckDIconType.alarm => Icons.alarm_outlined,
  CheckDIconType.permission => Icons.verified_user_outlined,
  CheckDIconType.appearance => Icons.palette_outlined,
  CheckDIconType.mascot => Icons.pets_outlined,
  CheckDIconType.backup => Icons.cloud_upload_outlined,
  CheckDIconType.privacy => Icons.privacy_tip_outlined,
  CheckDIconType.help => Icons.help_outline_rounded,
  CheckDIconType.about => Icons.info_outline_rounded,
  CheckDIconType.focus => Icons.hourglass_bottom_rounded,
  CheckDIconType.completion => Icons.check_circle_outline_rounded,
  CheckDIconType.checkIn => Icons.event_available_outlined,
  CheckDIconType.streak => Icons.local_fire_department_outlined,
  CheckDIconType.insight => Icons.auto_awesome_outlined,
  CheckDIconType.back => Icons.chevron_left_rounded,
  CheckDIconType.forward => Icons.chevron_right_rounded,
  CheckDIconType.refresh => Icons.refresh_rounded,
};

/// Shared Check D v1 surface hierarchy. Blur is deliberately limited to the
/// three glass levels so ordinary content remains crisp and inexpensive.
class CheckDSurface extends StatelessWidget {
  const CheckDSurface({
    required this.child,
    this.level = CheckDSurfaceLevel.plain,
    this.padding,
    this.radius,
    this.color,
    this.borderColor,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  final Widget child;
  final CheckDSurfaceLevel level;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? radius;
  final Color? color;
  final Color? borderColor;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final resolvedRadius = radius ?? _radiusFor(level);
    final surfaceDecoration = BoxDecoration(
      color: color ?? _colorFor(level),
      borderRadius: resolvedRadius,
      border: Border.all(color: borderColor ?? _borderFor(level), width: 1),
    );
    final content = AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.standard),
      curve: AppMotion.curve,
      decoration: surfaceDecoration,
      padding: padding,
      child: CustomPaint(
        foregroundPainter: _isGlass(level)
            ? _GlassRimPainter(radius: resolvedRadius, color: AppColors.border)
            : null,
        child: child,
      ),
    );

    return AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.standard),
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        borderRadius: resolvedRadius,
        boxShadow: _shadowsFor(level),
      ),
      child: ClipRRect(
        borderRadius: resolvedRadius,
        clipBehavior: clipBehavior,
        child: _isGlass(level)
            ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _blurFor(level),
                  sigmaY: _blurFor(level),
                ),
                child: content,
              )
            : content,
      ),
    );
  }
}

double _blurFor(CheckDSurfaceLevel level) => switch (level) {
  CheckDSurfaceLevel.glassFloating => 12,
  CheckDSurfaceLevel.glassActive => 10,
  CheckDSurfaceLevel.glassSoft => 8,
  _ => 0,
};

class CheckDSectionTitle extends StatelessWidget {
  const CheckDSectionTitle({
    required this.title,
    this.count,
    this.trailing,
    super.key,
  });

  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (count != null) ...[
              const SizedBox(width: 7),
              Text(
                '$count',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class CheckDStatusDot extends StatelessWidget {
  const CheckDStatusDot({required this.color, this.size = 7, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: SizedBox.square(dimension: size),
  );
}

class CheckDPressable extends StatefulWidget {
  const CheckDPressable({
    required this.child,
    required this.onTap,
    this.pressedScale = .98,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final BorderRadius? borderRadius;

  @override
  State<CheckDPressable> createState() => _CheckDPressableState();
}

class CheckDHoverLift extends StatefulWidget {
  const CheckDHoverLift({required this.child, this.radius, super.key});

  final Widget child;
  final BorderRadius? radius;

  @override
  State<CheckDHoverLift> createState() => _CheckDHoverLiftState();
}

class _CheckDHoverLiftState extends State<CheckDHoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations == true;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.quick),
        curve: AppMotion.curve,
        transform: Matrix4.translationValues(
          0,
          !reducedMotion && _hovered ? -1.5 : 0,
          0,
        ),
        decoration: BoxDecoration(
          borderRadius: widget.radius ?? const BorderRadius.all(AppRadius.card),
          boxShadow: _hovered
              ? const [
                  BoxShadow(
                    color: Color(0x1040252B),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.radius, required this.color});

  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()..addRRect(radius.toRRect(rect).deflate(.55));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color,
          color.withValues(alpha: .35),
          color.withValues(alpha: .15),
        ],
        stops: [0, .62, 1],
      ).createShader(rect);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.color != color;
}

class _CheckDPressableState extends State<CheckDPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations == true;
    return AnimatedOpacity(
      opacity: _pressed ? .94 : 1,
      duration: AppMotion.duration(context, AppMotion.quick),
      child: AnimatedScale(
        scale: reducedMotion || !_pressed ? 1 : widget.pressedScale,
        duration: AppMotion.duration(context, AppMotion.quick),
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: Material(
          color: Colors.transparent,
          borderRadius: widget.borderRadius,
          clipBehavior: widget.borderRadius == null
              ? Clip.none
              : Clip.antiAlias,
          child: InkWell(
            borderRadius: widget.borderRadius,
            onTap: widget.onTap,
            onTapDown: (_) => _setPressed(true),
            onTapCancel: () => _setPressed(false),
            onTapUp: (_) => _setPressed(false),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

bool _isGlass(CheckDSurfaceLevel level) => switch (level) {
  CheckDSurfaceLevel.glassSoft ||
  CheckDSurfaceLevel.glassFloating ||
  CheckDSurfaceLevel.glassActive => true,
  _ => false,
};

BorderRadius _radiusFor(CheckDSurfaceLevel level) =>
    BorderRadius.all(switch (level) {
      CheckDSurfaceLevel.glassFloating => AppRadius.sheet,
      CheckDSurfaceLevel.glassActive => AppRadius.importantCard,
      CheckDSurfaceLevel.glassSoft => AppRadius.importantCard,
      _ => AppRadius.card,
    });

Color _colorFor(CheckDSurfaceLevel level) => switch (level) {
  CheckDSurfaceLevel.plain => AppColors.surface,
  CheckDSurfaceLevel.raised => AppColors.surface,
  CheckDSurfaceLevel.glassSoft => AppColors.glassStrong,
  CheckDSurfaceLevel.glassFloating => AppColors.glassStrong,
  CheckDSurfaceLevel.glassActive => AppColors.blush,
};

Color _borderFor(CheckDSurfaceLevel level) => AppColors.border;

List<BoxShadow> _shadowsFor(CheckDSurfaceLevel level) => switch (level) {
  CheckDSurfaceLevel.plain => const [],
  CheckDSurfaceLevel.raised => [AppShadows.soft],
  CheckDSurfaceLevel.glassSoft => [AppShadows.soft],
  CheckDSurfaceLevel.glassFloating ||
  CheckDSurfaceLevel.glassActive => [AppShadows.glass],
};
