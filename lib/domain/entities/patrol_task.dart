import 'package:firebase_database/firebase_database.dart';
import 'dart:math' as Math;

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PatrolTask {
  final String taskId;
  final String userId;
  final String officerId;
  final String vehicleId;
  final String status;
  final String? timeliness;
  final String clusterId;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? assignedStartTime;
  final DateTime? assignedEndTime;
  final double? distance;
  final List<List<double>>? assignedRoute;
  final DateTime createdAt;
  final String createdBy;
  final Map<String, dynamic>? routePath;
  final Map<String, dynamic>? lastLocation;
  final String? notes;
  String? _officerName;
  String? _officerPhotoUrl;
  String? _clusterName;
  String? _vehicleName;

  String get officerName {
    if (_officerName == null || _officerName == 'Loading...') {
      return userId.isNotEmpty
          ? 'Officer #${userId.substring(0, Math.min(5, userId.length))}'
          : 'Unknown Officer';
    }
    return _officerName!;
  }

  String get clusterName {
    if (_clusterName == null || _clusterName == 'Loading...') {
      return clusterId.isNotEmpty
          ? 'Cluster #${clusterId.substring(0, Math.min(5, clusterId.length))}'
          : 'Unknown Cluster';
    }
    return _clusterName!;
  }

  String get vehicleName {
    if (_vehicleName == null || _vehicleName!.isEmpty) {
      return vehicleId.isEmpty ? 'Unknown Vehicle' : vehicleId;
    }
    return _vehicleName!;
  }

  String get officerPhotoUrl {
    if (_officerPhotoUrl == null ||
        _officerPhotoUrl == 'P' ||
        _officerPhotoUrl!.isEmpty) {
      return '';
    }
    return _officerPhotoUrl!;
  }

  set officerName(String value) => _officerName = value;
  set clusterName(String value) => _clusterName = value;
  set vehicleName(String value) => _vehicleName = value;
  set officerPhotoUrl(String value) => _officerPhotoUrl = value;

  String? finalReportPhotoUrl;
  final String? finalReportNote;
  final DateTime? finalReportTime;
  String? initialReportPhotoUrl;
  final String? initialReportNote;
  final DateTime? initialReportTime;
  bool? mockLocationDetected;
  int? mockLocationCount;

  PatrolTask({
    required this.taskId,
    required this.userId,
    this.officerId = '',
    required this.vehicleId,
    required this.status,
    this.timeliness,
    this.clusterId = '',
    this.startTime,
    this.endTime,
    this.assignedStartTime,
    this.assignedEndTime,
    this.distance,
    this.assignedRoute,
    required this.createdAt,
    this.createdBy = '',
    this.routePath,
    this.lastLocation,
    this.notes,
    String? officerName,
    String? clusterName,
    String? vehicleName,
    String? officerPhotoUrl,
    this.finalReportPhotoUrl,
    this.finalReportNote,
    this.finalReportTime,
    this.initialReportPhotoUrl,
    this.initialReportNote,
    this.initialReportTime,
    this.mockLocationDetected,
    this.mockLocationCount,
  }) {
    _officerName = officerName;
    _clusterName = clusterName;
    _vehicleName = vehicleName;
    _officerPhotoUrl = officerPhotoUrl;
  }

  factory PatrolTask.fromJson(Map<String, dynamic> json) {
    return PatrolTask(
      taskId: json['taskId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      officerId: json['officerId'] as String? ?? '',
      vehicleId: json['vehicleId'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      timeliness: json['timeliness'] as String?,
      clusterId: json['clusterId'] as String? ?? '',
      startTime: _parseDateTime(json['startTime']) ??
          _parseDateTime(json['start_time']),
      endTime:
          _parseDateTime(json['endTime']) ?? _parseDateTime(json['end_time']),
      assignedStartTime: _parseDateTime(json['assignedStartTime']) ??
          _parseDateTime(json['assigned_start_time']),
      assignedEndTime: _parseDateTime(json['assignedEndTime']) ??
          _parseDateTime(json['assigned_end_time']),
      assignedRoute: json['assignedRoute'] != null
          ? _parseRouteCoordinates(json['assignedRoute'])
          : (json['assigned_route'] != null
              ? _parseRouteCoordinates(json['assigned_route'])
              : null),
      distance: json['distance'] != null
          ? (json['distance'] as num).toDouble()
          : null,
      createdAt: _parseDateTime(json['createdAt']) ??
          _parseDateTime(json['created_at']) ??
          DateTime.now(),
      createdBy:
          json['createdBy'] as String? ?? json['created_by'] as String? ?? '',
      routePath: json['route_path'] as Map<String, dynamic>?,
      lastLocation: json['lastLocation'] as Map<String, dynamic>?,
      notes: json['notes'] as String?,
      officerName: json['officerName'] as String?,
      clusterName: json['clusterName'] as String?,
      vehicleName: json['vehicleName'] as String?,
      officerPhotoUrl: json['officerPhotoUrl'] as String?,
      finalReportPhotoUrl: json['finalReportPhotoUrl'] as String?,
      finalReportNote: json['finalReportNote'] as String?,
      finalReportTime: _parseDateTime(json['finalReportTime']),
      initialReportPhotoUrl: json['initialReportPhotoUrl'] as String?,
      initialReportNote: json['initialReportNote'] as String?,
      initialReportTime: _parseDateTime(json['initialReportTime']),
      mockLocationDetected: json['mockLocationDetected'] as bool?,
      mockLocationCount: json['mockLocationCount'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'userId': userId,
      'officerId': officerId.isNotEmpty ? officerId : userId,
      'vehicleId': vehicleId,
      'status': status,
      'timeliness': timeliness,
      'clusterId': clusterId,
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'assignedStartTime': assignedStartTime?.toIso8601String(),
      'assignedEndTime': assignedEndTime?.toIso8601String(),
      'distance': distance,
      'assignedRoute': assignedRoute,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'notes': notes,
      'finalReportPhotoUrl': finalReportPhotoUrl,
      'finalReportNote': finalReportNote,
      'finalReportTime': finalReportTime?.toIso8601String(),
      'initialReportPhotoUrl': initialReportPhotoUrl,
      'initialReportNote': initialReportNote,
      'initialReportTime': initialReportTime?.toIso8601String(),
      'mockLocationDetected': mockLocationDetected,
      'mockLocationCount': mockLocationCount,
    };
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        print('Error parsing date: $value - $e');
        return null;
      }
    } else if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    return null;
  }

  static List<List<double>> _parseRouteCoordinates(dynamic routeData) {
    if (routeData is! List) return [];

    try {
      return (routeData as List).map((route) {
        if (route is! List) return <double>[];
        return (route as List).map((coord) {
          if (coord is double) return coord;
          if (coord is int) return coord.toDouble();
          if (coord is String) {
            try {
              return double.parse(coord);
            } catch (_) {
              return 0.0;
            }
          }
          return 0.0;
        }).toList();
      }).toList();
    } catch (e) {
      print('Error parsing route coordinates: $e');
      return [];
    }
  }

  Future<void> fetchRelatedData(DatabaseReference database) async {
    try {
      await Future.wait([
        fetchOfficerName(database),
        fetchClusterName(database),
        fetchVehicleName(database),
      ]);
    } catch (e) {
      print('Error fetching related data: $e');
    }
  }

  Future<void> fetchOfficerName(DatabaseReference database) async {
    try {
      if (clusterId.isEmpty || userId.isEmpty) {
        _officerName = 'Unknown Officer';
        return;
      }

      print('Fetching officer name for userId: $userId in cluster: $clusterId');

      final officersSnapshot =
          await database.child('users/$clusterId/officers').get();

      if (officersSnapshot.exists && officersSnapshot.value != null) {
        final data = officersSnapshot.value;

        if (data is List) {
          final officersList = List.from(data.where((item) => item != null));
          print('Officers data is a List with ${officersList.length} entries');

          for (var officerData in officersList) {
            if (officerData is Map && officerData['id'] == userId) {
              _officerName =
                  officerData['name']?.toString() ?? 'Unknown Officer';
              _officerPhotoUrl = officerData['photo_url']?.toString();
              print('Found officer in array: $_officerName');
              return;
            }
          }
        } else if (data is Map<dynamic, dynamic>) {
          if (data.containsKey(userId) && data[userId] is Map) {
            final officerData = data[userId];
            _officerName = officerData['name']?.toString() ?? 'Unknown Officer';
            _officerPhotoUrl = officerData['photo_url']?.toString();
            print('Found officer directly by key: $_officerName');
            return;
          }

          for (var entry in data.entries) {
            final officerData = entry.value;
            if (officerData is Map && officerData['id'] == userId) {
              _officerName =
                  officerData['name']?.toString() ?? 'Unknown Officer';
              _officerPhotoUrl = officerData['photo_url']?.toString();
              print('Found officer by ID property: $_officerName');
              return;
            }
          }
        }
      }

      final userSnapshot = await database.child('users/$userId').get();
      if (userSnapshot.exists && userSnapshot.value != null) {
        final userData = userSnapshot.value;
        if (userData is Map<dynamic, dynamic>) {
          _officerName = userData['name']?.toString() ?? 'Unknown Officer';
          _officerPhotoUrl = userData['photo_url']?.toString() ??
              userData['photoUrl']?.toString();
          print('Found officer from direct user lookup: $_officerName');
          return;
        }
      }

      _officerName = userId.isNotEmpty
          ? 'Officer #${userId.substring(0, Math.min(5, userId.length))}'
          : 'Unknown Officer';
    } catch (e, stack) {
      print('Error fetching officer name: $e');
      print('Stack trace: $stack');
      _officerName = userId.isNotEmpty
          ? 'Officer #${userId.substring(0, Math.min(5, userId.length))}'
          : 'Unknown Officer';
    }
  }

  Future<void> fetchClusterName(DatabaseReference database) async {
    try {
      if (clusterId.isEmpty) {
        _clusterName = 'No Cluster';
        return;
      }

      print('Fetching cluster name for ID: $clusterId');

      final userSnapshot = await database.child('users').child(clusterId).get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        _clusterName = userData['name']?.toString() ?? 'Unknown Cluster';
        print('Found cluster name in users/$clusterId: $_clusterName');
        return;
      }

      final clusterSnapshot =
          await database.child('clusters').child(clusterId).get();

      if (clusterSnapshot.exists) {
        final clusterData = clusterSnapshot.value as Map<dynamic, dynamic>;
        _clusterName = clusterData['name']?.toString() ?? 'Unknown Cluster';
        print('Found cluster name in clusters/$clusterId: $_clusterName');
        return;
      }

      _clusterName =
          'Cluster #${clusterId.substring(0, Math.min(5, clusterId.length))}';
      print('Could not find cluster name, using default: $_clusterName');
    } catch (e) {
      print('Error fetching cluster name: $e');

      _clusterName = clusterId.isNotEmpty
          ? 'Cluster #${clusterId.substring(0, Math.min(5, clusterId.length))}'
          : 'Unknown Cluster';
    }
  }

  Future<void> fetchVehicleName(DatabaseReference database) async {
    try {
      if (vehicleId.isEmpty) return;

      final snapshot = await database.child('vehicle').child(vehicleId).get();

      if (snapshot.exists) {
        final vehicleData = Map<String, dynamic>.from(snapshot.value as Map);
        final model = vehicleData['model'] as String? ?? '';
        final plateNumber = vehicleData['plateNumber'] as String? ?? vehicleId;

        if (model.isNotEmpty) {
          _vehicleName = '$model ($plateNumber)';
        } else {
          _vehicleName = plateNumber;
        }
      } else {
        _vehicleName = vehicleId;
      }
    } catch (e) {
      print('Error fetching vehicle info: $e');
      _vehicleName = vehicleId;
    }
  }

  List<LatLng> getRoutePathAsLatLng() {
    if (routePath == null || routePath!.isEmpty) {
      return [];
    }

    try {
      final Map<String, dynamic> pathMap = routePath is Map<String, dynamic>
          ? routePath as Map<String, dynamic>
          : Map<String, dynamic>.from(routePath as Map);

      final entries = pathMap.entries.toList()
        ..sort((a, b) {
          String aTime = a.value['timestamp'] as String;
          String bTime = b.value['timestamp'] as String;
          return aTime.compareTo(bTime);
        });

      return entries.map((entry) {
        final coords = entry.value['coordinates'] as List;
        return LatLng(
          (coords[0] as num).toDouble(),
          (coords[1] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      print('Error converting route path: $e');
      return [];
    }
  }

  double calculateTotalDistance() {
    if (routePath == null || routePath!.isEmpty) {
      return distance ?? 0.0;
    }

    try {
      final latLngPoints = getRoutePathAsLatLng();
      if (latLngPoints.length < 2) return distance ?? 0.0;

      double total = 0.0;
      for (int i = 0; i < latLngPoints.length - 1; i++) {
        final p1 = latLngPoints[i];
        final p2 = latLngPoints[i + 1];

        total += Geolocator.distanceBetween(
            p1.latitude, p1.longitude, p2.latitude, p2.longitude);
      }

      return total;
    } catch (e) {
      print('Error calculating distance: $e');
      return distance ?? 0.0;
    }
  }

  PatrolTask copyWith({
    String? taskId,
    String? userId,
    String? officerId,
    String? vehicleId,
    String? status,
    String? timeliness,
    String? clusterId,
    DateTime? startTime,
    DateTime? endTime,
    DateTime? assignedStartTime,
    DateTime? assignedEndTime,
    double? distance,
    List<List<double>>? assignedRoute,
    DateTime? createdAt,
    String? createdBy,
    Map<String, dynamic>? routePath,
    Map<String, dynamic>? lastLocation,
    String? notes,
    String? officerName,
    String? clusterName,
    String? vehicleName,
    String? officerPhotoUrl,
    String? finalReportPhotoUrl,
    String? finalReportNote,
    DateTime? finalReportTime,
    String? initialReportPhotoUrl,
    String? initialReportNote,
    DateTime? initialReportTime,
    bool? mockLocationDetected,
    int? mockLocationCount,
  }) {
    return PatrolTask(
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      officerId: officerId ?? this.officerId,
      vehicleId: vehicleId ?? this.vehicleId,
      status: status ?? this.status,
      timeliness: timeliness ?? this.timeliness,
      clusterId: clusterId ?? this.clusterId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      assignedStartTime: assignedStartTime ?? this.assignedStartTime,
      assignedEndTime: assignedEndTime ?? this.assignedEndTime,
      distance: distance ?? this.distance,
      assignedRoute: assignedRoute ?? this.assignedRoute,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      routePath: routePath ?? this.routePath,
      lastLocation: lastLocation ?? this.lastLocation,
      notes: notes ?? this.notes,
      officerName: officerName ?? _officerName,
      clusterName: clusterName ?? _clusterName,
      vehicleName: vehicleName ?? _vehicleName,
      officerPhotoUrl: officerPhotoUrl ?? _officerPhotoUrl, // Tambahkan ini
      finalReportPhotoUrl: finalReportPhotoUrl ?? this.finalReportPhotoUrl,
      finalReportNote: finalReportNote ?? this.finalReportNote,
      finalReportTime: finalReportTime ?? this.finalReportTime,
      initialReportPhotoUrl:
          initialReportPhotoUrl ?? this.initialReportPhotoUrl,
      initialReportNote: initialReportNote ?? this.initialReportNote,
      initialReportTime: initialReportTime ?? this.initialReportTime,
      mockLocationDetected: mockLocationDetected ?? this.mockLocationDetected,
      mockLocationCount: mockLocationCount ?? this.mockLocationCount,
    );
  }

  @override
  String toString() {
    return 'PatrolTask(taskId: $taskId, userId: $userId, status: $status, clusterId: $clusterId)';
  }
}
