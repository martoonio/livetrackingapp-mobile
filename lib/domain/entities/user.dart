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
  });

  // Cek apakah user memiliki profil lengkap
  bool get hasProfile => name.isNotEmpty && role.isNotEmpty;

  // Cek apakah user memiliki akses admin
  bool get isCommandCenter => role == 'commandCenter';

  // Cek apakah user adalah akun patroli
  bool get isPatrol => role == 'patrol';

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
      createdAt: map['created_at'] != null 
          ? DateTime.parse(map['created_at']) 
          : null,
      updatedAt: map['updated_at'] != null 
          ? DateTime.parse(map['updated_at']) 
          : null,
      updatedBy: map['updated_by'],
    );
  }

  // Helper method untuk parsing officers
  static List<Officer>? _parseOfficers(dynamic officersData) {
    if (officersData == null) return null;
    
    try {
      if (officersData is List) {
        return officersData
            .map((officerMap) => Officer.fromMap(
                  officerMap is Map<String, dynamic> 
                      ? officerMap 
                      : Map<String, dynamic>.from(officerMap),
                ))
            .toList();
      }
      
      if (officersData is Map) {
        // Jika data officers berbentuk map dengan key-value
        return officersData.entries
            .map((entry) => Officer.fromMap(
                  entry.value is Map<String, dynamic> 
                      ? entry.value 
                      : Map<String, dynamic>.from(entry.value),
                ))
            .toList();
      }
    } catch (e) {
      print('Error parsing officers data: $e');
    }
    
    return null;
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
    } catch (e) {
      print('Error parsing cluster coordinates: $e');
    }
    
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
    );
  }
}

// Kelas untuk memodelkan data Officer dalam cluster
class Officer {
  final String id;
  final String name;
  final String shift; // Shift kerja (misalnya: "pagi", "siang", "malam")
  final String clusterId; // ID cluster tempat officer ditugaskan
  final String? photoUrl; // URL foto officer

  Officer({
    required this.id,
    required this.name,
    required this.shift,
    required this.clusterId,
    this.photoUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'shift': shift,
      'cluster_id': clusterId,
      'photo_url': photoUrl,
    };
  }

  factory Officer.fromMap(Map<String, dynamic> map) {
    return Officer(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      shift: map['shift'] ?? '',
      clusterId: map['cluster_id'] ?? '',
      photoUrl: map['photo_url'],
    );
  }
}