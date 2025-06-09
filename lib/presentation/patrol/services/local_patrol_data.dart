import 'package:hive/hive.dart';

part 'local_patrol_data.g.dart';

@HiveType(typeId: 0)
class LocalPatrolData extends HiveObject {
  @HiveField(0)
  String taskId;

  @HiveField(1)
  String userId;

  @HiveField(2)
  String status; // 'started', 'ongoing', 'completed'

  @HiveField(3)
  String? startTime; // Changed to String for better Hive compatibility

  @HiveField(4)
  String? endTime; // Changed to String for better Hive compatibility

  @HiveField(5)
  double distance;

  @HiveField(6)
  int elapsedTimeSeconds;

  @HiveField(7)
  String? initialReportPhotoUrl;

  @HiveField(8)
  String? finalReportPhotoUrl;

  @HiveField(9)
  String? initialNote;

  @HiveField(10)
  String? finalNote;

  @HiveField(11)
  Map<String, dynamic> routePath;

  @HiveField(12)
  bool isSynced;

  @HiveField(13)
  String lastUpdated; // Changed to String for better Hive compatibility

  @HiveField(14)
  bool mockLocationDetected;

  @HiveField(15)
  int mockLocationCount;

  LocalPatrolData({
    required this.taskId,
    required this.userId,
    required this.status,
    this.startTime,
    this.endTime,
    this.distance = 0.0,
    this.elapsedTimeSeconds = 0,
    this.initialReportPhotoUrl,
    this.finalReportPhotoUrl,
    this.initialNote,
    this.finalNote,
    this.routePath = const {},
    this.isSynced = false,
    required this.lastUpdated,
    this.mockLocationDetected = false,
    this.mockLocationCount = 0,
  });

  // Helper getters to convert strings back to DateTime
  DateTime? get startDateTime =>
      startTime != null ? DateTime.tryParse(startTime!) : null;
  DateTime? get endDateTime =>
      endTime != null ? DateTime.tryParse(endTime!) : null;
  DateTime get lastUpdatedDateTime => DateTime.parse(lastUpdated);

  // Helper setters to convert DateTime to strings
  set startDateTime(DateTime? dateTime) {
    startTime = dateTime?.toIso8601String();
  }

  set endDateTime(DateTime? dateTime) {
    endTime = dateTime?.toIso8601String();
  }

  set lastUpdatedDateTime(DateTime dateTime) {
    lastUpdated = dateTime.toIso8601String();
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'userId': userId,
      'status': status,
      'startTime': startTime,
      'endTime': endTime,
      'distance': distance,
      'elapsedTimeSeconds': elapsedTimeSeconds,
      'initialReportPhotoUrl': initialReportPhotoUrl,
      'finalReportPhotoUrl': finalReportPhotoUrl,
      'initialNote': initialNote,
      'finalNote': finalNote,
      'routePath': routePath,
      'isSynced': isSynced,
      'lastUpdated': lastUpdated,
      'mockLocationDetected': mockLocationDetected,
      'mockLocationCount': mockLocationCount,
    };
  }

  factory LocalPatrolData.fromJson(Map<String, dynamic> json) {
    return LocalPatrolData(
      taskId: json['taskId'],
      userId: json['userId'],
      status: json['status'],
      startTime: json['startTime'],
      endTime: json['endTime'],
      distance: (json['distance'] ?? 0.0).toDouble(),
      elapsedTimeSeconds: json['elapsedTimeSeconds'] ?? 0,
      initialReportPhotoUrl: json['initialReportPhotoUrl'],
      finalReportPhotoUrl: json['finalReportPhotoUrl'],
      initialNote: json['initialNote'],
      finalNote: json['finalNote'],
      routePath: Map<String, dynamic>.from(json['routePath'] ?? {}),
      isSynced: json['isSynced'] ?? false,
      lastUpdated: json['lastUpdated'] ?? DateTime.now().toIso8601String(),
      mockLocationDetected: json['mockLocationDetected'] ?? false,
      mockLocationCount: json['mockLocationCount'] ?? 0,
    );
  }
}
