import 'package:firebase_database/firebase_database.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:livetrackingapp/presentation/patrol/services/local_patrol_data.dart';
import 'local_patrol_service.dart';

class SyncService {
  static Future<void> syncUnsyncedPatrols() async {
    try {
      // Check internet connection
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        print('❌ No internet connection for sync');
        return;
      }

      final unsyncedPatrols = LocalPatrolService.getUnsyncedPatrols();
      print('🔄 Found ${unsyncedPatrols.length} unsynced patrols');

      for (LocalPatrolData patrol in unsyncedPatrols) {
        await _syncSinglePatrol(patrol);
      }

      print('✅ Sync finished');
    } catch (e) {
      print('❌ Error during sync: $e');
    }
  }

  static Future<void> _syncSinglePatrol(LocalPatrolData patrol) async {
    try {
      final taskRef =
          FirebaseDatabase.instance.ref().child('tasks/${patrol.taskId}');

      // ✅ PREPARE COMPREHENSIVE UPDATE DATA
      final updateData = <String, dynamic>{};

      // ✅ Basic patrol data with proper status mapping
      if (patrol.startTime != null) {
        updateData['startTime'] = patrol.startTime;

        // Map local status to Firebase status
        if (patrol.status == 'finished') {
          updateData['status'] = 'finished';
        } else if (patrol.status == 'ongoing' || patrol.status == 'started') {
          updateData['status'] = 'ongoing';
        }
      }

      if (patrol.endTime != null) {
        updateData['endTime'] = patrol.endTime;
        updateData['status'] = 'finished';
      }

      // ✅ Distance and time data
      updateData['distance'] = patrol.distance;

      // ✅ Photo URLs
      if (patrol.initialReportPhotoUrl != null) {
        updateData['initialReportPhotoUrl'] = patrol.initialReportPhotoUrl;
      }

      if (patrol.finalReportPhotoUrl != null) {
        updateData['finalReportPhotoUrl'] = patrol.finalReportPhotoUrl;
      }

      // ✅ Notes
      if (patrol.initialNote != null) {
        updateData['initialNote'] = patrol.initialNote;
      }

      if (patrol.finalNote != null) {
        updateData['finalNote'] = patrol.finalNote;
      }

      // ✅ Route path - ENHANCED FORMATTING WITH VALIDATION
      if (patrol.routePath.isNotEmpty) {
        print('📍 Syncing route path with ${patrol.routePath.length} points');

        Map<String, dynamic> firebaseRoutePath = {};

        patrol.routePath.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            // Validate coordinates
            if (value['coordinates'] != null && value['coordinates'] is List) {
              final coords = value['coordinates'] as List;
              if (coords.length >= 2 &&
                  coords[0] != null &&
                  coords[1] != null) {
                firebaseRoutePath[key] = {
                  'coordinates': [
                    (coords[0] as num).toDouble(),
                    (coords[1] as num).toDouble(),
                  ],
                  'timestamp':
                      value['timestamp'] ?? DateTime.now().toIso8601String(),
                };
              }
            }
          }
        });

        if (firebaseRoutePath.isNotEmpty) {
          updateData['route_path'] = firebaseRoutePath;
          print(
              '📍 Route path prepared for sync: ${firebaseRoutePath.length} valid points');
        }
      }

      // ✅ Mock location data
      if (patrol.mockLocationDetected) {
        updateData['mockLocationDetected'] = true;
        updateData['mockLocationCount'] = patrol.mockLocationCount;
      }

      // ✅ Metadata
      updateData['lastUpdated'] = patrol.lastUpdated;
      updateData['syncedAt'] = DateTime.now().toIso8601String();

      print('🔄 Updating Firebase for patrol ${patrol.taskId}');
      print('📊 Update data: ${updateData.keys.toList()}');
      if (updateData.containsKey('route_path')) {
        print(
            '📍 Route path size: ${(updateData['route_path'] as Map).length} points');
      }

      // ✅ UPDATE FIREBASE WITH RETRY MECHANISM
      int retryCount = 0;
      bool updateSuccess = false;

      while (!updateSuccess && retryCount < 3) {
        try {
          await taskRef.update(updateData).timeout(
            Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Firebase update timeout after 30 seconds');
            },
          );
          updateSuccess = true;
          print('✅ Firebase update successful on attempt ${retryCount + 1}');
        } catch (e) {
          retryCount++;
          print('❌ Firebase update attempt $retryCount failed: $e');

          if (retryCount < 3) {
            // Wait before retry
            await Future.delayed(Duration(seconds: retryCount * 2));
          } else {
            throw e; // Re-throw after all retries failed
          }
        }
      }

      // ✅ DELETE LOCAL DATA AFTER SUCCESSFUL SYNC
      if (updateSuccess) {
        final deleteSuccess =
            await LocalPatrolService.deletePatrolData(patrol.taskId);
        if (deleteSuccess) {
          print(
              '✅ Successfully synced and deleted local data for patrol: ${patrol.taskId}');
        } else {
          print(
              '⚠️ Synced to Firebase but failed to delete local data for: ${patrol.taskId}');
        }
      }
    } catch (e) {
      print('❌ Error syncing patrol ${patrol.taskId}: $e');
      // Don't delete local data if there's an error
      throw e;
    }
  }

  // ✅ Enhanced force sync with auto delete
  static Future<bool> forceSyncPatrol(String taskId) async {
    try {
      // Check internet connection first
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        print('❌ No internet connection for force sync');
        return false;
      }

      final localData = LocalPatrolService.getPatrolData(taskId);
      if (localData == null) {
        print('⚠️ No local data found for patrol: $taskId');
        return false;
      }

      // ✅ DOUBLE CHECK: Verify data actually exists in Firebase before deleting local
      try {
        final taskRef = FirebaseDatabase.instance.ref().child('tasks/$taskId');
        final snapshot = await taskRef.get();

        if (snapshot.exists) {
          final firebaseData = snapshot.value as Map<dynamic, dynamic>;

          // Check if critical data exists
          final hasStartTime = firebaseData['startTime'] != null;
          final hasStatus = firebaseData['status'] != null;
          final hasDistance = firebaseData['distance'] != null;

          if (hasStartTime && hasStatus) {
            print('✅ Firebase data verified complete, deleting local data');

            // ✅ Delete local data since it's already in Firebase
            final deleteSuccess =
                await LocalPatrolService.deletePatrolData(taskId);
            if (deleteSuccess) {
              print('✅ Local data deleted after verification for: $taskId');
            }
            return true;
          } else {
            print('⚠️ Firebase data incomplete, re-syncing...');
            // Data incomplete, need to sync again
          }
        } else {
          print('⚠️ Task not found in Firebase, need to sync');
          // Task not in Firebase, need to sync
        }
      } catch (e) {
        print('❌ Error verifying Firebase data: $e');
        // Continue with sync anyway
      }

      // ✅ Perform sync if data not verified in Firebase
      print('🔄 Force syncing patrol: $taskId');
      await _syncSinglePatrol(localData);
      print('✅ Force sync finished for: $taskId');
      return true;
    } catch (e) {
      print('❌ Error force syncing patrol $taskId: $e');
      return false;
    }
  }

  // Call this method when app comes back online
  static Future<void> onConnectivityRestored() async {
    print('🌐 Connectivity restored, starting comprehensive sync...');
    await syncUnsyncedPatrols();
  }

  // ✅ NEW: Method to clean up all synced data manually
  static Future<void> cleanupSyncedData() async {
    try {
      final allPatrols = LocalPatrolService.getUnsyncedPatrols();
      int deletedCount = 0;

      for (LocalPatrolData patrol in allPatrols) {
        // Check if data exists in Firebase
        try {
          final taskRef =
              FirebaseDatabase.instance.ref().child('tasks/${patrol.taskId}');
          final snapshot = await taskRef.get();

          if (snapshot.exists) {
            final firebaseData = snapshot.value as Map<dynamic, dynamic>;

            // Verify critical data exists
            if (firebaseData['startTime'] != null &&
                firebaseData['status'] != null) {
              // Data verified in Firebase, safe to delete local
              final deleteSuccess =
                  await LocalPatrolService.deletePatrolData(patrol.taskId);
              if (deleteSuccess) {
                deletedCount++;
                print('🧹 Cleaned up synced data for: ${patrol.taskId}');
              }
            }
          }
        } catch (e) {
          print('❌ Error verifying patrol ${patrol.taskId}: $e');
        }
      }

      print('✅ Cleanup finished, deleted $deletedCount local patrol records');
    } catch (e) {
      print('❌ Error during cleanup: $e');
    }
  }
}
