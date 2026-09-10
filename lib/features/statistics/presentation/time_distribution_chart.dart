import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/statistics_models.dart';

String timeLabel(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours小时$rest分';
}

class StatisticsTrendChart extends StatelessWidget {
  const StatisticsTrendChart({
    required this.report,
    required this.period,
    super.key,
  });

  final StatisticsReport report;
  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context) => switch (period) {
    StatisticsPeriod.month => MonthlyFocusHeatmap(report: report),
    StatisticsPeriod.semester => SemesterFocusLineChart(report: report),
    StatisticsPeriod.week || StatisticsPeriod.year => FocusBarChart(
      report: report,
      compactLabels: period == StatisticsPeriod.year,
    ),
    StatisticsPeriod.day => FocusBarChart(report: report),
  };
}

class FocusBarChart extends StatelessWidget {
  const FocusBarChart({
    required this.report,
    this.compactLabels = false,
    super.key,
  });

  final StatisticsReport report;
  final bool compactLabels;

  @override
  Widget build(BuildContext context) {
    final maximum = report.buckets.fold<int>(
      0,
      (value, bucket) => math.max(value, bucket.focusSeconds),
    );
    return SizedBox(
      height: 250,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _YAxis(maximum: maximum),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final minimumWidth =
                    report.buckets.length * (compactLabels ? 46.0 : 54.0);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(constraints.maxWidth, minimumWidth),
                    child: Stack(
                      children: [
                        const Positioned.fill(child: _ChartGrid()),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (
                              var index = 0;
                              index < report.buckets.length;
                              index++
                            )
                              Expanded(
                                child: Tooltip(
                                  message:
                                      '${_bucketDate(report.buckets[index])}\n${timeLabel(report.buckets[index].focusSeconds)}',
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.bottomCenter,
                                            child: FractionallySizedBox(
                                              heightFactor: maximum == 0
                                                  ? 0
                                                  : report
                                                            .buckets[index]
                                                            .focusSeconds /
                                                        maximum,
                                              child: Container(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxWidth: 34,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _barColor(index),
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                        top: Radius.circular(9),
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          report.buckets[index].label,
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _bucketDate(TimeBucket bucket) =>
      DateFormat('M月d日').format(bucket.start);

  static Color _barColor(int index) => const [
    AppColors.primary,
    AppColors.purple,
    AppColors.green,
    AppColors.orange,
    AppColors.accentBlue,
  ][index % 5];
}

class MonthlyFocusHeatmap extends StatelessWidget {
  const MonthlyFocusHeatmap({required this.report, super.key});

  final StatisticsReport report;

  @override
  Widget build(BuildContext context) {
    final offset = report.range.start.weekday - 1;
    final cells = offset + report.buckets.length;
    final rows = (cells / 7).ceil();
    return Column(
      children: [
        Row(
          children: [
            for (final label in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
            childAspectRatio: 1.2,
          ),
          itemCount: rows * 7,
          itemBuilder: (context, index) {
            final bucketIndex = index - offset;
            if (bucketIndex < 0 || bucketIndex >= report.buckets.length) {
              return const SizedBox.shrink();
            }
            final bucket = report.buckets[bucketIndex];
            return Tooltip(
              message:
                  '${DateFormat('M月d日').format(bucket.start)}\n${timeLabel(bucket.focusSeconds)}',
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _heatColor(bucket.focusSeconds),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFE8EBEF)),
                ),
                child: Text(
                  '${bucket.start.day}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: bucket.focusSeconds >= 4 * 3600
                        ? Colors.white
                        : AppColors.ink,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        const Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _HeatLegend(color: Color(0xFFF8EFF2), label: '<1h'),
            _HeatLegend(color: Color(0xFFF9DCE5), label: '1–2h'),
            _HeatLegend(color: Color(0xFFF4A8BC), label: '2–4h'),
            _HeatLegend(color: AppColors.primaryStrong, label: '>4h'),
          ],
        ),
      ],
    );
  }

  Color _heatColor(int seconds) {
    if (seconds == 0) return const Color(0xFFFFFBF7);
    if (seconds < 3600) return const Color(0xFFF8EFF2);
    if (seconds < 2 * 3600) return const Color(0xFFF9DCE5);
    if (seconds < 4 * 3600) return const Color(0xFFF4A8BC);
    return AppColors.primaryStrong;
  }
}

class SemesterFocusLineChart extends StatelessWidget {
  const SemesterFocusLineChart({required this.report, super.key});

  final StatisticsReport report;

  @override
  Widget build(BuildContext context) {
    final maximum = report.buckets.fold<int>(
      0,
      (value, bucket) => math.max(value, bucket.focusSeconds),
    );
    final width = math.max(620.0, report.buckets.length * 54.0);
    return SizedBox(
      height: 250,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _YAxis(maximum: maximum),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _LineChartPainter(
                          values: report.buckets
                              .map((b) => b.focusSeconds)
                              .toList(),
                          maximum: maximum,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final bucket in report.buckets)
                          Expanded(
                            child: Tooltip(
                              message:
                                  '${bucket.label}\n${timeLabel(bucket.focusSeconds)}',
                              child: Text(
                                bucket.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.values, required this.maximum});

  final List<int> values;
  final int maximum;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = AppColors.border;
    for (final y in [0.0, size.height / 2, size.height]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty || maximum == 0) return;
    final path = Path();
    final fill = Path();
    final step = values.length == 1 ? 0.0 : size.width / (values.length - 1);
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        i * step,
        size.height - (values[i] / maximum * (size.height - 12)),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
        fill
          ..moveTo(point.dx, size.height)
          ..lineTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
        fill.lineTo(point.dx, point.dy);
      }
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = AppColors.primary.withValues(alpha: .14),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primaryStrong
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        i * step,
        size.height - (values[i] / maximum * (size.height - 12)),
      );
      canvas.drawCircle(point, 4, Paint()..color = Colors.white);
      canvas.drawCircle(
        point,
        4,
        Paint()
          ..color = AppColors.primaryStrong
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.maximum != maximum;
}

class _ChartGrid extends StatelessWidget {
  const _ChartGrid();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [Divider(height: 1), Divider(height: 1), Divider(height: 1)],
  );
}

class _YAxis extends StatelessWidget {
  const _YAxis({required this.maximum});

  final int maximum;

  @override
  Widget build(BuildContext context) {
    final hours = math.max(1, (maximum / 3600).ceil());
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${hours}h'),
          Text('${(hours / 2).toStringAsFixed(hours.isEven ? 0 : 1)}h'),
          const Text('0h'),
        ],
      ),
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
    ],
  );
}
