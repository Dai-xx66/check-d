enum PlanType { month, year }

class PlanDraft {
  const PlanDraft({
    required this.name,
    required this.type,
    required this.colorValue,
    required this.startsOn,
    required this.endsOn,
    required this.taskIds,
    this.goal,
  });

  final String name;
  final PlanType type;
  final int colorValue;
  final String? goal;
  final DateTime startsOn;
  final DateTime endsOn;
  final Set<String> taskIds;
}

class PlanDetails {
  const PlanDetails({
    required this.id,
    required this.name,
    required this.type,
    required this.colorValue,
    required this.startsOn,
    required this.endsOn,
    required this.taskIds,
    required this.dueCount,
    required this.completedCount,
    this.goal,
  });

  final String id;
  final String name;
  final PlanType type;
  final int colorValue;
  final String? goal;
  final DateTime startsOn;
  final DateTime endsOn;
  final Set<String> taskIds;
  final int dueCount;
  final int completedCount;

  double get progress => dueCount == 0 ? 0 : completedCount / dueCount;
  int get progressPercent => (progress * 100).round().clamp(0, 100);
}
