class Report {
  final String id;
  final String title;
  final String description;
  final String photoUrl;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String taskId;

  Report({
    required this.id,
    required this.title,
    required this.description,
    required this.photoUrl,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.taskId,
  });
}
