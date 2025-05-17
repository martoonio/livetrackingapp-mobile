import '../../presentation/component/utils.dart';

class ClusterModel {
  final String id;
  final String name;
  final String description;
  final List<List<double>>? clusterCoordinates;
  final String status;
  final String createdAt;
  final String updatedAt;

  ClusterModel({
    required this.id,
    required this.name,
    required this.description,
    required this.clusterCoordinates,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClusterModel.fromJson(Map<String, dynamic> json) {
    return ClusterModel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      clusterCoordinates: json['clusterCoordinates'] != null
          ? parseRouteCoordinates(json['clusterCoordinates'])
          : (json['assigned_route'] != null
              ? parseRouteCoordinates(json['assigned_route'])
              : null),
      status: json['status'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }
}