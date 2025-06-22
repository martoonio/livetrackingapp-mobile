// lib/services/missed_checkpoint_service.dart
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/notification_utils.dart';

class MissedCheckpointService {
  static Future<void> validateAndNotify({
    required PatrolTask completedTask,
    double? validationRadius, // ✅ Make optional to get from user profile
  }) async {
    try {
      print('🔍 MissedCheckpointService: Starting validation...');
      print('   - Task ID: ${completedTask.taskId}');
      print('   - Officer: ${completedTask.officerName}');
      print('   - Cluster: ${completedTask.clusterName}');
      print('   - User ID: ${completedTask.userId}');

      // Check if task has assigned route
      if (completedTask.assignedRoute == null ||
          completedTask.assignedRoute!.isEmpty) {
        print('⚠️ No assigned route for validation');
        return;
      }

      // Check if task has actual route
      if (completedTask.routePath == null || completedTask.routePath!.isEmpty) {
        print('⚠️ No actual route path for validation');
        return;
      }

      // ✅ GET CUSTOM VALIDATION RADIUS FROM USER PROFILE USING GETTER
      double finalValidationRadius =
          validationRadius ?? 50.0; // Default fallback

      try {
        if (completedTask.clusterId.isNotEmpty) {
          print(
              '🔍 Getting custom validation radius for user: ${completedTask.clusterId}');

          final userSnapshot = await FirebaseDatabase.instance
              .ref('users/${completedTask.clusterId}')
              .get()
              .timeout(Duration(seconds: 10));

          if (userSnapshot.exists && userSnapshot.value != null) {
            final userData = userSnapshot.value as Map<dynamic, dynamic>;

            // ✅ CREATE USER OBJECT TO USE GETTER
            try {
              final user = User.fromMap(Map<String, dynamic>.from(userData));

              // ✅ USE GETTER TO GET VALIDATION RADIUS
              finalValidationRadius = user.checkpointValidationRadius;

              print(
                  '✅ Using validation radius from user profile: ${finalValidationRadius}m');
              print(
                  '   - Has custom radius: ${user.hasCustomValidationRadius}');
              print('   - Display: ${user.validationRadiusDisplay}');
            } catch (userParseError) {
              print('❌ Error parsing user data: $userParseError');

              // ✅ FALLBACK: Direct parsing if User.fromMap fails
              final customRadius = userData['checkpoint_validation_radius'];
              if (customRadius != null) {
                final parsedRadius = _parseValidationRadius(customRadius);
                if (parsedRadius != null &&
                    parsedRadius > 0 &&
                    parsedRadius <= 200) {
                  finalValidationRadius = parsedRadius;
                  print(
                      '✅ Using fallback parsed radius: ${finalValidationRadius}m');
                } else {
                  print(
                      '⚠️ Invalid fallback radius ($customRadius), using default: ${finalValidationRadius}m');
                }
              } else {
                print(
                    'ℹ️ No custom radius in fallback, using default: ${finalValidationRadius}m');
              }
            }
          } else {
            print(
                '⚠️ User profile not found, using default radius: ${finalValidationRadius}m');
          }
        } else {
          print(
              '⚠️ No user ID provided, using default radius: ${finalValidationRadius}m');
        }
      } catch (e) {
        print('❌ Error getting user validation radius: $e');
        print('ℹ️ Falling back to default radius: ${finalValidationRadius}m');
      }

      // ✅ ENHANCED: Get comprehensive route data from multiple sources
      Map<String, dynamic> comprehensiveRoutePath =
          Map<String, dynamic>.from(completedTask.routePath!);

      // Try to get additional data from Firebase
      try {
        final firebaseTask = await FirebaseDatabase.instance
            .ref('tasks/${completedTask.taskId}')
            .get()
            .timeout(Duration(seconds: 10));

        if (firebaseTask.exists) {
          final taskData = firebaseTask.value as Map<dynamic, dynamic>;
          final fbRoutePath = taskData['route_path'] as Map<dynamic, dynamic>?;

          if (fbRoutePath != null && fbRoutePath.isNotEmpty) {
            print(
                '🔥 Adding ${fbRoutePath.length} Firebase route points to validation');
            fbRoutePath.forEach((key, value) {
              final keyStr = key.toString();
              if (!comprehensiveRoutePath.containsKey(keyStr)) {
                comprehensiveRoutePath[keyStr] =
                    Map<String, dynamic>.from(value as Map);
              }
            });
          }
        }
      } catch (e) {
        print('⚠️ Could not get additional Firebase data for validation: $e');
      }

      print(
          '📊 Using comprehensive route data: ${comprehensiveRoutePath.length} points');

      // Convert assigned route to LatLng
      List<LatLng> assignedCheckpoints = [];
      for (var checkpoint in completedTask.assignedRoute!) {
        if (checkpoint.length >= 2) {
          assignedCheckpoints.add(LatLng(
            checkpoint[0].toDouble(),
            checkpoint[1].toDouble(),
          ));
        }
      }

      // Convert comprehensive route to LatLng with enhanced sorting
      List<LatLng> actualRoutePath = [];

      try {
        // ✅ ENHANCED: Better timestamp sorting
        final sortedEntries = comprehensiveRoutePath.entries.toList()
          ..sort((a, b) {
            try {
              final aTime = a.value['timestamp'] as String;
              final bTime = b.value['timestamp'] as String;
              return aTime.compareTo(bTime);
            } catch (e) {
              // Fallback to key comparison if timestamp parsing fails
              return a.key.compareTo(b.key);
            }
          });

        for (var entry in sortedEntries) {
          if (entry.value is Map && entry.value['coordinates'] != null) {
            final coordinates = entry.value['coordinates'] as List;
            if (coordinates.length >= 2) {
              final lat = (coordinates[0] as num).toDouble();
              final lng = (coordinates[1] as num).toDouble();

              // Enhanced coordinate validation
              if (lat.abs() <= 90 &&
                  lng.abs() <= 180 &&
                  lat != 0.0 &&
                  lng != 0.0 &&
                  !lat.isNaN &&
                  !lng.isNaN &&
                  !lat.isInfinite &&
                  !lng.isInfinite) {
                actualRoutePath.add(LatLng(lat, lng));
              }
            }
          }
        }
      } catch (e) {
        print('❌ Error parsing comprehensive route path: $e');
        return;
      }

      print('📊 Enhanced validation data:');
      print('   - Assigned checkpoints: ${assignedCheckpoints.length}');
      print('   - Actual route points: ${actualRoutePath.length}');
      print(
          '   - Validation radius: ${finalValidationRadius}m (${validationRadius != null ? "override" : "from user profile"})');

      // ✅ ENHANCED: Check distance between checkpoints to adjust radius
      double adaptiveRadius = finalValidationRadius;
      if (assignedCheckpoints.length > 1) {
        double minDistance = double.infinity;
        for (int i = 0; i < assignedCheckpoints.length - 1; i++) {
          final distance = Geolocator.distanceBetween(
            assignedCheckpoints[i].latitude,
            assignedCheckpoints[i].longitude,
            assignedCheckpoints[i + 1].latitude,
            assignedCheckpoints[i + 1].longitude,
          );
          if (distance < minDistance) {
            minDistance = distance;
          }
        }

        // Use larger radius if checkpoints are far apart (but respect user custom radius)
        if (minDistance > 200 && validationRadius == null) {
          // Only auto-adjust if no override
          adaptiveRadius = min(finalValidationRadius * 1.5,
              100.0); // Max 100m for auto-adjustment
          print(
              '📏 Adjusted radius to ${adaptiveRadius}m due to checkpoint spacing');
        } else if (validationRadius != null) {
          print(
              '📏 Using override radius, no auto-adjustment: ${adaptiveRadius}m');
        } else {
          print(
              '📏 Using user custom radius, no auto-adjustment: ${adaptiveRadius}m');
        }
      }

      // Check each assigned checkpoint with enhanced logic
      List<List<double>> missedCheckpoints = [];
      List<Map<String, dynamic>> checkpointDetails = [];

      for (int i = 0; i < assignedCheckpoints.length; i++) {
        final checkpoint = assignedCheckpoints[i];
        bool checkpointVisited = false;
        double? closestDistance;
        LatLng? closestPoint;
        List<double> nearbyDistances = [];

        // Check if any actual route point is within validation radius
        for (final routePoint in actualRoutePath) {
          final distance = Geolocator.distanceBetween(
            checkpoint.latitude,
            checkpoint.longitude,
            routePoint.latitude,
            routePoint.longitude,
          );

          // Track all nearby distances for better analysis
          if (distance <= adaptiveRadius * 2) {
            nearbyDistances.add(distance);
          }

          // Track closest point for debugging
          if (closestDistance == null || distance < closestDistance) {
            closestDistance = distance;
            closestPoint = routePoint;
          }

          if (distance <= adaptiveRadius) {
            checkpointVisited = true;
            break;
          }
        }

        // ✅ ENHANCED: Additional check for very close misses (only if using default radius)
        if (!checkpointVisited &&
            closestDistance != null &&
            validationRadius == null && // Only for auto-calculated radius
            closestDistance <= adaptiveRadius * 1.1) {
          // 10% tolerance
          print(
              '⚠️ Checkpoint ${i + 1} was very close (${closestDistance.toStringAsFixed(1)}m), considering as visited');
          checkpointVisited = true;
        }

        // Store checkpoint details
        checkpointDetails.add({
          'index': i + 1,
          'checkpoint': checkpoint,
          'visited': checkpointVisited,
          'closestDistance': closestDistance,
          'closestPoint': closestPoint,
          'nearbyDistances': nearbyDistances,
        });

        if (!checkpointVisited) {
          missedCheckpoints.add([checkpoint.latitude, checkpoint.longitude]);
          print(
              '❌ Checkpoint ${i + 1} MISSED (lat: ${checkpoint.latitude}, lng: ${checkpoint.longitude})');
          if (closestDistance != null) {
            print(
                '   → Closest approach: ${closestDistance.toStringAsFixed(1)}m');
            print(
                '   → Nearby distances: ${nearbyDistances.map((d) => d.toStringAsFixed(1)).join(", ")}m');
          }
        } else {
          print(
              '✅ Checkpoint ${i + 1} visited (closest: ${closestDistance?.toStringAsFixed(1)}m)');
        }
      }

      print(
          '📊 Final validation result: ${missedCheckpoints.length} missed out of ${assignedCheckpoints.length} checkpoints');

      // ✅ ENHANCED: Only send notification if there are significant misses
      if (missedCheckpoints.isNotEmpty) {
        final missedPercentage =
            (missedCheckpoints.length / assignedCheckpoints.length) * 100;

        // ✅ More conservative notification logic for custom radius
        bool shouldSendNotification = true;

        if (validationRadius == null) {
          // User's custom radius - be more strict
          // For custom radius, send notification for any missed checkpoint above 1
          if (assignedCheckpoints.length <= 3 &&
              missedCheckpoints.length == 1) {
            shouldSendNotification = false;
            print(
                'ℹ️ Skipping notification: Only 1 missed checkpoint out of ${assignedCheckpoints.length} with custom radius (minor miss)');
          }
        } else {
          // Override radius - use original logic
          if (assignedCheckpoints.length <= 3 &&
              missedCheckpoints.length == 1) {
            shouldSendNotification = false;
            print(
                'ℹ️ Skipping notification: Only 1 missed checkpoint out of ${assignedCheckpoints.length} (minor miss)');
          } else if (missedPercentage < 20) {
            shouldSendNotification = false;
            print(
                'ℹ️ Skipping notification: Only ${missedPercentage.toStringAsFixed(1)}% missed (minor miss)');
          }
        }

        if (shouldSendNotification) {
          print('🚨 Sending missed checkpoints notification...');

          try {
            await sendMissedCheckpointsNotificationWithRadius(
              patrolTaskId: completedTask.taskId,
              officerName: completedTask.officerName.isNotEmpty
                  ? completedTask.officerName
                  : 'Petugas',
              clusterName: completedTask.clusterName.isNotEmpty
                  ? completedTask.clusterName
                  : 'Tatar',
              officerId: completedTask.userId,
              missedCheckpoints: missedCheckpoints,
              clusterId: completedTask.clusterId,
              customRadius: validationRadius,
            );

            print('✅ Missed checkpoints notification sent successfully');

            // Log detailed analysis
            await _logDetailedAnalysis(
              completedTask,
              checkpointDetails,
              missedCheckpoints.length,
              assignedCheckpoints.length,
              adaptiveRadius,
              validationRadius == null,
            );
          } catch (notificationError) {
            print(
                '❌ Failed to send missed checkpoints notification: $notificationError');
          }
        } else {
          // Still log but don't send notification
          await _logSuccessfulPatrol(
              completedTask, assignedCheckpoints.length, adaptiveRadius);
        }
      } else {
        print('✅ All checkpoints visited - no notification needed');

        // Still log successful patrol
        await _logSuccessfulPatrol(
            completedTask, assignedCheckpoints.length, adaptiveRadius);
      }
    } catch (e) {
      print('❌ Error in MissedCheckpointService: $e');
    }
  }

  // ✅ NEW: Helper method to parse validation radius
  static double? _parseValidationRadius(dynamic value) {
    if (value == null) return null;

    try {
      if (value is double) {
        return value;
      } else if (value is int) {
        return value.toDouble();
      } else if (value is num) {
        return value.toDouble();
      } else if (value is String) {
        return double.tryParse(value);
      } else {
        print('Unknown validation radius type: ${value.runtimeType}');
        return null;
      }
    } catch (e) {
      print('Error parsing validation radius: $e');
      return null;
    }
  }

  // ✅ UPDATED: Log detailed analysis with radius info
  static Future<void> _logDetailedAnalysis(
    PatrolTask task,
    List<Map<String, dynamic>> checkpointDetails,
    int missedCount,
    int totalCount,
    double usedRadius,
    bool isCustomRadius,
  ) async {
    try {
      print('📋 === CHECKPOINT ANALYSIS ===');
      print('Task ID: ${task.taskId}');
      print('Officer: ${task.officerName}');
      print('Cluster: ${task.clusterName}');
      print('Total Checkpoints: $totalCount');
      print('Missed Checkpoints: $missedCount');
      print(
          'Success Rate: ${((totalCount - missedCount) / totalCount * 100).toStringAsFixed(1)}%');
      print(
          'Validation Radius: ${usedRadius}m (${isCustomRadius ? "custom from user profile" : "override/default"})');

      for (var detail in checkpointDetails) {
        final status = detail['visited'] ? '✅ VISITED' : '❌ MISSED';
        final distance = detail['closestDistance']?.toStringAsFixed(1) ?? 'N/A';
        print('Checkpoint ${detail['index']}: $status (closest: ${distance}m)');
      }
      print('=== END ANALYSIS ===');
    } catch (e) {
      print('❌ Error logging analysis: $e');
    }
  }

  // ✅ UPDATED: Log successful patrol with radius info
  static Future<void> _logSuccessfulPatrol(
      PatrolTask task, int totalCheckpoints, double usedRadius) async {
    try {
      print('📋 === SUCCESSFUL PATROL ===');
      print('Task ID: ${task.taskId}');
      print('Officer: ${task.officerName}');
      print('Checkpoints: $totalCheckpoints/$totalCheckpoints (100%)');
      print('Distance: ${task.distance?.toStringAsFixed(1)}m');
      print('Validation Radius: ${usedRadius}m');
      print('=== END SUCCESS LOG ===');
    } catch (e) {
      print('❌ Error logging success: $e');
    }
  }
}
