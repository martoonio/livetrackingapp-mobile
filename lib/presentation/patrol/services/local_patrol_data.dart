import 'package:hive/hive.dart';
import 'package:livetrackingapp/presentation/patrol/services/local_patrol_service.dart';

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
  String? startTime;

  @HiveField(4)
  String? endTime;

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
  String lastUpdated;

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

  // ✅ Enhanced save method using HiveObject capabilities
  @override
  Future<void> save() async {
    try {
      if (isInBox) {
        // ✅ Object already in box, just save changes
        await super.save();
        print('✅ LocalPatrolData updated in box: $taskId');
      } else {
        // ✅ Object not in box, add to box
        await LocalPatrolService.saveLocalPatrolDataToBox(this);
        print('✅ LocalPatrolData added to box: $taskId');
      }
    } catch (e) {
      print('❌ Error saving LocalPatrolData: $e');
      throw e;
    }
  }

  // ✅ Enhanced delete method
  @override
  Future<void> delete() async {
    try {
      if (isInBox) {
        await super.delete();
        print('✅ LocalPatrolData deleted from box: $taskId');
      } else {
        print('⚠️ LocalPatrolData not in box, cannot delete: $taskId');
      }
    } catch (e) {
      print('❌ Error deleting LocalPatrolData: $e');
      throw e;
    }
  }

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

  // ✅ Enhanced copyWith method
  LocalPatrolData copyWith({
    String? taskId,
    String? userId,
    String? status,
    String? startTime,
    String? endTime,
    double? distance,
    int? elapsedTimeSeconds,
    String? initialReportPhotoUrl,
    String? finalReportPhotoUrl,
    String? initialNote,
    String? finalNote,
    Map<String, dynamic>? routePath,
    bool? isSynced,
    String? lastUpdated,
    bool? mockLocationDetected,
    int? mockLocationCount,
  }) {
    return LocalPatrolData(
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      distance: distance ?? this.distance,
      elapsedTimeSeconds: elapsedTimeSeconds ?? this.elapsedTimeSeconds,
      initialReportPhotoUrl: initialReportPhotoUrl ?? this.initialReportPhotoUrl,
      finalReportPhotoUrl: finalReportPhotoUrl ?? this.finalReportPhotoUrl,
      initialNote: initialNote ?? this.initialNote,
      finalNote: finalNote ?? this.finalNote,
      routePath: routePath ?? this.routePath,
      isSynced: isSynced ?? this.isSynced,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      mockLocationDetected: mockLocationDetected ?? this.mockLocationDetected,
      mockLocationCount: mockLocationCount ?? this.mockLocationCount,
    );
  }

  // ✅ Update specific fields and save
  Future<void> updateAndSave(Map<String, dynamic> updates) async {
    try {
      // Update fields
      if (updates.containsKey('status')) status = updates['status'];
      if (updates.containsKey('startTime')) startTime = updates['startTime'];
      if (updates.containsKey('endTime')) endTime = updates['endTime'];
      if (updates.containsKey('distance')) distance = updates['distance'];
      if (updates.containsKey('elapsedTimeSeconds')) elapsedTimeSeconds = updates['elapsedTimeSeconds'];
      if (updates.containsKey('initialReportPhotoUrl')) initialReportPhotoUrl = updates['initialReportPhotoUrl'];
      if (updates.containsKey('finalReportPhotoUrl')) finalReportPhotoUrl = updates['finalReportPhotoUrl'];
      if (updates.containsKey('initialNote')) initialNote = updates['initialNote'];
      if (updates.containsKey('finalNote')) finalNote = updates['finalNote'];
      if (updates.containsKey('routePath')) routePath = Map<String, dynamic>.from(updates['routePath']);
      if (updates.containsKey('isSynced')) isSynced = updates['isSynced'];
      if (updates.containsKey('mockLocationDetected')) mockLocationDetected = updates['mockLocationDetected'];
      if (updates.containsKey('mockLocationCount')) mockLocationCount = updates['mockLocationCount'];
      
      // Always update lastUpdated
      lastUpdated = DateTime.now().toIso8601String();
      
      // Save to box
      await save();
      
      print('✅ LocalPatrolData updated and saved: $taskId');
    } catch (e) {
      print('❌ Error updating and saving LocalPatrolData: $e');
      throw e;
    }
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

  @override
  String toString() {
    return 'LocalPatrolData(taskId: $taskId, status: $status, distance: $distance, routePoints: ${routePath.length}, isSynced: $isSynced)';
  }
}