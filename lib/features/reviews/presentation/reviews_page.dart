import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_header.dart';
import '../../tasks/domain/task_models.dart';
import '../application/review_providers.dart';
import '../domain/review_models.dart';

class ReviewsPage extends ConsumerStatefulWidget {
  const ReviewsPage({super.key});

  @override
  ConsumerState<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends ConsumerState<ReviewsPage> {
  late ReviewType _type;
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    _type = ReviewType.day;
    _anchor = dateOnly(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final period = _periodFor(_type, _anchor);
    final review = ref.watch(reviewProvider(period));
    final snapshot = ref.watch(reviewSnapshotProvider(period));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              children: [
                const PageHeader(title: '复盘', subtitle: '把客观数据和主观感受放在一起'),
                const SizedBox(height: 20),
                SegmentedButton<ReviewType>(
                  segments: const [
                    ButtonSegment(value: ReviewType.day, label: Text('日复盘')),
                    ButtonSegment(value: ReviewType.week, label: Text('周复盘')),
                    ButtonSegment(value: ReviewType.month, label: Text('月复盘')),
                    ButtonSegment(value: ReviewType.year, label: Text('年复盘')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) =>
                      setState(() => _type = value.first),
                ),
                const SizedBox(height: 16),
                _PeriodBar(
                  label: _periodLabel(period),
                  onPrevious: () =>
                      setState(() => _anchor = _offset(_anchor, -1)),
                  onNext: () => setState(() => _anchor = _offset(_anchor, 1)),
                ),
                const SizedBox(height: 18),
                snapshot.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (error, stackTrace) => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('数据快照加载失败'),
                    ),
                  ),
                  data: (data) => _SnapshotCard(snapshot: data),
                ),
                const SizedBox(height: 16),
                review.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('复盘加载失败'),
                    ),
                  ),
                  data: (entry) => _ReviewCard(
                    review: entry,
                    onEdit: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) => ReviewEditorPage(period: period),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ReviewPeriod _periodFor(ReviewType type, DateTime anchor) {
    final day = dateOnly(anchor);
    return switch (type) {
      ReviewType.day => ReviewPeriod(type: type, startsOn: day, endsOn: day),
      ReviewType.week => ReviewPeriod(
        type: type,
        startsOn: day.subtract(Duration(days: day.weekday - 1)),
        endsOn: day.add(Duration(days: DateTime.sunday - day.weekday)),
      ),
      ReviewType.month => ReviewPeriod(
        type: type,
        startsOn: DateTime(day.year, day.month, 1),
        endsOn: DateTime(day.year, day.month + 1, 0),
      ),
      ReviewType.year => ReviewPeriod(
        type: type,
        startsOn: DateTime(day.year, 1, 1),
        endsOn: DateTime(day.year, 12, 31),
      ),
    };
  }

  DateTime _offset(DateTime anchor, int amount) => switch (_type) {
    ReviewType.day => anchor.add(Duration(days: amount)),
    ReviewType.week => anchor.add(Duration(days: 7 * amount)),
    ReviewType.month => DateTime(anchor.year, anchor.month + amount, 1),
    ReviewType.year => DateTime(anchor.year + amount, 1, 1),
  };

  String _periodLabel(ReviewPeriod period) => switch (period.type) {
    ReviewType.day => DateFormat('yyyy年M月d日', 'zh_CN').format(period.startsOn),
    ReviewType.week =>
      '${DateFormat('M月d日').format(period.startsOn)} - ${DateFormat('M月d日').format(period.endsOn)}',
    ReviewType.month => DateFormat('yyyy年M月', 'zh_CN').format(period.startsOn),
    ReviewType.year => '${period.startsOn.year} 年',
  };
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });
  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: '上一期',
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Expanded(
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      IconButton(
        tooltip: '下一期',
        onPressed: onNext,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ],
  );
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.snapshot});
  final ReviewSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('客观数据', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              _Metric(
                label: '完成任务',
                value: '${snapshot.completedCount}/${snapshot.dueCount}',
              ),
              _Metric(label: '完成率', value: '${snapshot.completionPercent}%'),
              _Metric(
                label: '计时时长',
                value: formatDuration(snapshot.timedSeconds),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.onEdit});
  final ReviewDetails? review;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    if (review == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.edit_note_outlined,
                size: 34,
                color: AppColors.primary,
              ),
              const SizedBox(height: 12),
              const Text(
                '这一期还没有复盘',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '记录发生的事、收获、改进方向和情绪。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('开始复盘'),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  _moodLabel(review!.mood),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '已完成复盘',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '编辑复盘',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            if (review!.happenedText != null)
              _Answer(label: '今日事', value: review!.happenedText!),
            if (review!.learnedText != null)
              _Answer(label: '今日得', value: review!.learnedText!),
            if (review!.improveText != null)
              _Answer(label: '今日改', value: review!.improveText!),
          ],
        ),
      ),
    );
  }

  String _moodLabel(int? mood) =>
      const {1: '😡', 2: '😟', 3: '😐', 4: '🙂', 5: '😄'}[mood] ?? '📝';
}

class _Answer extends StatelessWidget {
  const _Answer({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}

class ReviewEditorPage extends ConsumerStatefulWidget {
  const ReviewEditorPage({required this.period, super.key});
  final ReviewPeriod period;

  @override
  ConsumerState<ReviewEditorPage> createState() => _ReviewEditorPageState();
}

class _ReviewEditorPageState extends ConsumerState<ReviewEditorPage> {
  late final TextEditingController _happened;
  late final TextEditingController _learned;
  late final TextEditingController _improve;
  int? _mood;
  String? _loadedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _happened = TextEditingController();
    _learned = TextEditingController();
    _improve = TextEditingController();
  }

  @override
  void dispose() {
    _happened.dispose();
    _learned.dispose();
    _improve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(reviewProvider(widget.period));
    final snapshot = ref.watch(reviewSnapshotProvider(widget.period));
    review.whenData(_hydrate);
    return Scaffold(
      appBar: AppBar(
        title: const Text('填写复盘'),
        backgroundColor: AppColors.background,
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(snapshot.value),
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  snapshot.when(
                    loading: () => const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                    error: (error, stackTrace) => const SizedBox.shrink(),
                    data: (data) => _SnapshotCard(snapshot: data),
                  ),
                  const SizedBox(height: 16),
                  _PromptField(
                    controller: _happened,
                    title: '今日事',
                    question: '今天发生了什么？',
                  ),
                  const SizedBox(height: 16),
                  _PromptField(
                    controller: _learned,
                    title: '今日得',
                    question: '今天学到了什么？',
                  ),
                  const SizedBox(height: 16),
                  _PromptField(
                    controller: _improve,
                    title: '今日改',
                    question: '今天有哪些地方可以改进？',
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '今日情绪',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final item in const [
                                (1, '😡'),
                                (2, '😟'),
                                (3, '😐'),
                                (4, '🙂'),
                                (5, '😄'),
                              ])
                                ChoiceChip(
                                  label: Text(
                                    item.$2,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  selected: _mood == item.$1,
                                  onSelected: (_) =>
                                      setState(() => _mood = item.$1),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(snapshot.value),
                    icon: const Icon(Icons.save_outlined),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 13),
                      child: Text('保存复盘'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _hydrate(ReviewDetails? review) {
    if (review == null || _loadedId == review.id) return;
    _loadedId = review.id;
    _happened.text = review.happenedText ?? '';
    _learned.text = review.learnedText ?? '';
    _improve.text = review.improveText ?? '';
    _mood = review.mood;
  }

  Future<void> _save(ReviewSnapshot? snapshot) async {
    if (snapshot == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(reviewRepositoryProvider)
          .save(
            ReviewDraft(
              period: widget.period,
              snapshot: snapshot,
              happenedText: _happened.text,
              learnedText: _learned.text,
              improveText: _improve.text,
              mood: _mood,
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
      }
    }
  }
}

class _PromptField extends StatelessWidget {
  const _PromptField({
    required this.controller,
    required this.title,
    required this.question,
  });
  final TextEditingController controller;
  final String title;
  final String question;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(question, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: const InputDecoration(
              hintText: '写下你的想法…',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
  );
}
