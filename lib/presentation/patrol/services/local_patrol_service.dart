import 'package:hive/hive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:livetrackingapp/presentation/patrol/services/local_patrol_data.dart';

class LocalPatrolService {
  static const String _boxName = 'patrol_data';
  static Box<LocalPatrolData>? _box;

  static Future<void> init() async {
    try {
      // Clear any existing corrupted box first
      if (await Hive.boxExists(_boxName)) {
        try {
          _box = await Hive.openBox<LocalPatrolData>(_boxName);
          print('✅ Existing LocalPatrolService box opened');
        } catch (e) {
          print('⚠️ Corrupted box detected, deleting and recreating: $e');
          await Hive.deleteBoxFromDisk(_boxName);
          _box = await Hive.openBox<LocalPatrolData>(_boxName);
          print('✅ New LocalPatrolService box created');
        }
      } else {
        _box = await Hive.openBox<LocalPatrolData>(_boxName);
        print('✅ LocalPatrolService initialized with new box');
      }
    } catch (e) {
      print('❌ Error initializing LocalPatrolService: $e');
      // Try to create with a different name as fallback
      try {
        _box = await Hive.openBox<LocalPatrolData>('${_boxName}_backup');
        print('✅ LocalPatrolService initialized with backup box');
      } catch (fallbackError) {
        print('❌ Failed to initialize backup box: $fallbackError');
        throw Exception(
            'Failed to initialize LocalPatrolService: $fallbackError');
      }
    }
  }

  static Box<LocalPatrolData> get _patrolBox {
    if (_box == null || !_box!.isOpen) {
      throw Exception('LocalPatrolService not initialized. Call init() first.');
    }
    return _box!;
  }

  // Save patrol start data
  static Future<bool> savePatrolStart({
    required String taskId,
    required String userId,
    required DateTime startTime,
    String? initialPhotoUrl,
    String? initialNote,
  }) async {
    try {
      final patrolData = LocalPatrolData(
        taskId: taskId,
        userId: userId,
        status: 'started',
        startTime: startTime.toIso8601String(),
        distance: 0.0,
        elapsedTimeSeconds: 0,
        initialReportPhotoUrl: initialPhotoUrl,
        initialNote: initialNote,
        routePath: {},
        lastUpdated: DateTime.now().toIso8601String(),
      );

      await _patrolBox.put(taskId, patrolData);
      print('✅ Patrol start data saved locally for task: $taskId');
      return true;
    } catch (e) {
      print('❌ Error saving patrol start: $e');
      return false;
    }
  }

  // Update patrol status to ongoing
  static Future<bool> updatePatrolToOngoing(String taskId) async {
    try {
      final existingData = _patrolBox.get(taskId);
      if (existingData != null) {
        existingData.status = 'ongoing';
        existingData.lastUpdated = DateTime.now().toIso8601String();
        await existingData.save();
        print('✅ Patrol status updated to ongoing for task: $taskId');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error updating patrol to ongoing: $e');
      return false;
    }
  }

  // Update location and route data
  static Future<bool> updatePatrolLocation({
    required String taskId,
    required Position position,
    required DateTime timestamp,
    required double totalDistance,
    required int elapsedSeconds,
  }) async {
    try {
      final existingData = _patrolBox.get(taskId);
      if (existingData != null) {
        // Update basic data
        existingData.distance = totalDistance;
        existingData.elapsedTimeSeconds = elapsedSeconds;
        existingData.lastUpdated = DateTime.now().toIso8601String();

        // Add location to route path
        final routeKey = timestamp.millisecondsSinceEpoch.toString();
        existingData.routePath[routeKey] = {
          'coordinates': [position.latitude, position.longitude],
          'timestamp': timestamp.toIso8601String(),
          'accuracy': position.accuracy,
        };

        await existingData.save();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error updating patrol location: $e');
      return false;
    }
  }

  // Update mock location detection
  static Future<bool> updateMockLocationDetection({
    required String taskId,
    required bool detected,
    required int count,
  }) async {
    try {
      final existingData = _patrolBox.get(taskId);
      if (existingData != null) {
        existingData.mockLocationDetected = detected;
        existingData.mockLocationCount = count;
        existingData.lastUpdated = DateTime.now().toIso8601String();
        await existingData.save();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error updating mock location: $e');
      return false;
    }
  }

  // Update existing method in LocalPatrolService:

  static Future<bool> completePatrol({
    required String taskId,
    required DateTime endTime,
    required String finalPhotoUrl,
    String? finalNote,
    required double totalDistance,
    required int elapsedSeconds,
  }) async {
    try {
      final existingData = _patrolBox.get(taskId);
      if (existingData == null) {
        print('❌ No existing patrol data found for completion');
        return false;
      }

      print('🔄 Completing patrol in local storage...');

      // ✅ Update with completion data
      existingData.status = 'finished';
      existingData.endTime = endTime.toIso8601String();
      existingData.finalReportPhotoUrl = finalPhotoUrl;
      existingData.finalNote = finalNote;
      existingData.distance = totalDistance;
      existingData.lastUpdated = DateTime.now().toIso8601String();

      await existingData.save();

      print('✅ Patrol completed in local storage');
      print('   - Status: ${existingData.status}');
      print('   - End time: ${existingData.endTime}');
      print('   - Distance: ${existingData.distance}');
      print('   - Duration: ${existingData.elapsedTimeSeconds}s');

      return true;
    } catch (e) {
      print('❌ Error completing patrol: $e');
      return false;
    }
  }

  // Get patrol data
  static LocalPatrolData? getPatrolData(String taskId) {
    try {
      return _patrolBox.get(taskId);
    } catch (e) {
      print('❌ Error getting patrol data: $e');
      return null;
    }
  }

  // Check if patrol is active
  static bool isPatrolActive(String taskId) {
    try {
      final data = _patrolBox.get(taskId);
      return data != null &&
          (data.status == 'started' || data.status == 'ongoing');
    } catch (e) {
      print('❌ Error checking patrol status: $e');
      return false;
    }
  }

  // Get all unsynced patrols
  static List<LocalPatrolData> getUnsyncedPatrols() {
    try {
      return _patrolBox.values.where((patrol) => !patrol.isSynced).toList();
    } catch (e) {
      print('❌ Error getting unsynced patrols: $e');
      return [];
    }
  }

  // Mark patrol as synced
  static Future<bool> markAsSynced(String taskId) async {
    try {
      final existingData = _patrolBox.get(taskId);
      if (existingData != null) {
        existingData.isSynced = true;
        existingData.lastUpdated = DateTime.now().toIso8601String();
        await existingData.save();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error marking as synced: $e');
      return false;
    }
  }

  // Delete patrol data
  static Future<bool> deletePatrolData(String taskId) async {
    try {
      await _patrolBox.delete(taskId);
      print('✅ Patrol data deleted for task: $taskId');
      return true;
    } catch (e) {
      print('❌ Error deleting patrol data: $e');
      return false;
    }
  }

  // Clear all synced patrols (untuk cleanup)
  static Future<void> clearSyncedPatrols() async {
    try {
      final syncedKeys = _patrolBox.values
          .where((patrol) => patrol.isSynced)
          .map((patrol) => patrol.taskId)
          .toList();

      for (String key in syncedKeys) {
        await _patrolBox.delete(key);
      }
      print('✅ Cleared ${syncedKeys.length} synced patrols');
    } catch (e) {
      print('❌ Error clearing synced patrols: $e');
    }
  }

  // Get statistics
  static Map<String, int> getStatistics() {
    try {
      final allPatrols = _patrolBox.values;
      return {
        'total': allPatrols.length,
        'synced': allPatrols.where((p) => p.isSynced).length,
        'unsynced': allPatrols.where((p) => !p.isSynced).length,
        'active': allPatrols
            .where((p) => p.status == 'ongoing' || p.status == 'started')
            .length,
        'completed': allPatrols.where((p) => p.status == 'completed').length,
      };
    } catch (e) {
      print('❌ Error getting statistics: $e');
      return {
        'total': 0,
        'synced': 0,
        'unsynced': 0,
        'active': 0,
        'completed': 0
      };
    }
  }

  // Clear all data (untuk reset)
  static Future<void> clearAllData() async {
    try {
      await _patrolBox.clear();
      print('✅ All patrol data cleared');
    } catch (e) {
      print('❌ Error clearing all data: $e');
    }
  }
}
