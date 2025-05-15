import 'package:firebase_database/firebase_database.dart';

class PatrolTask {
  final String taskId;
  final String userId;
  final String vehicleId;
  final String status;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? assignedStartTime;
  final DateTime? assignedEndTime;
  final double? distance;
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
    this.assignedStartTime,
    this.assignedEndTime,
    this.distance,
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
      // Perbaikan: Periksa kedua format nama field (dengan dan tanpa underscore)
      assignedStartTime: json['assignedStartTime'] != null
          ? DateTime.parse(json['assignedStartTime'] as String)
          : (json['assigned_start_time'] != null
              ? DateTime.parse(json['assigned_start_time'] as String)
              : null),
      assignedEndTime: json['assignedEndTime'] != null
          ? DateTime.parse(json['assignedEndTime'] as String)
          : (json['assigned_end_time'] != null
              ? DateTime.parse(json['assigned_end_time'] as String)
              : null),
      assignedRoute: json['assignedRoute'] != null
          ? _parseRouteCoordinates(json['assignedRoute'])
          : (json['assigned_route'] != null
              ? _parseRouteCoordinates(json['assigned_route'])
              : null),
      distance: json['distance'] != null
          ? (json['distance'] as num).toDouble()
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      routePath: json['route_path'] as Map<String, dynamic>?,
      lastLocation: json['lastLocation'] as Map<String, dynamic>?,
    );
  }

// Helper method untuk parsing route coordinates dengan lebih aman
  static List<List<double>> _parseRouteCoordinates(dynamic routeData) {
    if (routeData is! List) return [];

    try {
      return (routeData as List).map((route) {
        if (route is! List) return <double>[];
        return (route as List).map((coord) {
          if (coord is double) return coord;
          if (coord is int) return coord.toDouble();
          return 0.0;
        }).toList();
      }).toList();
    } catch (e) {
      print('Error parsing route coordinates: $e');
      return [];
    }
  }

  Future<void> fetchOfficerName(DatabaseReference database) async {
    try {
      print('Fetching officer name for userId: $userId');
      if (userId.isEmpty) return;

      final snapshot = await database.child('users').child(userId).get();

      if (snapshot.exists) {
        final userData = Map<String, dynamic>.from(snapshot.value as Map);
        _officerName = userData['name'] as String? ?? 'Unknown';
        print('Officer name loaded: $_officerName');
      } else {
        _officerName = 'Unknown Officer';
        print('Officer not found in database');
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
    double? distance,
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
      distance: distance ?? this.distance,
      assignedRoute: assignedRoute ?? this.assignedRoute,
      createdAt: createdAt ?? this.createdAt,
      routePath: routePath ?? this.routePath,
      lastLocation: lastLocation ?? this.lastLocation,
      officerName: officerName ?? this.officerName,
    );
  }
}
