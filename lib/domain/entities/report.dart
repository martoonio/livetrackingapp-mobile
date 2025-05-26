class Report {
  final String id;
  final String taskId;
  final String? userId;
  final String officerName;
  final String? clusterId;
  final String clusterName;
  final String title;
  final String description;
  final double latitude;
  final double longitude;
  final String photoUrl;
  final DateTime timestamp;
  final bool isSynced;

  Report({
    required this.id,
    required this.taskId,
    this.userId,
    required this.officerName,
    this.clusterId,
    required this.clusterName,
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.photoUrl,
    required this.timestamp,
    this.isSynced = true,
  });

  factory Report.fromJson(String id, Map<String, dynamic> json) {
    return Report(
      id: id,
      taskId: json['taskId'] as String? ?? '',
      userId: json['userId'] as String?,
      clusterId: json['clusterId'] as String?,
      officerName: json['officerName'] as String? ?? '',
      clusterName: json['clusterName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      latitude:
          json['latitude'] is num ? (json['latitude'] as num).toDouble() : 0.0,
      longitude: json['longitude'] is num
          ? (json['longitude'] as num).toDouble()
          : 0.0,
      photoUrl: json['photoUrl'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      isSynced: json['isSynced'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'userId': userId,
      'officerName': officerName,
      'clusterId': clusterId,
      'clusterName': clusterName,
      'title': title,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'photoUrl': photoUrl,
      'timestamp': timestamp.toIso8601String(),
      'isSynced': isSynced,
    };
  }

  // Tambahkan method untuk membuat salinan dengan status sinkronisasi diperbarui
  Report copyWith({
    String? id,
    String? taskId,
    String? userId,
    String? officerName,
    String? clusterId,
    String? clusterName,
    String? title,
    String? description,
    double? latitude,
    double? longitude,
    String? photoUrl,
    DateTime? timestamp,
    bool? isSynced,
  }) {
    return Report(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      officerName: officerName ?? this.officerName,
      clusterId: clusterId ?? this.clusterId,
      clusterName: clusterName ?? this.clusterName,
      title: title ?? this.title,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      photoUrl: photoUrl ?? this.photoUrl,
      timestamp: timestamp ?? this.timestamp,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}