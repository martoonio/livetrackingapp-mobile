import 'package:flutter/material.dart';

class User {
  final String id;
  final String email;
  final String name;
  final String role; // 'patrol' atau 'commandCenter'
  final List<Officer>? officers; // Daftar petugas dalam cluster
  final List<List<double>>? clusterCoordinates; // Koordinat cluster
  String? pushToken;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;

  // TAMBAHAN BARU: Radius validasi checkpoint dalam meter
  final double? checkpointValidationRadius;

  // NEW: Battery monitoring fields untuk user (patrol)
  final int? batteryLevel;
  final String? batteryState; // charging, discharging, full, unknown
  final DateTime? lastBatteryUpdate;
  final bool? isOnline; // Status online berdasarkan update battery

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.officers,
    this.clusterCoordinates,
    this.pushToken,
    this.createdAt,
    this.updatedAt,
    this.updatedBy,
    this.checkpointValidationRadius, // Default akan 50 meter jika null
    // NEW: Battery fields
    this.batteryLevel,
    this.batteryState,
    this.lastBatteryUpdate,
    this.isOnline,
  });

  // Getter untuk mendapatkan radius dengan default value
  // double get validationRadius => checkpointValidationRadius ?? 50.0;

  // Cek apakah user memiliki profil lengkap
  bool get hasProfile => name.isNotEmpty && role.isNotEmpty;

  // Cek apakah user memiliki akses admin
  bool get isCommandCenter => role == 'commandCenter';

  // Cek apakah user adalah akun patroli
  bool get isPatrol => role == 'patrol';

  // NEW: Battery status getters
  bool get hasLowBattery => batteryLevel != null && batteryLevel! < 20;
  bool get hasMediumBattery =>
      batteryLevel != null && batteryLevel! >= 20 && batteryLevel! <= 50;
  bool get hasGoodBattery => batteryLevel != null && batteryLevel! > 50;

  String get batteryStatusText {
    if (batteryLevel == null) return 'Unknown';
    if (hasLowBattery) return 'Low';
    if (hasMediumBattery) return 'Medium';
    return 'Good';
  }

  Color get batteryStatusColor {
    if (batteryLevel == null) return const Color(0xFF9E9E9E); // neutral500
    if (hasLowBattery) return const Color(0xFFD32F2F); // dangerR500
    if (hasMediumBattery) return const Color(0xFFF57C00); // warningY500
    return const Color(0xFF388E3C); // successG500
  }

  // NEW: Check if user is currently online (battery updated in last 10 minutes)
  bool get isCurrentlyOnline {
    if (lastBatteryUpdate == null) return false;
    final now = DateTime.now();
    final difference = now.difference(lastBatteryUpdate!);
    return difference.inMinutes <= 10;
  }

  // Konversi ke Map untuk Firebase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'officers': officers?.map((officer) => officer.toMap()).toList(),
      'cluster_coordinates': clusterCoordinates,
      'push_token': pushToken,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'updated_by': updatedBy,
      'checkpoint_validation_radius': checkpointValidationRadius,
      // NEW: Battery fields
      'battery_level': batteryLevel,
      'battery_state': batteryState,
      'last_battery_update': lastBatteryUpdate?.toIso8601String(),
      'is_online': isOnline,
    };
  }

  // Factory constructor untuk membuat User dari Map
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] ?? '',
      officers: _parseOfficers(map['officers']),
      clusterCoordinates: _parseCoordinates(map['cluster_coordinates']),
      pushToken: map['push_token'],
      createdAt:
          map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt:
          map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
      updatedBy: map['updated_by'],
      checkpointValidationRadius:
          _parseDouble(map['checkpoint_validation_radius']),
      // NEW: Battery fields parsing
      batteryLevel: map['battery_level'],
      batteryState: map['battery_state'],
      lastBatteryUpdate: map['last_battery_update'] != null
          ? DateTime.parse(map['last_battery_update'])
          : null,
      isOnline: map['is_online'],
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;

    try {
      if (value is double) {
        print('User._parseDouble: Value is already double: $value');
        return value;
      } else if (value is int) {
        print('User._parseDouble: Converting int to double: $value');
        return value.toDouble();
      } else if (value is num) {
        print('User._parseDouble: Converting num to double: $value');
        return value.toDouble();
      } else if (value is String) {
        print('User._parseDouble: Parsing string to double: $value');
        return double.tryParse(value);
      } else {
        print(
            'User._parseDouble: Unknown type ${value.runtimeType}, value: $value');
        return null;
      }
    } catch (e) {
      print('User._parseDouble: Error parsing value $value: $e');
      return null;
    }
  }

  // Perbaiki _parseOfficers method untuk menangani berbagai struktur data
  static List<Officer>? _parseOfficers(dynamic officersData) {
    if (officersData == null) return null;

    List<Officer> result = [];

    try {
      if (officersData is List) {
        // Filter null entries
        final nonNullEntries =
            officersData.where((item) => item != null).toList();

        for (var officerData in nonNullEntries) {
          try {
            if (officerData is Map) {
              // Pastikan data officer memiliki semua properti yang diperlukan
              final Map<String, dynamic> officerMap = {};

              // Convert dynamic map to string keys map
              officerData.forEach((key, value) {
                officerMap[key.toString()] = value;
              });

              // Pastikan ID ada
              if (!officerMap.containsKey('id') || officerMap['id'] == null) {
                continue;
              }

              final officer = Officer.fromMap(officerMap);
              result.add(officer);
            }
          } catch (e) {}
        }
      } else if (officersData is Map) {
        // Handle officers as Map with battery info
        officersData.forEach((key, value) {
          try {
            if (value != null && value is Map) {
              // Convert to string key map
              final Map<String, dynamic> officerMap = {};

              // Populate map with string keys
              value.forEach((k, v) {
                officerMap[k.toString()] = v;
              });

              // Use key as ID if missing
              if (!officerMap.containsKey('id') ||
                  officerMap['id'] == null ||
                  officerMap['id'].toString().isEmpty) {
                officerMap['id'] = key.toString();
              }

              final officer = Officer.fromMap(officerMap);
              result.add(officer);
            }
          } catch (e) {}
        });
      } else {}
    } catch (e, stack) {}

    return result.isEmpty ? null : result;
  }

  // Helper method untuk parsing coordinates
  static List<List<double>>? _parseCoordinates(dynamic coordinatesData) {
    if (coordinatesData == null) return null;

    try {
      if (coordinatesData is List) {
        return coordinatesData.map((point) {
          if (point is List) {
            return point.map((coord) {
              if (coord is double) return coord;
              if (coord is int) return coord.toDouble();
              return 0.0;
            }).toList();
          }
          return <double>[0.0, 0.0];
        }).toList();
      }
    } catch (e) {}

    return null;
  }

  // Copy with method untuk immutability
  User copyWith({
    String? id,
    String? email,
    String? name,
    String? role,
    List<Officer>? officers,
    List<List<double>>? clusterCoordinates,
    String? pushToken,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? updatedBy,
    double? checkpointValidationRadius,
    // NEW: Battery fields
    int? batteryLevel,
    String? batteryState,
    DateTime? lastBatteryUpdate,
    bool? isOnline,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      officers: officers ?? this.officers,
      clusterCoordinates: clusterCoordinates ?? this.clusterCoordinates,
      pushToken: pushToken ?? this.pushToken,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      checkpointValidationRadius:
          checkpointValidationRadius ?? this.checkpointValidationRadius,
      // NEW: Battery fields
      batteryLevel: batteryLevel ?? this.batteryLevel,
      batteryState: batteryState ?? this.batteryState,
      lastBatteryUpdate: lastBatteryUpdate ?? this.lastBatteryUpdate,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

// Enum untuk tipe officer
enum OfficerType {
  organik,
  outsource,
}

// Enum untuk shift kerja
enum ShiftType {
  // Organik shifts
  pagi, // 07:00-15:00
  sore, // 15:00-23:00
  malam, // 23:00-07:00

  // Outsource shifts
  siang, // 07:00-19:00
  malamPanjang, // 19:00-07:00
}

// Kelas untuk memodelkan data Officer dalam cluster
class Officer {
  final String id;
  final String name;
  final OfficerType type; // Organik atau Outsource
  final ShiftType shift; // Shift kerja
  final String clusterId; // ID cluster tempat officer ditugaskan
  final String? photoUrl; // URL foto officer

  // NEW: Battery info untuk officer (akan diambil dari User yang terkait)
  final int? batteryLevel;
  final String? batteryState;
  final DateTime? lastBatteryUpdate;

  Officer({
    required this.id,
    required this.name,
    required this.type,
    required this.shift,
    required this.clusterId,
    this.photoUrl,
    // NEW: Battery fields
    this.batteryLevel,
    this.batteryState,
    this.lastBatteryUpdate,
  });

  // NEW: Battery status getters untuk Officer
  bool get hasLowBattery => batteryLevel != null && batteryLevel! < 20;
  bool get hasMediumBattery =>
      batteryLevel != null && batteryLevel! >= 20 && batteryLevel! <= 50;
  bool get hasGoodBattery => batteryLevel != null && batteryLevel! > 50;

  bool get isCurrentlyOnline {
    if (lastBatteryUpdate == null) return false;
    final now = DateTime.now();
    final difference = now.difference(lastBatteryUpdate!);
    return difference.inMinutes <= 10;
  }

  // Konversi string shift menjadi enum ShiftType
  static ShiftType _parseShiftType(String? shiftStr, String? typeStr) {
    final officerType = _parseOfficerType(typeStr);

    if (officerType == OfficerType.outsource) {
      // Outsource hanya memiliki 2 shift
      if (shiftStr?.toLowerCase().contains('malam') == true) {
        return ShiftType.malamPanjang;
      }
      return ShiftType.siang;
    } else {
      // Organik memiliki 3 shift
      if (shiftStr?.toLowerCase().contains('sore') == true) {
        return ShiftType.sore;
      } else if (shiftStr?.toLowerCase().contains('malam') == true) {
        return ShiftType.malam;
      }
      return ShiftType.pagi;
    }
  }

  // Konversi string tipe menjadi enum OfficerType
  static OfficerType _parseOfficerType(String? typeStr) {
    if (typeStr?.toLowerCase() == 'outsource') {
      return OfficerType.outsource;
    }
    return OfficerType.organik;
  }

  // Konversi ShiftType ke string untuk tampilan
  String get shiftDisplay {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi (07:00 - 15:00)';
      case ShiftType.sore:
        return 'Sore (15:00 - 23:00)';
      case ShiftType.malam:
        return 'Malam (23:00 - 07:00)';
      case ShiftType.siang:
        return 'Siang (07:00 - 19:00)';
      case ShiftType.malamPanjang:
        return 'Malam (19:00 - 07:00)';
    }
  }

  // Konversi OfficerType ke string untuk tampilan
  String get typeDisplay {
    switch (type) {
      case OfficerType.organik:
        return 'Organik';
      case OfficerType.outsource:
        return 'Outsource';
    }
  }

  // Mendapatkan jam mulai shift dalam format jam lengkap
  DateTime getShiftStartTime(DateTime date) {
    switch (shift) {
      case ShiftType.pagi:
        return DateTime(date.year, date.month, date.day, 7, 0);
      case ShiftType.sore:
        return DateTime(date.year, date.month, date.day, 15, 0);
      case ShiftType.malam:
        return DateTime(date.year, date.month, date.day, 23, 0);
      case ShiftType.siang:
        return DateTime(date.year, date.month, date.day, 7, 0);
      case ShiftType.malamPanjang:
        return DateTime(date.year, date.month, date.day, 19, 0);
    }
  }

  // Mendapatkan jam selesai shift dalam format jam lengkap
  DateTime getShiftEndTime(DateTime date) {
    switch (shift) {
      case ShiftType.pagi:
        return DateTime(date.year, date.month, date.day, 15, 0);
      case ShiftType.sore:
        return DateTime(date.year, date.month, date.day, 23, 0);
      case ShiftType.malam:
        return DateTime(date.year, date.month, date.day, 7, 0)
            .add(const Duration(days: 1));
      case ShiftType.siang:
        return DateTime(date.year, date.month, date.day, 19, 0);
      case ShiftType.malamPanjang:
        return DateTime(date.year, date.month, date.day, 7, 0)
            .add(const Duration(days: 1));
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type == OfficerType.organik ? 'organik' : 'outsource',
      'shift': _shiftTypeToString(shift),
      'cluster_id': clusterId,
      'photo_url': photoUrl,
      // NEW: Battery fields
      'battery_level': batteryLevel,
      'battery_state': batteryState,
      'last_battery_update': lastBatteryUpdate?.toIso8601String(),
    };
  }

  // Konversi ShiftType ke string untuk database
  String _shiftTypeToString(ShiftType shiftType) {
    switch (shiftType) {
      case ShiftType.pagi:
        return 'pagi';
      case ShiftType.sore:
        return 'sore';
      case ShiftType.malam:
        return 'malam';
      case ShiftType.siang:
        return 'siang';
      case ShiftType.malamPanjang:
        return 'malam_panjang';
    }
  }

  factory Officer.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] ?? 'organik';
    final shiftStr = map['shift'] ?? 'pagi';

    return Officer(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: _parseOfficerType(typeStr),
      shift: _parseShiftType(shiftStr, typeStr),
      clusterId: map['cluster_id'] ?? '',
      photoUrl: map['photo_url'],
      // NEW: Battery fields parsing
      batteryLevel: map['battery_level'],
      batteryState: map['battery_state'],
      lastBatteryUpdate: map['last_battery_update'] != null
          ? DateTime.parse(map['last_battery_update'])
          : null,
    );
  }

  // NEW: Copy with method untuk Officer
  Officer copyWith({
    String? id,
    String? name,
    OfficerType? type,
    ShiftType? shift,
    String? clusterId,
    String? photoUrl,
    int? batteryLevel,
    String? batteryState,
    DateTime? lastBatteryUpdate,
  }) {
    return Officer(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      shift: shift ?? this.shift,
      clusterId: clusterId ?? this.clusterId,
      photoUrl: photoUrl ?? this.photoUrl,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      batteryState: batteryState ?? this.batteryState,
      lastBatteryUpdate: lastBatteryUpdate ?? this.lastBatteryUpdate,
    );
  }
}
