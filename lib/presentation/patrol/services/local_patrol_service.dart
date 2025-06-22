import 'package:hive/hive.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'local_patrol_data.dart';

class LocalPatrolService {
  static const String _patrolBoxName = 'patrol_data';
  static const String _locationBoxName = 'location_data';
  static const String _logBoxName = 'patrol_logs';

  // ✅ UPDATED: Use TypedBox for LocalPatrolData
  static Box<LocalPatrolData>? _patrolBox;
  static Box<dynamic>? _locationBox;
  static Box<dynamic>? _logBox;

  static Future<void> init() async {
    try {
      print('🔄 Initializing LocalPatrolService...');

      // ✅ Register adapter if not already registered
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(LocalPatrolDataAdapter());
      }

      // ✅ Open TypedBox for LocalPatrolData
      _patrolBox = await Hive.openBox<LocalPatrolData>(_patrolBoxName);
      _locationBox = await Hive.openBox<dynamic>(_locationBoxName);
      _logBox = await Hive.openBox<dynamic>(_logBoxName);

      print('✅ LocalPatrolService initialized successfully');
      print('   - Patrol box: ${_patrolBox!.length} items');
      print('   - Location box: ${_locationBox!.length} items');
    } catch (e) {
      print('❌ Error initializing LocalPatrolService: $e');
      throw Exception('Failed to initialize LocalPatrolService: $e');
    }
  }

  static Future<void> updatePatrolField({
    required String taskId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      if (_patrolBox == null) {
        throw Exception('Patrol box not initialized');
      }

      final existingData = _patrolBox!.get(taskId);
      if (existingData == null) {
        throw Exception('No patrol data found to update: $taskId');
      }

      // ✅ Update fields using HiveObject methods
      await existingData.updateAndSave(updates);

      print('✅ Patrol field updated: $taskId');
    } catch (e) {
      print('❌ Error updating patrol field: $e');
      throw e;
    }
  }

// ✅ ENHANCED: Update mock location detection using HiveObject
  static Future<void> updateMockLocationDetection({
    required String taskId,
    required bool detected,
    required int count,
  }) async {
    try {
      if (_patrolBox == null) {
        throw Exception('Patrol box not initialized');
      }

      final existingData = _patrolBox!.get(taskId);
      if (existingData != null) {
        await existingData.updateAndSave({
          'mockLocationDetected': detected,
          'mockLocationCount': count,
        });
        print('✅ Updated mock location detection: $taskId (count: $count)');
      } else {
        print('⚠️ No patrol data found to update mock detection: $taskId');
      }
    } catch (e) {
      print('❌ Error updating mock location detection: $e');
    }
  }

  // ✅ UPDATED: Save LocalPatrolData object to TypedBox
  static Future<void> saveLocalPatrolDataToBox(LocalPatrolData data) async {
    try {
      if (_patrolBox == null) {
        throw Exception('Patrol box not initialized');
      }

      print('💾 Saving LocalPatrolData to TypedBox: ${data.taskId}');

      // ✅ Use key-based storage in TypedBox
      await _patrolBox!.put(data.taskId, data);

      print('✅ LocalPatrolData saved successfully: ${data.taskId}');
    } catch (e) {
      print('❌ Error saving LocalPatrolData: $e');
      throw e;
    }
  }

  // ✅ UPDATED: Get patrol data from TypedBox
  static LocalPatrolData? getPatrolData(String taskId) {
    try {
      if (_patrolBox == null) {
        print('❌ Patrol box not initialized');
        return null;
      }

      final data = _patrolBox!.get(taskId);

      if (data != null) {
        print(
            '📱 Retrieved LocalPatrolData: ${data.taskId} (${data.status}, ${data.routePath.length} points)');
        return data;
      } else {
        print('⚠️ No LocalPatrolData found: $taskId');
        return null;
      }
    } catch (e) {
      print('❌ Error getting LocalPatrolData: $e');
      return null;
    }
  }

  // ✅ UPDATED: Save patrol start using TypedBox
  static Future<void> savePatrolStart({
    required String taskId,
    required String userId,
    required DateTime startTime,
    String? initialPhotoUrl,
    String? initialNote,
  }) async {
    await logLocalStorageState('BEFORE_SAVE_PATROL_START', taskId);

    try {
      if (_patrolBox == null) {
        throw Exception('Patrol box not initialized');
      }

      final localData = LocalPatrolData(
        taskId: taskId,
        userId: userId,
        status: 'started',
        startTime: startTime.toIso8601String(),
        endTime: null,
        distance: 0.0,
        routePath: <String, dynamic>{},
        initialReportPhotoUrl: initialPhotoUrl,
        initialNote: initialNote,
        finalReportPhotoUrl: null,
        finalNote: null,
        mockLocationDetected: false,
        mockLocationCount: 0,
        lastUpdated: DateTime.now().toIso8601String(),
        isSynced: false,
        elapsedTimeSeconds: 0,
      );

      // ✅ Save to TypedBox
      await _patrolBox!.put(taskId, localData);
      print('✅ Patrol start data saved locally: $taskId');

      // ✅ BACKUP: Also save to location box for redundancy
      await _locationBox!.put('patrol_meta_$taskId', {
        'taskId': taskId,
        'status': 'started',
        'startTime': startTime.toIso8601String(),
        'lastUpdated': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('❌ Error saving patrol start: $e');
      throw e;
    }

    await logLocalStorageState('AFTER_SAVE_PATROL_START', taskId);
  }

  // ✅ UPDATED: Update patrol location using TypedBox
  static Future<void> updatePatrolLocation({
    required String taskId,
    required Position position,
    required DateTime timestamp,
    required double totalDistance,
    required int elapsedSeconds,
  }) async {
    try {
      if (_patrolBox == null) {
        throw Exception('Patrol box not initialized');
      }

      final existingData = _patrolBox!.get(taskId);
      if (existingData == null) {
        print('⚠️ No existing patrol data found for location update: $taskId');
        return;
      }

      // ✅ Add location to route path
      final locationKey = timestamp.millisecondsSinceEpoch.toString();
      existingData.routePath[locationKey] = {
        'coordinates': [position.latitude, position.longitude],
        'timestamp': timestamp.toIso8601String(),
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'heading': position.heading,
        'speed': position.speed,
      };

      // ✅ Update other fields
      existingData.distance = totalDistance;
      existingData.elapsedTimeSeconds = elapsedSeconds;
      existingData.lastUpdated = DateTime.now().toIso8601String();
      existingData.status = 'ongoing';

      // ✅ Save using HiveObject.save()
      await existingData.save();

      // ✅ BACKUP: Save individual location data
      await _locationBox!.put('location_${taskId}_$locationKey', {
        'taskId': taskId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': timestamp.toIso8601String(),
        'accuracy': position.accuracy,
        'totalDistance': totalDistance,
        'elapsedSeconds': elapsedSeconds,
      });

      // ✅ Log periodically
      if (existingData.routePath.length % 10 == 0) {
        print(
            '✅ Location updated for patrol $taskId: ${existingData.routePath.length} points, ${totalDistance.toStringAsFixed(1)}m');
      }
    } catch (e) {
      print('❌ Error updating patrol location: $e');
      throw e;
    }
  }

  // lib/presentation/patrol/services/local_patrol_service.dart
// Update method completePatrol dengan better error handling:

// ✅ UPDATED: Complete patrol using TypedBox with defensive programming
  static Future<void> completePatrol({
    required String taskId,
    required DateTime endTime,
    String? finalPhotoUrl,
    String? finalNote,
    required double totalDistance,
    required int elapsedSeconds,
  }) async {
    await logLocalStorageState('BEFORE_COMPLETE_PATROL', taskId);

    try {
      if (_patrolBox == null) {
        throw Exception('Patrol box not initialized');
      }

      final existingData = _patrolBox!.get(taskId);

      if (existingData == null) {
        print('⚠️ No patrol data found for completion. Attempting recovery...');

        // ✅ RECOVERY: Try to create minimal patrol data if none exists
        await _attemptPatrolDataRecovery(
          taskId: taskId,
          endTime: endTime,
          totalDistance: totalDistance,
          elapsedSeconds: elapsedSeconds,
          finalPhotoUrl: finalPhotoUrl,
          finalNote: finalNote,
        );

        return;
      }

      // ✅ Update completion data
      existingData.status = 'finished';
      existingData.endTime = endTime.toIso8601String();
      existingData.finalReportPhotoUrl = finalPhotoUrl;
      existingData.finalNote = finalNote;
      existingData.distance = totalDistance;
      existingData.elapsedTimeSeconds = elapsedSeconds;
      existingData.lastUpdated = DateTime.now().toIso8601String();
      existingData.isSynced = false;

      // ✅ Save using HiveObject.save()
      await existingData.save();

      // ✅ BACKUP: Create completion marker
      await _locationBox!.put('completion_$taskId', {
        'taskId': taskId,
        'completedAt': endTime.toIso8601String(),
        'totalDistance': totalDistance,
        'routePointsCount': existingData.routePath.length,
        'isSynced': false,
      });

      print(
          '✅ Patrol finished locally: $taskId (${existingData.routePath.length} points, ${totalDistance.toStringAsFixed(1)}m)');
    } catch (e) {
      print('❌ Error completing patrol: $e');
      throw e;
    }

    await logLocalStorageState('AFTER_COMPLETE_PATROL', taskId);
  }

// ✅ NEW: Recovery method untuk data yang hilang
  static Future<void> _attemptPatrolDataRecovery({
    required String taskId,
    required DateTime endTime,
    required double totalDistance,
    required int elapsedSeconds,
    String? finalPhotoUrl,
    String? finalNote,
  }) async {
    try {
      print('🔄 Attempting patrol data recovery for: $taskId');

      // Check if there's backup data in location box
      final metaData = _locationBox?.get('patrol_meta_$taskId');
      String? userId;
      String? startTime;
      Map<String, dynamic> routePath = {};

      if (metaData != null && metaData is Map) {
        startTime = metaData['startTime'];
        print('📱 Found backup meta data: start time = $startTime');
      }

      // Try to recover route path from location box
      if (_locationBox != null) {
        for (final key in _locationBox!.keys) {
          if (key.toString().startsWith('location_$taskId')) {
            final locationData = _locationBox!.get(key);
            if (locationData != null && locationData is Map) {
              final timestamp = locationData['timestamp'] as String?;
              final latitude = locationData['latitude'];
              final longitude = locationData['longitude'];

              if (timestamp != null && latitude != null && longitude != null) {
                final locationKey =
                    DateTime.parse(timestamp).millisecondsSinceEpoch.toString();
                routePath[locationKey] = {
                  'coordinates': [latitude, longitude],
                  'timestamp': timestamp,
                  'accuracy': locationData['accuracy'] ?? 0.0,
                };
              }
            }
          }
        }
      }

      // Create recovery patrol data
      final recoveryData = LocalPatrolData(
        taskId: taskId,
        userId: userId ?? 'unknown_user', // Will be updated from UI context
        status: 'finished',
        startTime: startTime ??
            endTime
                .subtract(Duration(seconds: elapsedSeconds))
                .toIso8601String(),
        endTime: endTime.toIso8601String(),
        distance: totalDistance,
        routePath: routePath,
        initialReportPhotoUrl: null,
        initialNote: null,
        finalReportPhotoUrl: finalPhotoUrl,
        finalNote: finalNote,
        mockLocationDetected: false,
        mockLocationCount: 0,
        lastUpdated: DateTime.now().toIso8601String(),
        isSynced: false,
        elapsedTimeSeconds: elapsedSeconds,
      );

      // Save recovery data
      await _patrolBox!.put(taskId, recoveryData);

      print('✅ Patrol data recovered and saved: $taskId');
      print('   - Route points: ${routePath.length}');
      print('   - Distance: ${totalDistance.toStringAsFixed(1)}m');
      print('   - Duration: ${elapsedSeconds}s');
    } catch (e) {
      print('❌ Failed to recover patrol data: $e');
      throw Exception('Data patroli hilang dan gagal dipulihkan: $e');
    }
  }

  // ✅ UPDATED: Update patrol to ongoing using TypedBox
  static Future<void> updatePatrolToOngoing(String taskId) async {
    try {
      if (_patrolBox == null) {
        throw Exception('Patrol box not initialized');
      }

      final existingData = _patrolBox!.get(taskId);

      if (existingData != null) {
        existingData.status = 'ongoing';
        existingData.lastUpdated = DateTime.now().toIso8601String();

        await existingData.save();
        print('✅ Updated patrol status to ongoing: $taskId');
      } else {
        print('⚠️ No patrol data found to update status: $taskId');
      }
    } catch (e) {
      print('❌ Error updating patrol to ongoing: $e');
    }
  }

  // ✅ UPDATED: Get unsynced patrols using TypedBox
  static List<LocalPatrolData> getUnsyncedPatrols() {
    try {
      if (_patrolBox == null) return [];

      final List<LocalPatrolData> unsyncedData = [];

      for (final patrol in _patrolBox!.values) {
        if (!patrol.isSynced) {
          unsyncedData.add(patrol);
        }
      }

      print('📊 Found ${unsyncedData.length} unsynced patrols');
      return unsyncedData;
    } catch (e) {
      print('❌ Error getting unsynced patrols: $e');
      return [];
    }
  }

  // ✅ UPDATED: Get statistics using TypedBox
  static Map<String, int> getStatistics() {
    try {
      if (_patrolBox == null) {
        return {
          'total': 0,
          'unsynced': 0,
          'synced': 0,
          'ongoing': 0,
          'finished': 0,
          'started': 0,
        };
      }

      int total = _patrolBox!.length;
      int unsynced = 0;
      int synced = 0;
      int ongoing = 0;
      int finished = 0;
      int started = 0;

      for (final patrol in _patrolBox!.values) {
        if (patrol.isSynced) {
          synced++;
        } else {
          unsynced++;
        }

        switch (patrol.status) {
          case 'started':
            started++;
            break;
          case 'ongoing':
            ongoing++;
            break;
          case 'finished':
            finished++;
            break;
        }
      }

      final stats = {
        'total': total,
        'unsynced': unsynced,
        'synced': synced,
        'ongoing': ongoing,
        'finished': finished,
        'started': started,
      };

      print('📊 LocalPatrolService Statistics: $stats');
      return stats;
    } catch (e) {
      print('❌ Error getting statistics: $e');
      return {
        'total': 0,
        'unsynced': 0,
        'synced': 0,
        'ongoing': 0,
        'finished': 0,
        'started': 0,
      };
    }
  }

  // ✅ UPDATED: Mark as synced using TypedBox
  static Future<void> markAsSynced(String taskId) async {
    try {
      if (_patrolBox == null) return;

      final existingData = _patrolBox!.get(taskId);

      if (existingData != null) {
        existingData.isSynced = true;
        existingData.lastUpdated = DateTime.now().toIso8601String();

        await existingData.save();
        print('✅ Marked patrol as synced: $taskId');
      }
    } catch (e) {
      print('❌ Error marking as synced: $e');
    }
  }

  // ✅ UPDATED: Delete patrol data using TypedBox
  static Future<void> deletePatrolData(String taskId) async {
    try {
      if (_patrolBox == null) return;

      final existingData = _patrolBox!.get(taskId);
      if (existingData != null) {
        await existingData.delete();
        print('✅ Force deleted patrol data: $taskId');
      }
    } catch (e) {
      print('❌ Error force deleting patrol data: $e');
    }
  }

  // ✅ Check if boxes are initialized
  static bool get isInitialized {
    return _patrolBox != null &&
        _locationBox != null &&
        _patrolBox!.isOpen &&
        _locationBox!.isOpen;
  }

  // ✅ Enhanced logging with TypedBox
  static Future<void> logLocalStorageState(String action,
      [String? taskId]) async {
    try {
      final timestamp = DateTime.now().toIso8601String();

      print('📊 =============== LOCAL STORAGE DEBUG ===============');
      print('⏰ Timestamp: $timestamp');
      print('🎯 Action: $action');
      if (taskId != null) print('🆔 Task ID: $taskId');

      if (_patrolBox == null || _locationBox == null) {
        print('❌ Boxes not initialized!');
        return;
      }

      print('📦 Patrol Box Status:');
      print('   - Name: ${_patrolBox!.name}');
      print('   - Length: ${_patrolBox!.length}');
      print('   - Is Open: ${_patrolBox!.isOpen}');
      print('   - Is Empty: ${_patrolBox!.isEmpty}');

      if (_patrolBox!.isNotEmpty) {
        print('   📋 All Patrol Data:');
        for (final patrol in _patrolBox!.values) {
          print('     🔹 Task: ${patrol.taskId}');
          print('       - Status: ${patrol.status}');
          print('       - Distance: ${patrol.distance}m');
          print('       - Route Points: ${patrol.routePath.length}');
          print('       - Is Synced: ${patrol.isSynced}');
        }
      }

      if (taskId != null) {
        print('🎯 Specific Task Data ($taskId):');
        final taskData = _patrolBox!.get(taskId);
        if (taskData != null) {
          print('   ✅ Task data exists in patrol box');
          print('   📊 Route Points: ${taskData.routePath.length}');
          print('   💾 Status: ${taskData.status}');
          print('   🔄 Is Synced: ${taskData.isSynced}');
        } else {
          print('   ⚠️ Task data NOT found in patrol box');
        }
      }

      print('📊 =============== END DEBUG LOG ===============\n');
    } catch (e) {
      print('❌ Error in logLocalStorageState: $e');
    }
  }
}
