import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_header.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('M月d日 EEEE', 'zh_CN').format(DateTime.now());

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            sliver: SliverList.list(
              children: [
                PageHeader(title: '今日', subtitle: dateText),
                const SizedBox(height: 22),
                const _TodaySummary(),
                const SizedBox(height: 28),
                Text(
                  '长期任务',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const EmptyState(
                  icon: Icons.loop_rounded,
                  title: '还没有长期任务',
                  message: '从中央的“添加”入口创建第一个长期目标。',
                ),
                const SizedBox(height: 24),
                Text(
                  '单次事项提醒',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const EmptyState(
                  icon: Icons.event_note_outlined,
                  title: '今天没有单次事项',
                  message: '临时事项和重要日期会单独显示在这里。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: _Metric(label: '今日完成度', value: '0%'),
                ),
                Expanded(
                  child: _Metric(label: '已完成', value: '0'),
                ),
                Expanded(
                  child: _Metric(label: '计时时长', value: '0m'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                value: 0,
                minHeight: 8,
                color: AppColors.primary,
                backgroundColor: Color(0xFFE9EBEF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
