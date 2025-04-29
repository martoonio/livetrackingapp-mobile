import 'package:firebase_database/firebase_database.dart';

class PatrolTask {
  final String taskId;
  final String userId;
  final String vehicleId;
  final String status;
  final DateTime? startTime;
  final DateTime? endTime;
  final List<List<double>>? assignedRoute;
  final DateTime createdAt;
  final Map<String, dynamic>? routePath;
  final Map<String, dynamic>? lastLocation;
  String? _officerName;
  String get officerName => _officerName ?? 'Loading...';
  set officerName(String value) => _officerName = value;

  PatrolTask({
    required this.taskId,
    required this.userId,
    required this.vehicleId,
    required this.status,
    this.startTime,
    this.endTime,
    this.assignedRoute,
    required this.createdAt,
    this.routePath,
    this.lastLocation,
    String? officerName,
  });

  factory PatrolTask.fromJson(Map<String, dynamic> json) {
    print('Processing JSON: $json'); // Debug print

    return PatrolTask(
      taskId: json['taskId'] as String,
      userId: json['userId'] as String,
      vehicleId: json['vehicleId'] as String,
      status: json['status'] as String,
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'] as String)
          : null,
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      assignedRoute: json['assigned_route'] != null
          ? (json['assigned_route'] as List)
              .map((route) => (route as List)
                  .map((coord) => (coord as num).toDouble())
                  .toList())
              .toList()
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      routePath: json['route_path'] as Map<String, dynamic>?,
      lastLocation: json['lastLocation'] as Map<String, dynamic>?,
    );
  }

  Future<void> fetchOfficerName(DatabaseReference database) async {
    try {
      if (userId == null) return;

      final snapshot = await database.child('users').child(userId!).get();

      if (snapshot.exists) {
        final userData = Map<String, dynamic>.from(snapshot.value as Map);
        _officerName = userData['name'] as String? ?? 'Unknown';
      } else {
        _officerName = 'Unknown Officer';
      }
    } catch (e) {
      print('Error fetching officer name: $e');
      _officerName = 'Error loading name';
    }
  }

  PatrolTask copyWith({
    String? taskId,
    String? userId,
    String? vehicleId,
    String? status,
    DateTime? startTime,
    DateTime? endTime,
    List<List<double>>? assignedRoute,
    DateTime? createdAt,
    Map<String, dynamic>? routePath,
    Map<String, dynamic>? lastLocation,
    String? officerName,
  }) {
    return PatrolTask(
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      vehicleId: vehicleId ?? this.vehicleId,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      assignedRoute: assignedRoute ?? this.assignedRoute,
      createdAt: createdAt ?? this.createdAt,
      routePath: routePath ?? this.routePath,
      lastLocation: lastLocation ?? this.lastLocation,
      officerName: officerName ?? this.officerName,
    );
  }
}
