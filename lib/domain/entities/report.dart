class Report {
  final String id;
  final String taskId;
  final String title;
  final String description;
  final double latitude;
  final double longitude;
  final String photoUrl;
  final DateTime timestamp;

  Report({
    required this.id,
    required this.taskId,
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.photoUrl,
    required this.timestamp,
  });

  factory Report.fromJson(String id, Map<String, dynamic> json) {
    return Report(
      id: id,
      taskId: json['taskId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      latitude: json['latitude'] is num ? (json['latitude'] as num).toDouble() : 0.0,
      longitude: json['longitude'] is num ? (json['longitude'] as num).toDouble() : 0.0,
      photoUrl: json['photoUrl'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'title': title,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'photoUrl': photoUrl,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}