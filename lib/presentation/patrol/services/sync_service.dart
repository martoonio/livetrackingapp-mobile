import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:livetrackingapp/presentation/patrol/services/local_patrol_data.dart';
import 'local_patrol_service.dart';

class SyncService {
  static Future<void> syncUnsyncedPatrols() async {
    try {
      // Check authentication first
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('❌ No authenticated user for sync');
        return;
      }

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
      // Verify authentication
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('❌ No authenticated user for patrol sync: ${patrol.taskId}');
        return;
      }

      final taskRef =
          FirebaseDatabase.instance.ref().child('tasks/${patrol.taskId}');

      // First, verify this user has permission to update this task
      final taskSnapshot = await taskRef.get();
      if (!taskSnapshot.exists) {
        print('❌ Task not found in Firebase: ${patrol.taskId}');
        return;
      }

      final taskData = taskSnapshot.value as Map<dynamic, dynamic>;
      final taskUserId = taskData['clusterId'];

      // Only sync if current user owns this task
      if (taskUserId != currentUser.uid) {
        print(
            '❌ Permission denied: User ${currentUser.uid} cannot sync task owned by $taskUserId');
        return;
      }

      // ✅ PREPARE UPDATE DATA WITH PERMISSION-SAFE FIELDS
      final updateData = <String, dynamic>{};

      // ✅ Core patrol data that user can always update
      if (patrol.startTime != null) {
        updateData['startTime'] = patrol.startTime;
        updateData['actualStartTime'] = patrol.startTime;
        updateData['startedFromApp'] = true;
      }

      if (patrol.endTime != null) {
        updateData['endTime'] = patrol.endTime;
        updateData['actualEndTime'] = patrol.endTime;
        updateData['finishedFromApp'] = true;
        updateData['status'] = 'completed';
      } else if (patrol.status == 'ongoing' || patrol.status == 'started') {
        updateData['status'] = 'ongoing';
      }

      // ✅ Distance (user can update)
      updateData['distance'] = patrol.distance;

      // ✅ Report data with proper field names
      if (patrol.initialReportPhotoUrl != null) {
        updateData['initialReportPhotoUrl'] = patrol.initialReportPhotoUrl;
      }

      if (patrol.finalReportPhotoUrl != null) {
        updateData['finalReportPhotoUrl'] = patrol.finalReportPhotoUrl;
      }

      if (patrol.initialNote != null) {
        updateData['initialReportNote'] = patrol.initialNote;
        updateData['initialReportTime'] =
            patrol.startTime ?? DateTime.now().toIso8601String();
      }

      if (patrol.finalNote != null) {
        updateData['finalReportNote'] = patrol.finalNote;
        updateData['finalReportTime'] =
            patrol.endTime ?? DateTime.now().toIso8601String();
      }

      if (patrol.routePath.isNotEmpty) {
        print('📍 Syncing route path with ${patrol.routePath.length} points');

        // ✅ Get existing route path from Firebase first
        Map<String, dynamic> existingFirebaseRoutePath = {};
        try {
          final existingSnapshot = await taskRef.child('route_path').get();
          if (existingSnapshot.exists && existingSnapshot.value != null) {
            final existingData =
                existingSnapshot.value as Map<dynamic, dynamic>;
            existingData.forEach((key, value) {
              if (value is Map) {
                existingFirebaseRoutePath[key.toString()] =
                    Map<String, dynamic>.from(value as Map);
              }
            });
            print(
                '📍 Found ${existingFirebaseRoutePath.length} existing points in Firebase');
          }
        } catch (e) {
          print('⚠️ Could not get existing route path: $e');
        }

        Map<String, dynamic> firebaseRoutePath =
            Map<String, dynamic>.from(existingFirebaseRoutePath);

        // ✅ Merge local route path dengan existing Firebase data
        patrol.routePath.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            try {
              // ✅ PERBAIKAN: Validasi koordinat yang lebih fleksibel
              if (value['coordinates'] != null &&
                  value['coordinates'] is List) {
                final coords = value['coordinates'] as List;
                if (coords.length >= 2 &&
                    coords[0] != null &&
                    coords[1] != null) {
                  final lat = (coords[0] as num).toDouble();
                  final lng = (coords[1] as num).toDouble();

                  // ✅ PERBAIKAN: Validasi koordinat yang lebih realistis
                  if (lat.abs() <= 90 &&
                      lng.abs() <= 180 &&
                      lat != 0.0 &&
                      lng != 0.0) {
                    // Hindari koordinat (0,0)
                    firebaseRoutePath[key] = {
                      'coordinates': [lat, lng],
                      'timestamp': value['timestamp'] ??
                          DateTime.now().toIso8601String(),
                    };
                  } else {
                    print('⚠️ Invalid coordinates skipped: lat=$lat, lng=$lng');
                  }
                }
              }
            } catch (e) {
              print('⚠️ Error processing route point $key: $e');
            }
          }
        });

        if (firebaseRoutePath.isNotEmpty) {
          updateData['route_path'] = firebaseRoutePath;

          // ✅ PERBAIKAN: Update lastLocation dengan titik terbaru
          final sortedEntries = firebaseRoutePath.entries.toList()
            ..sort((a, b) => (b.value['timestamp'] as String)
                .compareTo(a.value['timestamp'] as String));

          if (sortedEntries.isNotEmpty) {
            updateData['lastLocation'] = sortedEntries.first.value;
          }

          print(
              '📍 Route path prepared for sync: ${firebaseRoutePath.length} valid points');
          print(
              '📍 Latest timestamp: ${sortedEntries.isNotEmpty ? sortedEntries.first.value['timestamp'] : 'none'}');
        }
      }

      // ✅ Mock location data
      if (patrol.mockLocationDetected) {
        updateData['mockLocationDetected'] = true;
        updateData['mockLocationCount'] = patrol.mockLocationCount;
        updateData['lastMockDetection'] = DateTime.now().toIso8601String();
      }

      // ✅ Sync metadata
      updateData['lastUpdated'] = patrol.lastUpdated;
      updateData['syncedAt'] = DateTime.now().toIso8601String();

      print('🔄 Updating Firebase for patrol ${patrol.taskId}');
      print('📊 Update data keys: ${updateData.keys.toList()}');

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
            await Future.delayed(Duration(seconds: retryCount * 2));
          } else {
            // If all retries failed, check if it's a permission error
            if (e.toString().contains('permission-denied')) {
              print('❌ Permission denied error - user may not own this task');
              return; // Don't retry permission errors
            }
            throw e;
          }
        }
      }

      // ✅ UPDATE LOCAL DATA TO MARK AS SYNCED AND DELETE ONLY ON SUCCESS
      if (updateSuccess) {
        try {
          // ✅ FIRST, MARK AS SYNCED
          patrol.isSynced = true;
          await patrol.save();
          print('✅ Local data marked as synced');

          // ✅ THEN, DELETE LOCAL DATA ONLY AFTER SUCCESSFUL FIREBASE UPDATE
          try {
            await LocalPatrolService.deletePatrolData(patrol.taskId);
            print(
                '✅ Successfully synced and deleted local data for patrol: ${patrol.taskId}');
          } catch (e) {
            print(
                '⚠️ Synced to Firebase but failed to delete local data for: ${patrol.taskId}');
            // This is not critical - data is marked as synced so won't be re-synced
          }
        } catch (e) {
          print('⚠️ Failed to update local sync status: $e');
          // Data was synced to Firebase, so this is not critical
        }
      } else {
        print('❌ Firebase sync failed, preserving local data for retry');
      }
    } catch (e) {
      print('❌ Error syncing patrol ${patrol.taskId}: $e');
      // Don't rethrow to allow other patrols to continue syncing
    }
  }

  // ✅ Enhanced force sync with better cleanup logic
  static Future<bool> forceSyncPatrol(String taskId) async {
    try {
      // Check authentication
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('❌ No authenticated user for force sync');
        return false;
      }

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

      // ✅ VERIFY TASK OWNERSHIP BEFORE SYNC
      try {
        final taskRef = FirebaseDatabase.instance.ref().child('tasks/$taskId');
        final snapshot = await taskRef.get();

        if (snapshot.exists) {
          final firebaseData = snapshot.value as Map<dynamic, dynamic>;
          final taskUserId = firebaseData['clusterId'];

          // Check ownership
          if (taskUserId != currentUser.uid) {
            print(
                '❌ Permission denied: User ${currentUser.uid} cannot sync task owned by $taskUserId');
            return false;
          }

          // Check if critical data exists and is complete
          final hasStartTime = firebaseData['startTime'] != null;
          final hasStatus = firebaseData['status'] != null;

          if (hasStartTime && hasStatus) {
            // Check if local data matches or is more recent
            final localIsMoreRecent = localData.lastUpdated != null &&
                firebaseData['lastUpdated'] != null &&
                DateTime.parse(localData.lastUpdated!).isAfter(
                    DateTime.parse(firebaseData['lastUpdated'].toString()));

            if (!localIsMoreRecent) {
              print('✅ Firebase data is current, can safely delete local data');
              print('✅ Firebase data is current, can safely delete local data');
              try {
                await LocalPatrolService.deletePatrolData(taskId);
                print('✅ Local data deleted after verification for: $taskId');
              } catch (e) {
                print('❌ Failed to delete local data for: $taskId');
              }
            } else {
              print('⚠️ Local data is more recent, need to sync...');
            }
          } else {
            print('⚠️ Firebase data incomplete, re-syncing...');
          }
        } else {
          print('⚠️ Task not found in Firebase, need to sync');
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

  // ✅ Enhanced cleanup with permission checking
  static Future<void> cleanupSyncedData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('❌ No authenticated user for cleanup');
        return;
      }

      final allPatrols = LocalPatrolService.getUnsyncedPatrols();
      int deletedCount = 0;

      for (LocalPatrolData patrol in allPatrols) {
        try {
          final taskRef =
              FirebaseDatabase.instance.ref().child('tasks/${patrol.taskId}');
          final snapshot = await taskRef.get();

          if (snapshot.exists) {
            final firebaseData = snapshot.value as Map<dynamic, dynamic>;
            final taskUserId = firebaseData['userId'];

            // Only clean up if user owns the task
            if (taskUserId == currentUser.uid) {
              // Verify critical data exists
              if (firebaseData['startTime'] != null &&
                  firebaseData['status'] != null) {
                try {
                  await LocalPatrolService.deletePatrolData(patrol.taskId);
                  deletedCount++;
                  print('🧹 Cleaned up synced data for: ${patrol.taskId}');
                } catch (e) {
                  print('❌ Failed to delete local data for: ${patrol.taskId}');
                }
              }
            } else {
              print(
                  '⚠️ Skipping cleanup for task not owned by current user: ${patrol.taskId}');
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
