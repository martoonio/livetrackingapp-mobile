class PatrolSession {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final List<List<double>> patrolPath;
  final String status; // 'active', 'completed', 'cancelled'

  PatrolSession({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.patrolPath,
    required this.status,
  });
}