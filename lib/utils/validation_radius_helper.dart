import 'dart:math';

import 'package:firebase_database/firebase_database.dart';

class ValidationRadiusHelper {
  static const double DEFAULT_RADIUS = 50.0;

  /// Mendapatkan radius validasi untuk cluster tertentu
  static Future<double> getClusterValidationRadius(String clusterId) async {
    try {
      if (clusterId.isEmpty) return DEFAULT_RADIUS;

      final clusterSnapshot =
          await FirebaseDatabase.instance.ref('users/$clusterId').get();

      if (clusterSnapshot.exists) {
        final clusterData = clusterSnapshot.value as Map<dynamic, dynamic>;
        return clusterData['checkpoint_validation_radius'] != null
            ? (clusterData['checkpoint_validation_radius'] as num).toDouble()
            : DEFAULT_RADIUS;
      }

      return DEFAULT_RADIUS;
    } catch (e) {
      print('Error getting cluster validation radius: $e');
      return DEFAULT_RADIUS;
    }
  }

  /// Update radius validasi untuk cluster
  static Future<bool> updateClusterValidationRadius(
      String clusterId, double newRadius) async {
    try {
      if (clusterId.isEmpty || newRadius < 5 || newRadius > 500) {
        return false;
      }

      await FirebaseDatabase.instance.ref('users/$clusterId').update({
        'checkpoint_validation_radius': newRadius,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      print('Error updating cluster validation radius: $e');
      return false;
    }
  }

  /// Validasi apakah suatu koordinat berada dalam radius checkpoint
  static bool isWithinCheckpointRadius({
    required double checkpointLat,
    required double checkpointLng,
    required double actualLat,
    required double actualLng,
    required double radiusInMeters,
  }) {
    try {
      final distance = _calculateDistance(
        checkpointLat,
        checkpointLng,
        actualLat,
        actualLng,
      );

      return distance <= radiusInMeters;
    } catch (e) {
      print('Error validating checkpoint radius: $e');
      return false;
    }
  }

  /// Menghitung jarak antara dua koordinat (Haversine formula)
  static double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Radius bumi dalam meter
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = (dLat / 2) * (dLat / 2) +
        (_toRadians(lat1) * _toRadians(lat2)) * (dLon / 2) * (dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  static double _toRadians(double degrees) {
    return degrees * (pi / 180);
  }
}
