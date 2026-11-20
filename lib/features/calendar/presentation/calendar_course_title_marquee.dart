import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Reveals an overflowing course title without changing its timetable slot.
class CalendarCourseTitleMarquee extends StatefulWidget {
  const CalendarCourseTitleMarquee({
    required this.text,
    required this.style,
    super.key,
  });

  final String text;
  final TextStyle style;

  @override
  State<CalendarCourseTitleMarquee> createState() =>
      _CalendarCourseTitleMarqueeState();
}

class _CalendarCourseTitleMarqueeState extends State<CalendarCourseTitleMarquee>
    with SingleTickerProviderStateMixin {
  static const _headPause = Duration(milliseconds: 1400);
  static const _tailPause = Duration(milliseconds: 1200);
  static const _pixelsPerSecond = 20.0;

  late final AnimationController _controller;
  Animation<double> _position = const AlwaysStoppedAnimation(0);
  Object? _requestedConfiguration;
  Object? _appliedConfiguration;
  var _configurationRevision = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  void _configureAfterLayout(
    Object configuration, {
    required bool animate,
    required double distance,
  }) {
    if (_requestedConfiguration == configuration) return;
    _requestedConfiguration = configuration;
    final revision = ++_configurationRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _configurationRevision) return;
      _controller.stop();
      _controller.value = 0;
      _appliedConfiguration = configuration;
      if (!animate) {
        _position = const AlwaysStoppedAnimation(0);
        return;
      }

      final travel = Duration(
        microseconds: math.max(
          1,
          (distance / _pixelsPerSecond * Duration.microsecondsPerSecond)
              .round(),
        ),
      );
      _position = TweenSequence<double>([
        TweenSequenceItem(
          tween: ConstantTween<double>(0),
          weight: _headPause.inMicroseconds.toDouble(),
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: distance),
          weight: travel.inMicroseconds.toDouble(),
        ),
        TweenSequenceItem(
          tween: ConstantTween<double>(distance),
          weight: _tailPause.inMicroseconds.toDouble(),
        ),
      ]).animate(_controller);
      _controller.duration = _headPause + travel + _tailPause;
      _controller.repeat();
    });
  }

  @override
  void dispose() {
    _configurationRevision++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    final style = defaults.style.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final allowMotion =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          textHeightBehavior: defaults.textHeightBehavior,
          maxLines: 1,
        )..layout();
        final textWidth = painter.width;
        final textHeight = painter.height;
        painter.dispose();

        final width = constraints.maxWidth;
        final bounded = constraints.hasBoundedWidth && width > 0;
        final distance = bounded ? math.max(0.0, textWidth - width) : 0.0;
        final animate = allowMotion && distance > .5;
        final configuration = (
          widget.text,
          style,
          scaler,
          direction,
          locale,
          defaults.textHeightBehavior,
          width,
          textWidth,
          textHeight,
          animate,
        );
        _configureAfterLayout(
          configuration,
          animate: animate,
          distance: distance,
        );

        Widget title({required TextOverflow overflow}) => Text(
          widget.text,
          style: style,
          textScaler: scaler,
          textDirection: direction,
          locale: locale,
          textHeightBehavior: defaults.textHeightBehavior,
          maxLines: 1,
          softWrap: false,
          overflow: overflow,
        );

        if (!animate) return title(overflow: TextOverflow.ellipsis);

        return SizedBox(
          width: width,
          height: constraints.hasBoundedHeight
              ? math.min(textHeight, constraints.maxHeight)
              : textHeight,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              child: OverflowBox(
                alignment: AlignmentDirectional.topStart,
                minWidth: textWidth,
                maxWidth: textWidth,
                child: title(overflow: TextOverflow.visible),
              ),
              builder: (context, child) {
                final offset = _appliedConfiguration == configuration
                    ? _position.value
                    : 0.0;
                return Transform.translate(
                  offset: Offset(
                    direction == TextDirection.ltr ? -offset : offset,
                    0,
                  ),
                  child: child,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
