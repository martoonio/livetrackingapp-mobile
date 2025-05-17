import 'package:firebase_database/firebase_database.dart';
import 'dart:math' as Math;

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PatrolTask {
  final String taskId;
  final String userId; // ID petugas yang ditugaskan
  final String officerId; // Alternatif ID petugas (untuk kompatibilitas)
  final String vehicleId;
  final String status;
  final String clusterId; // ID cluster untuk task ini
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? assignedStartTime;
  final DateTime? assignedEndTime;
  final double? distance;
  final List<List<double>>? assignedRoute;
  final DateTime createdAt;
  final String createdBy; // User yang membuat task
  final Map<String, dynamic>? routePath;
  final Map<String, dynamic>? lastLocation;
  final String? notes; // Catatan tambahan tentang tugas

  // Data officer yang akan di-lazy load
  String? _officerName;
  String? _officerPhotoUrl;
  String? _clusterName;
  String? _vehicleName;

  String get officerName => _officerName ?? 'Loading...';
  String get clusterName => _clusterName ?? 'Loading...';
  String get vehicleName => _vehicleName ?? vehicleId;
  String get officerPhotoUrl => _officerPhotoUrl ?? 'P';

  set officerName(String value) => _officerName = value;
  set clusterName(String value) => _clusterName = value;
  set vehicleName(String value) => _vehicleName = value;
  set officerPhotoUrl(String value) => _officerPhotoUrl = value;

  PatrolTask({
    required this.taskId,
    required this.userId,
    this.officerId = '',
    required this.vehicleId,
    required this.status,
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
  }) {
    _officerName = officerName;
    _clusterName = clusterName;
    _vehicleName = vehicleName;
    _officerPhotoUrl = officerPhotoUrl;
  }

  // Konversi dari JSON ke objek PatrolTask
  factory PatrolTask.fromJson(Map<String, dynamic> json) {
    return PatrolTask(
      taskId: json['taskId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      officerId: json['officerId'] as String? ?? '',
      vehicleId: json['vehicleId'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
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
    );
  }

  // Konversi ke Map untuk Firebase
  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'userId': userId,
      'officerId': officerId.isNotEmpty ? officerId : userId,
      'vehicleId': vehicleId,
      'status': status,
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
    };
  }

  // Helper method untuk parsing DateTime dari berbagai format
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
      // Asumsi timestamp dalam milidetik
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    return null;
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

  // Fetch related data
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

  // Fetch officer name
  // Perbaikan metode fetchOfficerName

  Future<void> fetchOfficerName(DatabaseReference database) async {
    try {
      if (clusterId.isNotEmpty) {
        final officerSnapshot =
            await database.child('users/$clusterId/officers/$userId').get();

        if (officerSnapshot.exists && officerSnapshot.value != null) {
          final officerData = officerSnapshot.value as Map<dynamic, dynamic>;
          _officerName = officerData['name']?.toString() ?? 'Unknown Officer';
          _officerPhotoUrl =
              officerData['photo_url']?.toString(); // Ambil URL foto
          print('Found officer by direct path: $_officerName');
          return;
        }

        // Jika tidak ditemukan dengan path langsung, cari di semua officers
        final clusterSnapshot =
            await database.child('users/$clusterId/officers').get();

        if (clusterSnapshot.exists && clusterSnapshot.value != null) {
          final officersData = clusterSnapshot.value as Map<dynamic, dynamic>;

          for (var officerId in officersData.keys) {
            final officerData =
                officersData[officerId] as Map<dynamic, dynamic>;

            if (officerData['id']?.toString() == userId) {
              _officerName =
                  officerData['name']?.toString() ?? 'Unknown Officer';
              _officerPhotoUrl =
                  officerData['photo_url']?.toString(); // Ambil URL foto
              print(
                  'Found officer by id in users/$clusterId/officers: $_officerName');
              return;
            }
          }
        }

        // Mencoba path lama (untuk kompatibilitas dengan data lama)
        final oldPathSnapshot =
            await database.child('clusters/$clusterId/officers').get();

        if (oldPathSnapshot.exists && oldPathSnapshot.value != null) {
          final officersData = oldPathSnapshot.value;

          if (officersData is List) {
            // Array format
            for (var i = 0; i < officersData.length; i++) {
              final officerData = officersData[i];
              if (officerData is Map &&
                  officerData['id']?.toString() == userId) {
                _officerName =
                    officerData['name']?.toString() ?? 'Unknown Officer';
                _officerPhotoUrl =
                    officerData['photo_url']?.toString(); // Ambil URL foto
                print(
                    'Found officer by id in clusters/$clusterId/officers array: $_officerName');
                return;
              }
            }
          } else if (officersData is Map) {
            // Map format
            final officersMap = officersData as Map<dynamic, dynamic>;

            for (var entry in officersMap.entries) {
              final officerData = entry.value;
              if (officerData is Map &&
                  officerData['id']?.toString() == userId) {
                _officerName =
                    officerData['name']?.toString() ?? 'Unknown Officer';
                _officerPhotoUrl =
                    officerData['photo_url']?.toString(); // Ambil URL foto
                print(
                    'Found officer by id in clusters/$clusterId/officers: $_officerName');
                return;
              }
            }
          }
        }
      }

      // Jika sampai sini belum ketemu, gunakan nilai default yang lebih baik
      _officerName =
          'Officer #${userId.substring(0, Math.min(5, userId.length))}';
      print('Could not find officer name, using default: $_officerName');
    } catch (e, stackTrace) {
      print('Error fetching officer name: $e');
      print('Stack trace: $stackTrace');

      // Nilai default yang lebih baik jika terjadi error
      _officerName = userId.isNotEmpty
          ? 'Officer #${userId.substring(0, Math.min(5, userId.length))}'
          : 'Unknown Officer';
    }
  }

  // Fetch cluster name
  // Perbaikan metode fetchClusterName

  Future<void> fetchClusterName(DatabaseReference database) async {
    try {
      if (clusterId.isEmpty) {
        _clusterName = 'No Cluster';
        return;
      }

      print('Fetching cluster name for ID: $clusterId');

      // Coba di path users
      final userSnapshot = await database.child('users').child(clusterId).get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        _clusterName = userData['name']?.toString() ?? 'Unknown Cluster';
        print('Found cluster name in users/$clusterId: $_clusterName');
        return;
      }

      // Coba di path clusters (untuk kompatibilitas dengan struktur lama)
      final clusterSnapshot =
          await database.child('clusters').child(clusterId).get();

      if (clusterSnapshot.exists) {
        final clusterData = clusterSnapshot.value as Map<dynamic, dynamic>;
        _clusterName = clusterData['name']?.toString() ?? 'Unknown Cluster';
        print('Found cluster name in clusters/$clusterId: $_clusterName');
        return;
      }

      // Default jika tidak ditemukan
      _clusterName =
          'Cluster #${clusterId.substring(0, Math.min(5, clusterId.length))}';
      print('Could not find cluster name, using default: $_clusterName');
    } catch (e) {
      print('Error fetching cluster name: $e');

      // Nilai default yang lebih baik jika terjadi error
      _clusterName = clusterId.isNotEmpty
          ? 'Cluster #${clusterId.substring(0, Math.min(5, clusterId.length))}'
          : 'Unknown Cluster';
    }
  }

  // Fetch vehicle name/info
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

  // Dalam class PatrolTask, tambahkan method untuk membantu mengelola routePath
  List<LatLng> getRoutePathAsLatLng() {
    if (routePath == null || routePath!.isEmpty) {
      return [];
    }

    try {
      // Convert to Map format for type safety
      final Map<String, dynamic> pathMap = routePath is Map<String, dynamic>
          ? routePath as Map<String, dynamic>
          : Map<String, dynamic>.from(routePath as Map);

      // Sort by timestamp for correct ordering
      final entries = pathMap.entries.toList()
        ..sort((a, b) {
          String aTime = a.value['timestamp'] as String;
          String bTime = b.value['timestamp'] as String;
          return aTime.compareTo(bTime);
        });

      // Convert to LatLng list
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

// Add helper to calculate distance from route
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

  // copyWith method untuk membuat salinan dengan perubahan
  PatrolTask copyWith({
    String? taskId,
    String? userId,
    String? officerId,
    String? vehicleId,
    String? status,
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
    String? officerPhotoUrl, // Tambahkan parameter ini
  }) {
    return PatrolTask(
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      officerId: officerId ?? this.officerId,
      vehicleId: vehicleId ?? this.vehicleId,
      status: status ?? this.status,
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
    );
  }

  // Untuk debugging
  @override
  String toString() {
    return 'PatrolTask(taskId: $taskId, userId: $userId, status: $status, clusterId: $clusterId)';
  }
}
