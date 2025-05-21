import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteMergeHelper {
  /// Menggabungkan route_path sebelum dan sesudah restart
  static Map<String, dynamic> mergeRoutePaths(
    Map<dynamic, dynamic>? existingRoutePath,
    Map<String, dynamic>? newRoutePath,
  ) {
    // Konversi existingRoutePath ke Map<String, dynamic> jika perlu
    Map<String, dynamic> existing = {};
    if (existingRoutePath != null) {
      existingRoutePath.forEach((key, value) {
        existing[key.toString()] = value;
      });
    }

    // Jika tidak ada rute baru, kembalikan yang lama
    if (newRoutePath == null || newRoutePath.isEmpty) {
      return existing;
    }

    // Jika tidak ada rute lama, kembalikan yang baru
    if (existing.isEmpty) {
      return newRoutePath;
    }

    // Gabungkan kedua rute, prioritaskan data baru jika ada konflik key
    Map<String, dynamic> merged = {...existing, ...newRoutePath};
    return merged;
  }

  /// Konversi route_path ke list LatLng untuk polyline
  static List<LatLng> convertRoutePathToLatLngList(Map<dynamic, dynamic> routePath) {
    try {
      // Urutkan berdasarkan timestamp
      final entries = routePath.entries.toList()
        ..sort((a, b) => (a.value['timestamp'] as String)
            .compareTo(b.value['timestamp'] as String));

      // Konversi ke list LatLng
      List<LatLng> points = [];
      for (var entry in entries) {
        final coordinates = entry.value['coordinates'] as List;
        if (coordinates.length >= 2) {
          points.add(LatLng(
            (coordinates[0] as num).toDouble(),
            (coordinates[1] as num).toDouble(),
          ));
        }
      }
      return points;
    } catch (e) {
      print('Error converting route path: $e');
      return [];
    }
  }
}