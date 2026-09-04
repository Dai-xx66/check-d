enum ReviewType { day, week, month, year }

class ReviewPeriod {
  const ReviewPeriod({
    required this.type,
    required this.startsOn,
    required this.endsOn,
  });

  final ReviewType type;
  final DateTime startsOn;
  final DateTime endsOn;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReviewPeriod &&
            other.type == type &&
            other.startsOn == startsOn &&
            other.endsOn == endsOn;
  }

  @override
  int get hashCode => Object.hash(type, startsOn, endsOn);
}

class ReviewSnapshot {
  const ReviewSnapshot({
    required this.dueCount,
    required this.completedCount,
    required this.timedSeconds,
  });

  final int dueCount;
  final int completedCount;
  final int timedSeconds;

  int get completionPercent => dueCount == 0
      ? 0
      : (completedCount / dueCount * 100).round().clamp(0, 100);
}

class ReviewDraft {
  const ReviewDraft({
    required this.period,
    required this.snapshot,
    this.happenedText,
    this.learnedText,
    this.improveText,
    this.mood,
  });

  final ReviewPeriod period;
  final ReviewSnapshot snapshot;
  final String? happenedText;
  final String? learnedText;
  final String? improveText;
  final int? mood;
}

class ReviewDetails {
  const ReviewDetails({
    required this.id,
    required this.period,
    required this.snapshot,
    required this.createdAt,
    required this.updatedAt,
    this.happenedText,
    this.learnedText,
    this.improveText,
    this.mood,
  });

  final String id;
  final ReviewPeriod period;
  final ReviewSnapshot snapshot;
  final String? happenedText;
  final String? learnedText;
  final String? improveText;
  final int? mood;
  final DateTime createdAt;
  final DateTime updatedAt;
}
