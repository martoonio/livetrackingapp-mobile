import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/report.dart';
import 'package:livetrackingapp/patrol_summary_screen.dart';
import 'package:livetrackingapp/presentation/patrol/services/local_patrol_data.dart';
import 'package:livetrackingapp/presentation/patrol/services/local_patrol_service.dart';
import 'package:livetrackingapp/presentation/patrol/services/sync_service.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_bloc.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_event.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_state.dart';
import 'package:livetrackingapp/services/location_validator.dart';
import 'package:livetrackingapp/notification_utils.dart'; // Import notification_utils
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/patrol_task.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class MapScreen extends StatefulWidget {
  final PatrolTask task;
  final VoidCallback onStart;

  const MapScreen({
    super.key,
    required this.task,
    required this.onStart,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? mapController;
  Position? userCurrentLocation;
  StreamSubscription<Position>? _positionStreamSubscription;
  final Set<Marker> _markers = {};
  bool _isMapReady = false;
  late final currentState;

  bool _localIsPatrolling = false;
  String? _localPatrollingTaskId;

  bool _isInitializing = false;
  bool _hasResumedPatrol = false;

  bool _mockLocationDetected = false;
  bool _snackbarShown = false;

  Timer? _patrolTimer;
  Duration _elapsedTime = Duration.zero;
  double _totalDistance = 0;
  Position? _lastPosition;

  double _longPressProgress = 0.0;
  Timer? _longPressTimer;

  List<File> selectedPhotos = [];

  String? initialReportPhotoUrl;
  String? finalReportPhotoUrl;

  final Set<Polyline> _polylines = {};
  final List<LatLng> _routePoints = [];

  bool _isRecoveringFromLocal = false;
  LocalPatrolData? _localPatrolData;

  bool isWakeLockEnabled = false;

  // Warna untuk polyline
  static const Color _polylineColor = kbpBlue900;

  void _startLongPressAnimation(BuildContext context, PatrolState state) {
    const duration = Duration(seconds: 3);
    const interval = Duration(milliseconds: 50);
    double increment = interval.inMilliseconds / duration.inMilliseconds;

    _longPressTimer = Timer.periodic(interval, (timer) {
      setState(() {
        _longPressProgress += increment;
        if (_longPressProgress >= 1.0) {
          _longPressProgress = 1.0;
          timer.cancel();
          _handlePatrolButtonPress(context, state); // Jalankan aksi
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();

    final task = widget.task;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.task.fetchOfficerName(FirebaseDatabase.instance.ref());
      // Untuk memastikan clusterName juga terisi jika belum
      await widget.task.fetchClusterName(FirebaseDatabase.instance.ref());
      if (mounted) {
        setState(() {}); // Refresh UI after name is loaded
      }
    });

    currentState = context.read<PatrolBloc>().state;

    if (task.status == 'ongoing' || task.status == 'in_progress') {
      // We need to wait for widget to be built before triggering resume
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resumeExistingPatrol(task);
      });
    } else {}

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PatrolBloc>().add(LoadRouteData(userId: widget.task.userId));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final patrolState = context.read<PatrolBloc>().state;
      if (patrolState is PatrolLoaded && patrolState.isPatrolling) {
        _enableWakelock();
      }
    });

    _initializeMap();
  }

  Future<void> _initializeAppWithLocalRecovery() async {
    if (_isInitializing) return;
    _isInitializing = true;

    final task = widget.task;
    print('🚀 Initializing app with local recovery for task: ${task.taskId}');

    // 1. Check for local patrol data first
    _localPatrolData = LocalPatrolService.getPatrolData(task.taskId);

    if (_localPatrolData != null) {
      print('📱 Found local patrol data: ${_localPatrolData!.status}');
      await _recoverFromLocalData();
    }

    // 2. Continue with normal initialization
    await _initializeApp();

    _isInitializing = false;
  }

  Future<void> _recoverFromLocalData() async {
    if (_localPatrolData == null) return;

    setState(() {
      _isRecoveringFromLocal = true;
    });

    try {
      final localData = _localPatrolData!;

      // ✅ HANYA RECOVER JIKA BENAR-BENAR OFFLINE DAN DATA TIDAK ADA DI FIREBASE
      if (localData.status == 'started' || localData.status == 'ongoing') {
        print('📱 Local recovery: Checking if Firebase data exists...');

        bool shouldUseFirebaseData = false;

        // Check if Firebase already has this data
        try {
          final taskRef = FirebaseDatabase.instance
              .ref()
              .child('tasks/${localData.taskId}');
          final snapshot = await taskRef.get();

          if (snapshot.exists) {
            final firebaseData = snapshot.value as Map<dynamic, dynamic>;
            final firebaseStartTime = firebaseData['startTime'];

            if (firebaseStartTime != null) {
              print(
                  '✅ Firebase data exists, will use Firebase data with UI restoration');
              shouldUseFirebaseData = true;
            }
          }

          if (!shouldUseFirebaseData) {
            print('⚠️ No Firebase data found, proceeding with local recovery');
          }
        } catch (e) {
          print(
              '❌ Error checking Firebase data: $e, proceeding with local recovery');
        }

        // ✅ RESTORE UI STATE REGARDLESS OF DATA SOURCE
        print('📱 Restoring UI state from local data...');

        setState(() {
          _localIsPatrolling = true;
          _localPatrollingTaskId = localData.taskId;
          _totalDistance = localData.distance;

          // ✅ CALCULATE ELAPSED TIME FROM START TIME
          if (localData.startTime != null) {
            final startTime = DateTime.parse(localData.startTime!);
            _elapsedTime = DateTime.now().difference(startTime);
            print(
                '⏱️ Calculated elapsed time: ${_formatDuration(_elapsedTime)}');
          } else {
            _elapsedTime = Duration.zero;
          }

          // ✅ RESTORE ROUTE POINTS
          _routePoints.clear();
          if (localData.routePath.isNotEmpty) {
            final sortedEntries = localData.routePath.entries.toList()
              ..sort((a, b) => a.value['timestamp']
                  .toString()
                  .compareTo(b.value['timestamp'].toString()));

            for (var entry in sortedEntries) {
              final coordinates = entry.value['coordinates'] as List;
              _routePoints.add(LatLng(
                (coordinates[0] as num).toDouble(),
                (coordinates[1] as num).toDouble(),
              ));
            }

            // ✅ UPDATE POLYLINE IMMEDIATELY
            if (_routePoints.isNotEmpty) {
              _polylines.clear();
              _polylines.add(
                Polyline(
                  polylineId: const PolylineId('patrol_route'),
                  points: _routePoints,
                  color: _polylineColor,
                  width: 5,
                ),
              );
              print(
                  '🗺️ Restored ${_routePoints.length} route points and polyline');
            }
          }

          // ✅ RESTORE LAST POSITION
          if (localData.routePath.isNotEmpty) {
            try {
              final sortedEntries = localData.routePath.entries.toList()
                ..sort((a, b) => b.value['timestamp']
                    .toString()
                    .compareTo(a.value['timestamp'].toString()));

              if (sortedEntries.isNotEmpty) {
                final coordinates =
                    sortedEntries.first.value['coordinates'] as List;
                _lastPosition = Position(
                  latitude: (coordinates[0] as num).toDouble(),
                  longitude: (coordinates[1] as num).toDouble(),
                  timestamp: DateTime.now(),
                  accuracy: 0,
                  altitude: 0,
                  heading: 0,
                  speed: 0,
                  speedAccuracy: 0,
                  isMocked: false,
                  floor: null,
                  altitudeAccuracy: 0,
                  headingAccuracy: 0,
                );
                print(
                    '📍 Restored last position: ${_lastPosition!.latitude}, ${_lastPosition!.longitude}');
              }
            } catch (e) {
              print('❌ Error restoring last position: $e');
            }
          }
        });

        // ✅ START SYSTEMS IMMEDIATELY (CRITICAL!)
        print('🚀 Starting patrol systems...');
        _startPatrolTimer();
        _startLocationTracking();

        // ✅ DETERMINE WHICH DATA TO USE FOR BLOC
        Map<String, dynamic> routePathForBloc = {};
        DateTime startTimeForBloc = DateTime.now();
        double distanceForBloc = 0.0;

        if (shouldUseFirebaseData) {
          // Use fresh Firebase data
          if (widget.task.routePath != null) {
            routePathForBloc =
                Map<String, dynamic>.from(widget.task.routePath!);
          }
          startTimeForBloc = widget.task.startTime ?? DateTime.now();
          distanceForBloc = widget.task.distance ?? 0.0;

          print('📡 Using Firebase data for BLoC:');
          print('   - Route points: ${routePathForBloc.length}');
          print('   - Distance: $distanceForBloc');
        } else {
          // Use local data
          routePathForBloc = localData.routePath;
          startTimeForBloc = DateTime.parse(localData.startTime!);
          distanceForBloc = localData.distance;

          print('📱 Using local data for BLoC:');
          print('   - Route points: ${routePathForBloc.length}');
          print('   - Distance: $distanceForBloc');
        }

        // ✅ SYNC TO BLOC AND FIREBASE
        Future.delayed(Duration(seconds: 1), () async {
          try {
            print('🔄 Syncing recovery data to BLoC...');

            final connectivityResult = await Connectivity().checkConnectivity();
            if (connectivityResult != ConnectivityResult.none) {
              // ✅ UPDATE BLOC STATE
              if (mounted) {
                try {
                  context.read<PatrolBloc>().add(ResumePatrol(
                        task: widget.task,
                        startTime: startTimeForBloc,
                        currentDistance: distanceForBloc,
                        existingRoutePath: routePathForBloc,
                      ));

                  print('✅ Recovery data synced to BLoC');
                } catch (e) {
                  print('❌ Failed to sync recovery to BLoC: $e');
                }
              }

              // Force sync to Firebase if using local data
              if (!shouldUseFirebaseData) {
                final syncSuccess =
                    await SyncService.forceSyncPatrol(localData.taskId);
                if (syncSuccess) {
                  print(
                      '✅ Local recovery data synced to Firebase successfully');
                } else {
                  print('⚠️ Failed to sync local recovery data');
                }
              }
            }
          } catch (e) {
            print('❌ Error syncing recovery data: $e');
          }
        });

        // ✅ SHOW SUCCESS MESSAGE
        showCustomSnackbar(
          context: context,
          title: shouldUseFirebaseData
              ? 'Patroli Dilanjutkan'
              : 'Patroli Dipulihkan dari Data Lokal',
          subtitle: shouldUseFirebaseData
              ? 'Melanjutkan patroli yang sedang berlangsung'
              : 'Data lokal berhasil dipulihkan dan akan disinkronisasi',
          type: SnackbarType.success,
        );

        // ✅ ZOOM TO POLYLINE
        if (_routePoints.isNotEmpty && mapController != null) {
          Future.delayed(Duration(milliseconds: 1000), () {
            if (mounted) {
              _zoomToPolyline();
            }
          });
        }
      }
    } catch (e) {
      print('❌ Error in local recovery: $e');
      showCustomSnackbar(
        context: context,
        title: 'Gagal Memulihkan Data Lokal',
        subtitle: 'Terjadi error saat memulihkan data lokal',
        type: SnackbarType.warning,
      );
    } finally {
      setState(() {
        _isRecoveringFromLocal = false;
      });
    }
  }

  void _resetLongPressAnimation() {
    _longPressTimer?.cancel();
    setState(() {
      _longPressProgress = 0.0;
    });
  }

  void _startPatrolTimer() {
    _patrolTimer?.cancel(); // Cancel existing timer if any

    print('⏱️ Starting patrol timer...');
    print('   - Current elapsed time: ${_formatDuration(_elapsedTime)}');

    _patrolTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedTime += const Duration(seconds: 1);
        });

        // ✅ UPDATE LOCAL STORAGE EVERY MINUTE
        if (_elapsedTime.inSeconds % 60 == 0) {
          print('⏱️ Timer milestone: ${_formatDuration(_elapsedTime)}');
          _updateLocalPatrolTime();
        }
      } else {
        print('⚠️ Widget not mounted, stopping timer');
        timer.cancel();
      }
    });

    print('✅ Patrol timer started successfully');
  }

// ✅ NEW METHOD: Update local storage with current time
  void _updateLocalPatrolTime() async {
    try {
      final localData = LocalPatrolService.getPatrolData(widget.task.taskId);
      if (localData != null) {
        localData.elapsedTimeSeconds = _elapsedTime.inSeconds;
        localData.distance = _totalDistance;
        localData.lastUpdated = DateTime.now().toIso8601String();
        await localData.save();
      }
    } catch (e) {
      print('❌ Error updating local patrol time: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  void _updateDistance(Position newPosition) {
    if (_lastPosition != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );
      _totalDistance += distanceInMeters;

      // Simpan totalDistance ke backend
      final state = context.read<PatrolBloc>().state;
      if (state is PatrolLoaded && state.task != null) {
        context.read<PatrolBloc>().add(UpdateTask(
              taskId: state.task!.taskId,
              updates: {'distance': _totalDistance},
            ));
      }
    } else {}
    _lastPosition = newPosition;
  }

  void _enableWakelock() async {
    isWakeLockEnabled = await WakelockPlus.enabled;
    if (!isWakeLockEnabled) {
      WakelockPlus.enable();
      isWakeLockEnabled = true;
    }
  }

  void _disableWakelock() async {
    if (isWakeLockEnabled) {
      WakelockPlus.disable();
      isWakeLockEnabled = false;
    }
  }

  bool _canStartPatrol() {
    // Cek koneksi internet
    final state = context.read<PatrolBloc>().state;
    final isOffline = state is PatrolLoaded ? state.isOffline : false;

    // Jika offline dan belum patroli, maka tidak bisa mulai
    if (isOffline) {
      // Kecuali jika patroli sudah berjalan
      if (widget.task.status == 'ongoing' ||
          widget.task.status == 'in_progress') {
        return true; // Boleh menyelesaikan patroli walau offline
      }
      return false; // Tidak bisa mulai patroli jika offline
    }

    // Jika patroli sedang berlangsung, selalu return true
    if (state is PatrolLoaded && state.isPatrolling) return true;

    // Jika tidak ada jadwal mulai, bisa langsung mulai
    if (widget.task.assignedStartTime == null) return true;

    // Hitung selisih waktu sekarang dengan jadwal mulai
    final now = DateTime.now();
    final timeDifference = widget.task.assignedStartTime!.difference(now);

    // Bisa mulai jika kurang dari atau sama dengan 10 menit sebelum jadwal
    return timeDifference.inMinutes <= 10;
  }

// Tambahkan method ini untuk mendapatkan waktu tunggu yang tersisa
  String _getRemainingWaitTime() {
    if (widget.task.assignedStartTime == null) return '';

    final now = DateTime.now();
    final timeDifference = widget.task.assignedStartTime!.difference(now);

    if (timeDifference.inHours > 0) {
      return '${timeDifference.inHours} jam ${timeDifference.inMinutes % 60} menit lagi';
    } else {
      return '${timeDifference.inMinutes} menit lagi';
    }
  }

  // ✅ Centralized initialization method
  Future<void> _initializeApp() async {
    if (_isInitializing) return;
    _isInitializing = true;

    final task = widget.task;
    print(
        '🚀 Initializing app for task: ${task.taskId}, status: ${task.status}');

    // ✅ PERBAIKAN: Enhanced logging untuk debugging
    print('📊 Task details:');
    print('   - Task ID: ${task.taskId}');
    print('   - Status: ${task.status}');
    print('   - Start time: ${task.startTime}');
    print('   - Distance: ${task.distance}');
    print('   - Route path: ${task.routePath?.length ?? 0} points');
    print('   - Officer: ${task.officerName}');

    // 1. Load officer and cluster names first
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.task.fetchOfficerName(FirebaseDatabase.instance.ref());
      await widget.task.fetchClusterName(FirebaseDatabase.instance.ref());
      if (mounted) {
        setState(() {}); // Refresh UI after name is loaded
      }
    });

    // ✅ PERBAIKAN: Enhanced detection untuk ongoing patrol
    final isOngoingPatrol = _isTaskOngoing(task);
    final hasLocalPatrolData = _localPatrolData != null;

    print('🔍 Patrol status check:');
    print('   - Is ongoing: $isOngoingPatrol');
    print('   - Has local data: $hasLocalPatrolData');
    print('   - Has resumed before: $_hasResumedPatrol');
    print('   - Local state: $_localIsPatrolling');

    // ✅ RESUME HANYA JIKA BELUM RECOVERY LOCAL DAN BELUM RESUME
    if (isOngoingPatrol &&
        !_hasResumedPatrol &&
        !hasLocalPatrolData &&
        !_localIsPatrolling) {
      print(
          '📍 Task is ongoing and no local recovery done, setting up resume...');

      // ✅ Set local state SYNCHRONOUSLY before any async operations
      setState(() {
        _localIsPatrolling = true;
        _localPatrollingTaskId = task.taskId;
        _hasResumedPatrol = true;
      });

      // ✅ Resume patrol after a frame to ensure UI is stable
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(Duration(milliseconds: 100));
        if (mounted && _hasResumedPatrol && !hasLocalPatrolData) {
          _resumeExistingPatrol(task);
        }
      });
    } else if (_localIsPatrolling) {
      print('📍 Local state already active, skipping resume');
    } else {
      print('📍 Task not ongoing or already resumed, status: ${task.status}');
    }

    // 3. Initialize other components
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context
            .read<PatrolBloc>()
            .add(LoadRouteData(userId: widget.task.userId));
      }
    });

    // 4. Check wakelock
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final patrolState = context.read<PatrolBloc>().state;
      if (patrolState is PatrolLoaded && patrolState.isPatrolling) {
        _enableWakelock();
      }
    });

    // 5. Initialize map
    _initializeMap();

    _isInitializing = false;
  }

  bool _isTaskOngoing(PatrolTask task) {
    // Cek apakah task sudah dimulai dan belum selesai
    if (task.startTime != null &&
        (task.status == 'ongoing' || task.status == 'in_progress')) {
      return true;
    }
    return false;
  }

  void _resumeExistingPatrol(PatrolTask task) {
    if (task.startTime == null) {
      return;
    }

    // Get route path data
    final routePath = task.routePath as Map<dynamic, dynamic>?;

    // Simpan route path yang sudah ada dengan struktur yang benar
    Map<String, dynamic> existingRoutePath = {};
    if (routePath != null) {
      // Konversi ke Map<String, dynamic> untuk konsistensi
      routePath.forEach((key, value) {
        if (value is Map) {
          Map<String, dynamic> pointData = {};
          value.forEach((k, v) {
            pointData[k.toString()] = v;
          });
          existingRoutePath[key.toString()] = pointData;
        } else {
          existingRoutePath[key.toString()] = value;
        }
      });
    }

    // Resume patrol in bloc with existing route path
    context.read<PatrolBloc>().add(ResumePatrol(
          task: task,
          startTime: task.startTime!,
          currentDistance: task.distance ?? 0.0,
          existingRoutePath:
              existingRoutePath, // Passing the existing route path
        ));

    // Set local variables
    setState(() {
      _elapsedTime = DateTime.now().difference(task.startTime!);
      _totalDistance = task.distance ?? 0.0;

      // Inisialisasi _routePoints untuk polyline
      _routePoints.clear();
      if (routePath != null && routePath.isNotEmpty) {
        try {
          // Sort entries by timestamp to ensure correct order
          final List<MapEntry<dynamic, dynamic>> sortedEntries =
              routePath.entries.toList()
                ..sort((a, b) => (a.value['timestamp'].toString())
                    .compareTo(b.value['timestamp'].toString()));

          // Add points to _routePoints for polyline display
          for (var entry in sortedEntries) {
            if (entry.value is Map && entry.value['coordinates'] != null) {
              final coordinates = entry.value['coordinates'] as List;
              if (coordinates.length >= 2) {
                _routePoints.add(LatLng(
                  (coordinates[0] as num).toDouble(),
                  (coordinates[1] as num).toDouble(),
                ));
              }
            }
          }
        } catch (e) {}
      }

      // Update lastPosition to the most recent point if available
      if (routePath != null && routePath.isNotEmpty) {
        try {
          // Get the most recent point by timestamp
          final sortedEntries = routePath.entries.toList()
            ..sort((a, b) => (b.value['timestamp'].toString())
                .compareTo(a.value['timestamp'].toString()));

          if (sortedEntries.isNotEmpty) {
            final coordinates =
                sortedEntries.first.value['coordinates'] as List;
            _lastPosition = Position(
              latitude: (coordinates[0] as num).toDouble(),
              longitude: (coordinates[1] as num).toDouble(),
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              isMocked: false,
              floor: null,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            );
          }
        } catch (e) {}
      }
    });

    // Start systems
    _startPatrolTimer();
    _startLocationTracking();

    // Load saved route if exists
    if (routePath != null && routePath.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _displaySavedRoute(routePath.cast<String, dynamic>());
        setState(() {
          _polylines.clear();
          if (_routePoints.isNotEmpty) {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('patrol_route'),
                points: _routePoints,
                color: _polylineColor,
                width: 5,
              ),
            );
          }
        });

        // Zoom to show the entire route
        if (_routePoints.isNotEmpty && mapController != null) {
          _zoomToPolyline();
        }
      });
    }

    // Notify user
    showCustomSnackbar(
      context: context,
      title: 'Patroli Dilanjutkan',
      subtitle: 'Melanjutkan patroli yang sedang berlangsung',
      type: SnackbarType.success,
    );
  }

  Future<String> _uploadPhotoToFirebase(File imageFile, String fileName) async {
    // Simpan referensi context di awal method
    final BuildContext currentContext = context;

    try {
      // Reference to Firebase Storage
      final storageRef = FirebaseStorage.instance.ref();
      final photoRef = storageRef.child('patrol_reports/$fileName');

      // Buat upload task
      final uploadTask = photoRef.putFile(imageFile);

      // Completer untuk menunggu task selesai
      final completer = Completer<void>();

      // Dialog reference holder
      BuildContext? dialogContextRef;

      // Tampilkan dialog progress yang akan menutup secara otomatis
      if (mounted) {
        await showDialog(
          context: currentContext,
          barrierDismissible: false,
          builder: (dialogContext) {
            // Simpan reference ke dialog context
            dialogContextRef = dialogContext;

            return StatefulBuilder(
              builder: (context, setDialogState) {
                // Gunakan ValueNotifier untuk progress
                final uploadProgress = ValueNotifier<double>(0.0);

                // Setup listener untuk progress upload
                uploadTask.snapshotEvents.listen(
                  (TaskSnapshot snapshot) {
                    double progress =
                        snapshot.bytesTransferred / snapshot.totalBytes;
                    uploadProgress.value = progress;

                    // Tutup dialog otomatis saat upload berhasil
                    if (snapshot.state == TaskState.success) {
                      Future.delayed(const Duration(milliseconds: 500), () {
                        // Pastikan dialog masih ada sebelum mencoba menutupnya
                        if (dialogContextRef != null &&
                            Navigator.canPop(dialogContextRef!)) {
                          Navigator.of(dialogContextRef!).pop();
                        }

                        if (!completer.isCompleted) {
                          completer.complete();
                        }
                      });
                    }
                  },
                  onError: (e) {
                    // Pastikan dialog masih ada sebelum mencoba menutupnya
                    if (dialogContextRef != null &&
                        Navigator.canPop(dialogContextRef!)) {
                      Navigator.of(dialogContextRef!).pop();
                    }

                    if (!completer.isCompleted) {
                      completer.completeError(e);
                    }
                  },
                );

                return ValueListenableBuilder<double>(
                  valueListenable: uploadProgress,
                  builder: (context, progress, _) {
                    return Dialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Icon dengan progress
                            SizedBox(
                              height: 80,
                              width: 80,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: progress,
                                    strokeWidth: 6,
                                    backgroundColor: kbpBlue100,
                                    color: kbpBlue900,
                                  ),
                                  Icon(
                                    Icons.cloud_upload,
                                    size: 36,
                                    color: kbpBlue900,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            Text(
                              'Mengunggah Foto',
                              style: boldTextStyle(size: 18, color: kbpBlue900),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mohon tunggu sementara foto sedang diunggah...',
                              style:
                                  regularTextStyle(size: 14, color: neutral700),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),

                            // Progress bar
                            Container(
                              height: 8,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: kbpBlue100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Stack(
                                children: [
                                  FractionallySizedBox(
                                    widthFactor: progress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: kbpBlue900,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: semiBoldTextStyle(
                                  size: 14, color: kbpBlue900),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      }

      // Tunggu hingga upload selesai
      await completer.future;

      // Dapatkan URL download
      final TaskSnapshot taskSnapshot = await uploadTask;
      final String downloadUrl = await taskSnapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload photo: $e');
    }
  }

  void _startLocationTracking() async {
    String timeNow = DateTime.now().toIso8601String();
    print('🚀 Starting location tracking at: $timeNow');

    // ✅ CANCEL EXISTING SUBSCRIPTION FIRST
    _positionStreamSubscription?.cancel();

    // ✅ ADD DELAY TO ENSURE SYSTEMS ARE READY
    await Future.delayed(Duration(milliseconds: 500));

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) async {
        if (mounted) {
          print(
              '📍 Location received: ${position.latitude}, ${position.longitude}');

          // Update UI state
          setState(() {
            userCurrentLocation = position;
            if (mapController != null) {
              _updateUserMarker(position);
            }
          });

          final actuallyPatrolling = _isCurrentlyPatrolling();
          print('🔍 Currently patrolling check: $actuallyPatrolling');

          if (actuallyPatrolling) {
            final timestamp = DateTime.now();

            // ✅ CRITICAL: Update distance and route locally FIRST
            print('📊 Updating distance and route...');
            _updateDistance(position);
            _updatePolyline(position);

            // ✅ Save to local storage IMMEDIATELY
            try {
              await LocalPatrolService.updatePatrolLocation(
                taskId: widget.task.taskId,
                position: position,
                timestamp: timestamp,
                totalDistance: _totalDistance,
                elapsedSeconds: _elapsedTime.inSeconds,
              );
              print('💾 Location saved to local storage successfully');
            } catch (e) {
              print('❌ Failed to save location to local storage: $e');
            }

            // ✅ Try to update Firebase (don't block if it fails)
            try {
              context.read<PatrolBloc>().add(UpdatePatrolLocation(
                    position: position,
                    timestamp: timestamp,
                  ));
              print('📡 Location sent to BLoC');
            } catch (e) {
              print('❌ Failed to update Firebase location: $e');
              // Continue with local tracking
            }

            // Handle mock location detection
            final isMocked = await LocationValidator.isLocationMocked(position);
            if (isMocked) {
              await _handleMockLocationDetection(position);
            }
          } else {
            print('⚠️ Not patrolling, skipping location processing');
          }
        }
      },
      onError: (error) {
        print('❌ Location stream error: $error');
      },
    );

    print('✅ Location tracking stream started');
  }

  Future<void> _handleMockLocationDetection(Position position) async {
    try {
      final localData = LocalPatrolService.getPatrolData(widget.task.taskId);
      final newCount = (localData?.mockLocationCount ?? 0) + 1;

      // Update local storage
      await LocalPatrolService.updateMockLocationDetection(
        taskId: widget.task.taskId,
        detected: true,
        count: newCount,
      );

      // Update UI
      setState(() {
        _mockLocationDetected = true;
      });

      // Try to update Firebase
      try {
        final mockData = {
          'timestamp': DateTime.now().toIso8601String(),
          'coordinates': [position.latitude, position.longitude],
          'accuracy': position.accuracy,
          'count': newCount,
        };

        final taskRef = FirebaseDatabase.instance
            .ref()
            .child('tasks/${widget.task.taskId}');

        await taskRef.update({
          'mockLocationDetected': true,
          'mockLocationCount': newCount,
          'lastMockDetection': mockData['timestamp'],
        });

        await taskRef.child('mock_detections').push().set(mockData);
      } catch (e) {
        print('❌ Failed to update mock location in Firebase: $e');
      }

      // Show warning to user
      if (!_snackbarShown) {
        _snackbarShown = true;
        showCustomSnackbar(
          context: context,
          title: 'Fake GPS Terdeteksi!',
          subtitle:
              'Penggunaan fake GPS tidak diperbolehkan dan akan dilaporkan',
          type: SnackbarType.danger,
        );

        Future.delayed(Duration(seconds: 6), () {
          _snackbarShown = false;
        });
      }
    } catch (e) {
      print('❌ Error handling mock location: $e');
    }
  }

  void _startPatrol(BuildContext context) async {
    final startTime = DateTime.now();

    print('🚀 Starting patrol for task: ${widget.task.taskId}');

    try {
      // ✅ 1. UPDATE LOCAL STATE IMMEDIATELY (sudah dilakukan di dialog)
      // Pastikan state sudah diset
      if (!_localIsPatrolling) {
        setState(() {
          _localIsPatrolling = true;
          _localPatrollingTaskId = widget.task.taskId;
        });
      }

      // ✅ 2. START LOCAL SYSTEMS IMMEDIATELY
      await Future.delayed(
          const Duration(milliseconds: 100)); // Small delay for UI stability
      _startPatrolTimer();
      _elapsedTime = Duration.zero;
      _totalDistance = 0;
      _lastPosition = null;
      _startLocationTracking();
      widget.onStart();

      // ✅ 3. UPDATE FIREBASE ASYNC (NON-BLOCKING)
      try {
        // Update task status in Firebase
        context.read<PatrolBloc>().add(UpdateTask(
              taskId: widget.task.taskId,
              updates: {
                'status': 'ongoing',
                'startTime': startTime.toIso8601String(),
              },
            ));

        // Start patrol in bloc
        context.read<PatrolBloc>().add(
              StartPatrol(
                task: widget.task,
                startTime: startTime,
              ),
            );

        // Update local status to ongoing
        await LocalPatrolService.updatePatrolToOngoing(widget.task.taskId);

        print('✅ Patrol started in Firebase successfully');
      } catch (firebaseError) {
        print('❌ Error starting patrol in Firebase: $firebaseError');
        // Show warning but don't stop patrol
        if (mounted) {
          showCustomSnackbar(
            context: context,
            title: 'Peringatan',
            subtitle:
                'Patroli berjalan offline, data akan disinkronisasi nanti',
            type: SnackbarType.warning,
          );
        }
      }
    } catch (e) {
      print('❌ Critical error in _startPatrol: $e');

      // Rollback on critical error
      if (mounted) {
        setState(() {
          _localIsPatrolling = false;
          _localPatrollingTaskId = null;
        });

        _patrolTimer?.cancel();
        _positionStreamSubscription?.cancel();

        showCustomSnackbar(
          context: context,
          title: 'Gagal memulai patroli',
          subtitle: 'Terjadi kesalahan sistem: $e',
          type: SnackbarType.danger,
        );
      }
    }
  }

  void _handlePatrolButtonPress(BuildContext context, PatrolState state) async {
    final isOffline = state is PatrolLoaded ? state.isOffline : false;

    final isPatrollingInBloc = state is PatrolLoaded && state.isPatrolling;
    final isPatrollingInTask =
        widget.task.status == 'ongoing' || widget.task.status == 'in_progress';
    final isPatrolActive =
        isPatrollingInBloc || isPatrollingInTask || _localIsPatrolling;

    // 🔍 DEBUG: Compare different state detection methods
    final isPatrollingViaFunction = _isCurrentlyPatrolling();

    print('🔍 PATROL STATE DEBUG:');
    print('   - BLoC state: $isPatrollingInBloc');
    print('   - Task status: $isPatrollingInTask (${widget.task.status})');
    print('   - Local state: $_localIsPatrolling');
    print('   - isPatrolActive (old logic): $isPatrolActive');
    print('   - _isCurrentlyPatrolling(): $isPatrollingViaFunction');
    print('   - Connectivity: ${isOffline ? "OFFLINE" : "ONLINE"}');

    if (isOffline && !isPatrolActive) {
      showCustomSnackbar(
        context: context,
        title: 'Tidak ada koneksi internet',
        subtitle: 'Memulai patroli memerlukan koneksi internet',
        type: SnackbarType.danger,
      );
      _resetLongPressAnimation();
      return;
    }

    if (!_canStartPatrol() && !isPatrolActive) {
      showCustomSnackbar(
        context: context,
        title: 'Belum Waktunya Patroli',
        subtitle:
            'Anda dapat memulai patroli 10 menit sebelum jadwal dimulai (${_getRemainingWaitTime()})',
        type: SnackbarType.warning,
      );
      _resetLongPressAnimation();
      return;
    }

    if (_isCurrentlyPatrolling()) {
      if (state is PatrolLoaded) {
        await _stopPatrol(context, state);
      } else {
        final tempState = PatrolLoaded(
          task: widget.task,
          isPatrolling: true,
          distance: _totalDistance,
        );
        await _stopPatrol(context, tempState);
      }
    } else {
      _showInitialReportDialog(context);
      _resetLongPressAnimation();
    }
  }

  Widget _buildPatrolButtonUI(bool isPatrolling) {
    final state = context.read<PatrolBloc>().state;
    final isOffline = state is PatrolLoaded ? state.isOffline : false;
    final actuallyPatrolling = _isCurrentlyPatrolling();

    final canStartNow = _canStartPatrol();

    if (isOffline && !actuallyPatrolling) {
      return Container(
        width: 120,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(12),
          color: neutral500,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_off,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              'Offline Mode',
              style: semiBoldTextStyle(size: 12, color: Colors.white),
            ),
            Text(
              'Koneksi diperlukan',
              style: regularTextStyle(size: 10, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (!canStartNow && !actuallyPatrolling) {
      return Container(
        width: 120,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(12),
          color: neutral500,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.timer,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              'Tunggu',
              style: semiBoldTextStyle(size: 12, color: Colors.white),
            ),
            Text(
              _getRemainingWaitTime(),
              style: regularTextStyle(size: 10, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        // Tampilkan tooltip manual saat tap biasa
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              actuallyPatrolling
                  ? 'Tekan 3 detik untuk selesai'
                  : isOffline
                      ? 'Mode offline, koneksi diperlukan'
                      : 'Tekan 3 detik untuk mulai',
              style: mediumTextStyle(color: Colors.white),
            ),
            backgroundColor: actuallyPatrolling
                ? dangerR300
                : isOffline
                    ? neutral500
                    : kbpBlue900,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
      onLongPressStart: (_) {
        if (isOffline && !actuallyPatrolling)
          return; // Disable long press jika offline dan belum mulai
        final state = context.read<PatrolBloc>().state;
        _startLongPressAnimation(context, state);
      },
      onLongPressEnd: (_) {
        _resetLongPressAnimation();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Progress indicator
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0.0,
              end: _longPressProgress,
            ),
            duration: const Duration(milliseconds: 50),
            builder: (context, value, child) {
              return SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 6.0,
                  color: actuallyPatrolling
                      ? dangerR300
                      : isOffline
                          ? neutral500
                          : successG300,
                  backgroundColor: actuallyPatrolling
                      ? dangerR300.withOpacity(0.3)
                      : isOffline
                          ? neutral500.withOpacity(0.3)
                          : successG300.withOpacity(0.3),
                ),
              );
            },
          ),
          // Tombol
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: actuallyPatrolling
                  ? dangerR300
                  : isOffline
                      ? neutral500
                      : successG300,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                actuallyPatrolling
                    ? Icons.stop
                    : isOffline
                        ? Icons.wifi_off
                        : Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }

// Tambahkan metode untuk menampilkan dialog laporan awal
  Future<bool> _showInitialReportDialog(BuildContext context) async {
    File? capturedImage;
    final noteController = TextEditingController();
    bool isSubmitting = false;
    bool result = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (statefulContext, setState) {
            return WillPopScope(
              onWillPop: () async {
                bool exitConfirmed = await showDialog(
                  context: statefulContext,
                  builder: (context) => AlertDialog(
                    title: Text(
                      'Batalkan Memulai Patroli?',
                      style: boldTextStyle(size: 18),
                    ),
                    content: Text(
                      'Anda akan membatalkan memulai patroli. Yakin ingin keluar?',
                      style: regularTextStyle(size: 14),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          'Tidak',
                          style: mediumTextStyle(color: kbpBlue900),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kbpBlue900,
                        ),
                        child: Text(
                          'Ya, Batalkan',
                          style: mediumTextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );
                return exitConfirmed;
              },
              child: Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Dialog title
                      Row(
                        children: [
                          const Icon(Icons.play_circle_filled,
                              color: successG500, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mulai Patroli',
                                  style: boldTextStyle(
                                      size: 18, color: kbpBlue900),
                                  textAlign: TextAlign.left,
                                ),
                                Text(
                                  'Ambil foto sebagai bukti awal patroli',
                                  style: regularTextStyle(
                                      size: 14, color: neutral700),
                                  textAlign: TextAlign.left,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Foto preview container
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: kbpBlue100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kbpBlue300),
                        ),
                        child: capturedImage == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    size: 48,
                                    color: kbpBlue700,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Foto wajib diambil',
                                    style: mediumTextStyle(color: kbpBlue700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Pastikan lokasi terlihat dengan jelas',
                                    style: regularTextStyle(
                                        color: kbpBlue700, size: 12),
                                  ),
                                ],
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Image.file(
                                  capturedImage!,
                                  width: double.infinity,
                                  height: 200,
                                  fit: BoxFit.cover,
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Tombol ambil foto
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.camera_alt),
                          label: Text(
                            capturedImage == null
                                ? 'Ambil Foto'
                                : 'Ambil Ulang',
                            style: mediumTextStyle(color: Colors.white),
                          ),
                          onPressed: () async {
                            try {
                              final ImagePicker picker = ImagePicker();
                              final XFile? photo = await picker.pickImage(
                                source: ImageSource.camera,
                                preferredCameraDevice: CameraDevice.rear,
                                maxWidth: 1024,
                                maxHeight: 1024,
                                imageQuality: 80,
                              );

                              if (photo != null) {
                                setState(() {
                                  capturedImage = File(photo.path);
                                });
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue900,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Catatan tambahan
                      TextField(
                        controller: noteController,
                        decoration: InputDecoration(
                          labelText: 'Catatan Awal Patroli (Opsional)',
                          labelStyle: regularTextStyle(color: neutral600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: 'Tambahkan catatan sebelum memulai patroli',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 24),

                      // Button baris
                      Row(
                        children: [
                          // Tombol Batal
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      bool exit = await showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(
                                            'Batalkan Mulai Patroli?',
                                            style: boldTextStyle(size: 18),
                                          ),
                                          content: Text(
                                            'Jika Anda keluar, patroli tidak akan dimulai. Yakin ingin keluar?',
                                            style: regularTextStyle(size: 14),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: Text(
                                                'Tidak',
                                                style: mediumTextStyle(
                                                    color: kbpBlue900),
                                              ),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: kbpBlue900,
                                              ),
                                              child: Text(
                                                'Ya, Batalkan',
                                                style: mediumTextStyle(
                                                    color: Colors.white),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (exit) {
                                        Navigator.pop(dialogContext, false);
                                      }
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: neutral700,
                                side: BorderSide(color: neutral700),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                'Batal',
                                style: mediumTextStyle(color: neutral700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Tombol Mulai Patroli
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSubmitting || capturedImage == null
                                  ? null
                                  : () async {
                                      setState(() {
                                        isSubmitting = true;
                                      });

                                      try {
                                        // ✅ 1. SET STATE PATROLI DIMULAI DULU SEBELUM UPLOAD
                                        // Ini untuk memastikan button UI berubah ke "stop" meskipun upload gagal
                                        if (mounted) {
                                          this.setState(() {
                                            _localIsPatrolling = true;
                                            _localPatrollingTaskId =
                                                widget.task.taskId;
                                          });
                                        }

                                        // ✅ 2. SAVE TO LOCAL STORAGE IMMEDIATELY
                                        await LocalPatrolService
                                            .savePatrolStart(
                                          taskId: widget.task.taskId,
                                          userId: widget.task.userId,
                                          startTime: DateTime.now(),
                                          initialPhotoUrl:
                                              null, // Set null dulu, akan diupdate setelah upload
                                        );

                                        // ✅ 3. MULAI PATROLI SYSTEMS DULU
                                        // Jangan tunggu upload foto selesai
                                        if (mounted) {
                                          _startPatrol(context);
                                        }

                                        String? uploadedPhotoUrl;

                                        // ✅ 4. UPLOAD FOTO (ASYNC, TIDAK MENGHALANGI PATROLI)
                                        try {
                                          final fileName =
                                              'initial_report_${widget.task.taskId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                          uploadedPhotoUrl =
                                              await _uploadPhotoToFirebase(
                                                  capturedImage!, fileName);

                                          // Update local storage dengan URL foto
                                          final localData =
                                              LocalPatrolService.getPatrolData(
                                                  widget.task.taskId);
                                          if (localData != null) {
                                            localData.initialReportPhotoUrl =
                                                uploadedPhotoUrl;
                                            await localData.save();
                                          }

                                          if (mounted) {
                                            setState(() {
                                              initialReportPhotoUrl =
                                                  uploadedPhotoUrl;
                                            });
                                          }

                                          print(
                                              '✅ Initial report photo uploaded successfully: $uploadedPhotoUrl');
                                        } catch (uploadError) {
                                          print(
                                              '❌ Failed to upload initial photo: $uploadError');
                                          // Patroli tetap lanjut meskipun upload foto gagal

                                          // Simpan foto ke local storage untuk diupload nanti
                                          try {
                                            final directory = Directory(
                                                '${(await getApplicationDocumentsDirectory()).path}/pending_uploads');
                                            if (!await directory.exists()) {
                                              await directory.create(
                                                  recursive: true);
                                            }

                                            final localPhotoPath =
                                                '${directory.path}/initial_${widget.task.taskId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                            await capturedImage!
                                                .copy(localPhotoPath);

                                            // Update local storage dengan path lokal
                                            final localData = LocalPatrolService
                                                .getPatrolData(
                                                    widget.task.taskId);
                                            if (localData != null) {
                                              localData.initialReportPhotoUrl =
                                                  localPhotoPath; // Simpan path lokal
                                              await localData.save();
                                            }

                                            print(
                                                '📱 Initial photo saved locally: $localPhotoPath');
                                          } catch (localSaveError) {
                                            print(
                                                '❌ Failed to save photo locally: $localSaveError');
                                          }
                                        }

                                        // ✅ 5. SUBMIT INITIAL REPORT TO FIREBASE (JIKA ADA FOTO)
                                        if (uploadedPhotoUrl != null) {
                                          try {
                                            context
                                                .read<PatrolBloc>()
                                                .add(SubmitInitialReport(
                                                  photoUrl: uploadedPhotoUrl,
                                                  note: noteController.text
                                                      .trim(),
                                                  reportTime: DateTime.now(),
                                                ));
                                            print(
                                                '✅ Initial report submitted to Firebase');
                                          } catch (e) {
                                            print(
                                                '❌ Failed to submit initial report to Firebase: $e');
                                          }
                                        }

                                        if (mounted) {
                                          setState(() {
                                            isSubmitting = false;
                                          });
                                        }

                                        result = true;

                                        // ✅ 6. CLOSE DIALOG
                                        if (Navigator.canPop(context)) {
                                          Navigator.pop(context, true);
                                        }

                                        // ✅ 7. SHOW SUCCESS MESSAGE
                                        if (mounted) {
                                          showCustomSnackbar(
                                            context: context,
                                            title: uploadedPhotoUrl != null
                                                ? 'Patroli dimulai'
                                                : 'Patroli dimulai (foto akan diupload nanti)',
                                            subtitle: uploadedPhotoUrl != null
                                                ? 'Laporan awal berhasil dikirim'
                                                : 'Foto akan dikirim saat koneksi stabil',
                                            type: SnackbarType.success,
                                          );

                                          // ✅ 8. TRANSITION FROM LOCAL STATE SETELAH DELAY
                                          Future.delayed(Duration(seconds: 3),
                                              () {
                                            if (mounted) {
                                              this.setState(() {
                                                _localIsPatrolling = false;
                                                _localPatrollingTaskId = null;
                                              });
                                            }
                                          });
                                        }
                                      } catch (e) {
                                        // ✅ HANDLE CRITICAL ERROR - ROLLBACK STATE
                                        print(
                                            '❌ Critical error in initial report: $e');

                                        if (mounted) {
                                          setState(() {
                                            isSubmitting = false;
                                          });

                                          // Rollback local state
                                          this.setState(() {
                                            _localIsPatrolling = false;
                                            _localPatrollingTaskId = null;
                                          });

                                          // Stop patrol systems
                                          _patrolTimer?.cancel();
                                          _positionStreamSubscription?.cancel();

                                          showCustomSnackbar(
                                            context: context,
                                            title: 'Gagal memulai patroli',
                                            subtitle: 'Terjadi kesalahan: $e',
                                            type: SnackbarType.danger,
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: successG500,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Mulai Patroli',
                                      style: semiBoldTextStyle(
                                          color: Colors.white),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }

  void _showReportDialog(BuildContext context) {
    final TextEditingController kejadianController = TextEditingController();
    final TextEditingController catatanController = TextEditingController();

    Future<void> pickImagesFromCamera() async {
      try {
        final pickedFile = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        if (pickedFile != null) {
          setState(() {
            selectedPhotos.add(File(pickedFile.path));
          });
        }
      } catch (e) {}
    }

    // Buat dialog di dalam showDialog
    showDialog(
      context: context,
      // PENTING: Set ini ke true untuk memungkinkan tap di luar menutup dialog
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // 1. Gunakan SingleChildScrollView untuk memungkinkan scrolling saat keyboard muncul
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              // 2. Gunakan insetPadding untuk memastikan dialog tidak terlalu besar
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                // 3. Batasi ukuran dialog
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 4. Header tetap di atas
                    Padding(
                      padding: const EdgeInsets.only(
                          top: 24, left: 24, right: 24, bottom: 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Laporan Kejadian',
                            style: boldTextStyle(size: 18, color: kbpBlue900),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: kbpBlue900),
                            onPressed: () {
                              Navigator.pop(context);
                              selectedPhotos.clear();
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),

                    // 5. Konten scrollable
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Input Kejadian
                            Text(
                              'Kejadian',
                              style: semiBoldTextStyle(size: 14),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: kejadianController,
                              decoration: InputDecoration(
                                hintText: 'Judul kejadian...',
                                hintStyle: regularTextStyle(color: Colors.grey),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: kbpBlue300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: kbpBlue300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: kbpBlue900, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Input Catatan
                            Text(
                              'Catatan',
                              style: semiBoldTextStyle(size: 14),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: catatanController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: 'Deskripsi kejadian...',
                                hintStyle: regularTextStyle(color: Colors.grey),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: kbpBlue300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: kbpBlue300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: kbpBlue900, width: 2),
                                ),
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Bukti Kejadian
                            Text(
                              'Bukti Kejadian',
                              style: semiBoldTextStyle(size: 14),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 100,
                              decoration: BoxDecoration(
                                border: Border.all(color: kbpBlue300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  // Tombol untuk menambah foto
                                  GestureDetector(
                                    onTap: () async {
                                      await pickImagesFromCamera();
                                      setState(
                                          () {}); // Pastikan dialog diperbarui
                                    },
                                    child: Container(
                                      width: 80,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: kbpBlue900),
                                        borderRadius: BorderRadius.circular(8),
                                        color: kbpBlue100,
                                      ),
                                      child: const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.camera_alt,
                                            size: 32,
                                            color: kbpBlue900,
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Tambah Foto',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: kbpBlue900,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Foto yang dipilih
                                  ...selectedPhotos.map((photo) {
                                    return Container(
                                      width: 80,
                                      height: 80,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: kbpBlue300),
                                      ),
                                      child: Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                            child: Image.file(
                                              photo,
                                              width: 80,
                                              height: 80,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  selectedPhotos.remove(photo);
                                                });
                                              },
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.white
                                                      .withOpacity(0.7),
                                                ),
                                                padding:
                                                    const EdgeInsets.all(4),
                                                child: const Icon(
                                                  Icons.close,
                                                  color: dangerR300,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Button Kirim Laporan
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (kejadianController.text.isNotEmpty &&
                                      catatanController.text.isNotEmpty &&
                                      selectedPhotos.isNotEmpty) {
                                    // Cek koneksi internet terlebih dahulu
                                    final connectivityResult =
                                        await Connectivity()
                                            .checkConnectivity();
                                    final isOffline = connectivityResult ==
                                        ConnectivityResult.none;

                                    // Tampilkan loading dialog dengan progress
                                    BuildContext? loadingDialogContext;
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (dialogContext) {
                                        loadingDialogContext = dialogContext;
                                        return WillPopScope(
                                          onWillPop: () async => false,
                                          child: AlertDialog(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(height: 16),
                                                const CircularProgressIndicator(
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(kbpBlue900),
                                                ),
                                                const SizedBox(height: 24),
                                                Text(
                                                  isOffline
                                                      ? 'Menyimpan laporan...'
                                                      : 'Mengirim laporan...',
                                                  style: semiBoldTextStyle(
                                                      size: 16),
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  isOffline
                                                      ? 'Laporan akan dikirim saat terhubung internet'
                                                      : 'Proses upload foto sedang berlangsung',
                                                  style: regularTextStyle(
                                                      size: 14,
                                                      color: neutral600),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );

                                    try {
                                      // Buat ID unik dari Firebase
                                      final reportRef = FirebaseDatabase
                                          .instance
                                          .ref('reports')
                                          .push();
                                      final reportId = reportRef.key!;

                                      // Cek directory reports
                                      final directory = Directory(
                                          '${(await getApplicationDocumentsDirectory()).path}/reports');
                                      if (!await directory.exists()) {
                                        await directory.create();
                                      }

                                      // Simpan path gambar yang dipilih
                                      final photoPathsList = <String>[];
                                      for (int i = 0;
                                          i < selectedPhotos.length;
                                          i++) {
                                        final photo = selectedPhotos[i];
                                        final savedFile = await photo.copy(
                                            '${directory.path}/${reportId}_photo_$i.jpg');
                                        photoPathsList.add(savedFile.path);
                                      }

                                      // Gabungkan path foto dengan koma
                                      final combinedPhotoPath =
                                          photoPathsList.join(',');

                                      // Buat objek Report
                                      final report = Report(
                                        id: reportId,
                                        taskId: widget.task.taskId,
                                        userId: widget.task.userId,
                                        officerName: widget.task.officerName,
                                        clusterId: widget.task.clusterId,
                                        clusterName: widget.task.clusterName,
                                        title: kejadianController.text,
                                        description: catatanController.text,
                                        photoUrl: combinedPhotoPath,
                                        timestamp: DateTime.now(),
                                        latitude:
                                            userCurrentLocation?.latitude ??
                                                0.0,
                                        longitude:
                                            userCurrentLocation?.longitude ??
                                                0.0,
                                        isSynced:
                                            !isOffline, // Tandai sesuai status koneksi
                                      );

                                      // Kirim report menggunakan bloc
                                      context
                                          .read<ReportBloc>()
                                          .add(CreateReportEvent(report));

                                      // Tunggu sebentar untuk memberi waktu proses penyimpanan
                                      await Future.delayed(
                                          const Duration(milliseconds: 800));

                                      // Tutup dialog loading
                                      if (loadingDialogContext != null &&
                                          Navigator.canPop(
                                              loadingDialogContext!)) {
                                        Navigator.pop(loadingDialogContext!);
                                      }

                                      // Tutup dialog form
                                      if (mounted &&
                                          Navigator.canPop(context)) {
                                        Navigator.pop(context);
                                      }

                                      // Reset form
                                      selectedPhotos.clear();
                                      kejadianController.clear();
                                      catatanController.clear();

                                      if (!isOffline) {
                                        await sendReportNotificationToCommandCenter(
                                          reportId:
                                              reportId, // ID laporan yang baru dibuat
                                          reportTitle:
                                              kejadianController.text.trim(),
                                          reportDescription:
                                              catatanController.text.trim(),
                                          patrolTaskId: widget.task.taskId,
                                          officerId: widget.task.userId,
                                          officerName:
                                              widget.task.officerName.isNotEmpty
                                                  ? widget.task.officerName
                                                  : 'Petugas',
                                          clusterName:
                                              widget.task.clusterName.isNotEmpty
                                                  ? widget.task.clusterName
                                                  : 'Tatar',
                                          latitude:
                                              userCurrentLocation?.latitude ??
                                                  0.0,
                                          longitude:
                                              userCurrentLocation?.longitude ??
                                                  0.0,
                                          reportTime: DateTime.now(),
                                          photoUrl: combinedPhotoPath.isNotEmpty
                                              ? combinedPhotoPath
                                              : null,
                                        );
                                      }

                                      // Tampilkan snackbar berdasarkan status koneksi
                                      showCustomSnackbar(
                                        context: context,
                                        title: isOffline
                                            ? 'Laporan disimpan untuk dikirim nanti'
                                            : 'Laporan berhasil dikirim',
                                        subtitle: isOffline
                                            ? 'Laporan akan dikirim saat terhubung internet'
                                            : 'Terima kasih atas laporan Anda',
                                        type: SnackbarType.success,
                                      );
                                    } catch (e) {
                                      // Tangani error
                                      if (loadingDialogContext != null &&
                                          mounted &&
                                          Navigator.canPop(
                                              loadingDialogContext!)) {
                                        Navigator.pop(loadingDialogContext!);
                                      }

                                      showCustomSnackbar(
                                        context: context,
                                        title: 'Gagal mengirim laporan',
                                        subtitle: 'Terjadi kesalahan: $e',
                                        type: SnackbarType.danger,
                                      );
                                    }
                                  } else {
                                    showCustomSnackbar(
                                      context: context,
                                      title: 'Data belum lengkap',
                                      subtitle:
                                          'Silakan isi semua data laporan',
                                      type: SnackbarType.danger,
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kbpBlue900,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 2,
                                ),
                                child: Text(
                                  'Kirim Laporan',
                                  style: semiBoldTextStyle(
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _isCurrentlyPatrolling() {
    // ✅ 1. PRIORITAS TERTINGGI: Local state yang sedang dalam transisi
    if (_localIsPatrolling && _localPatrollingTaskId == widget.task.taskId) {
      print('🔍 Patrol active via local state');
      return true;
    }

    // ✅ 2. PRIORITAS KEDUA: Local storage data (exclude completed)
    try {
      final localData = LocalPatrolService.getPatrolData(widget.task.taskId);
      if (localData != null) {
        // ✅ PERBAIKAN: Completed patrol should return false
        if (localData.status == 'completed') {
          print('🔍 Patrol completed, returning false');
          return false;
        }

        if (localData.status == 'started' || localData.status == 'ongoing') {
          print('🔍 Patrol active via local storage: ${localData.status}');
          return true;
        }
      }
    } catch (e) {
      print('❌ Error checking local patrol data: $e');
    }

    // ✅ 3. PRIORITAS KETIGA: BLoC state
    final state = context.read<PatrolBloc>().state;
    if (state is PatrolLoaded && state.isPatrolling) {
      print('🔍 Patrol active via BLoC state');
      return true;
    }

    // ✅ 4. PRIORITAS TERAKHIR: Task status (exclude completed)
    final taskOngoing =
        widget.task.status == 'ongoing' || widget.task.status == 'in_progress';

    if (taskOngoing) {
      print('🔍 Patrol active via task status: ${widget.task.status}');
    } else {
      print('🔍 Patrol not active, task status: ${widget.task.status}');
    }

    return taskOngoing;
  }

  Future<void> _addRouteMarkers(List<List<double>> coordinates) async {
    if (!_isMapReady || mapController == null) return;

    try {
      setState(() {
        _markers.clear();
        for (int i = 0; i < coordinates.length; i++) {
          final coord = coordinates[i];
          _markers.add(
            Marker(
              markerId: MarkerId('route-$i'),
              position: LatLng(coord[0], coord[1]),
              infoWindow: InfoWindow(title: 'Point ${i + 1}'),
            ),
          );
        }
      });

      // Fit map to show all markers
      if (coordinates.isNotEmpty) {
        final bounds = _getRouteBounds(coordinates);
        mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 50),
        );
      }
    } catch (e) {}
  }

  LatLngBounds _getRouteBounds(List<List<double>> coordinates) {
    if (coordinates.isEmpty) {
      // Return default bounds if no coordinates
      return LatLngBounds(
        southwest: LatLng(-6.927872391717073, 107.76910906700982),
        northeast: LatLng(-6.927872391717073, 107.76910906700982),
      );
    }

    double minLat = coordinates[0][0];
    double maxLat = coordinates[0][0];
    double minLng = coordinates[0][1];
    double maxLng = coordinates[0][1];

    for (var coord in coordinates) {
      if (coord.length >= 2) {
        minLat = minLat < coord[0] ? minLat : coord[0];
        maxLat = maxLat > coord[0] ? maxLat : coord[0];
        minLng = minLng < coord[1] ? minLng : coord[1];
        maxLng = maxLng > coord[1] ? maxLng : coord[1];
      }
    }

    // Add padding to bounds
    const padding = 0.001; // roughly 100m
    minLat -= padding;
    maxLat += padding;
    minLng -= padding;
    maxLng += padding;

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _initializeMap() async {
    await _getUserLocation();

    // ✅ Add route markers AFTER getting user location and BEFORE setting map ready
    if (widget.task.assignedRoute != null &&
        widget.task.assignedRoute!.isNotEmpty) {
      print(
          '🗺️ Adding ${widget.task.assignedRoute!.length} route markers to map');
      await _addRouteMarkers(widget.task.assignedRoute!);
    }

    setState(() {
      _isMapReady = true;
    });

    // ✅ Focus camera to assigned route after map is ready
    if (widget.task.assignedRoute != null &&
        widget.task.assignedRoute!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusCameraToAssignedRoute();
      });
    }
  }

  void _focusCameraToAssignedRoute() {
    if (widget.task.assignedRoute == null ||
        widget.task.assignedRoute!.isEmpty ||
        mapController == null) {
      print('⚠️ Cannot focus camera: route empty or controller null');
      return;
    }

    try {
      final coordinates = widget.task.assignedRoute!;

      if (coordinates.length == 1) {
        // Single point - just zoom to it
        final coord = coordinates[0];
        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(coord[0], coord[1]),
            16,
          ),
        );
        print('📍 Focused camera to single route point');
      } else {
        // Multiple points - fit all in view
        final bounds = _getRouteBounds(coordinates);
        mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 100),
        );
        print('📍 Focused camera to route bounds');
      }
    } catch (e) {
      print('❌ Error focusing camera to route: $e');
    }
  }

  Future<Position?> _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied');
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // Update lokasi setiap 10 meter
      ),
    ).listen(
      (Position position) {
        if (mounted) {
          setState(() {
            userCurrentLocation = position;
            if (mapController != null) {
              _updateUserMarker(position);
            }
          });

          final state = context.read<PatrolBloc>().state;
          if (state is PatrolLoaded && state.isPatrolling) {
            _updateDistance(position);
          } else {}
        }
      },
      onError: (error) {},
    );

    return await Geolocator.getCurrentPosition();
  }

  void _updateUserMarker(Position position) {
    setState(() {
      // ✅ Only remove existing user location marker, keep route markers
      _markers.removeWhere(
          (marker) => marker.markerId == const MarkerId('user-location'));

      // Add user location marker
      _markers.add(
        Marker(
          markerId: const MarkerId('user-location'),
          position: LatLng(position.latitude, position.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: 'Lokasi Saya',
            snippet:
                'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}',
          ),
        ),
      );
    });

    // ✅ Only auto-follow if patrolling, otherwise let user control camera
    final actuallyPatrolling = _isCurrentlyPatrolling();
    if (actuallyPatrolling) {
      // Update polyline for patrol route
      _updatePolyline(position);

      // Auto-follow only during patrol
      mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );
    }
  }

  void _updatePolyline(Position position) {
    if (!_isMapReady || mapController == null) {
      print('⚠️ Map not ready for polyline update');
      return;
    }

    final LatLng newPoint = LatLng(position.latitude, position.longitude);

    // ✅ VALIDATION: Check if coordinates are valid
    if (position.latitude.abs() > 90 || position.longitude.abs() > 180) {
      print(
          '⚠️ Invalid coordinates: ${position.latitude}, ${position.longitude}');
      return;
    }

    // Cek jika titik berubah signifikan
    if (_routePoints.isNotEmpty) {
      final lastPoint = _routePoints.last;
      final distance = Geolocator.distanceBetween(lastPoint.latitude,
          lastPoint.longitude, newPoint.latitude, newPoint.longitude);

      // Hanya tambahkan titik jika jarak cukup signifikan
      if (distance < 5) {
        print('⚠️ Distance too small ($distance m), skipping polyline update');
        return; // Skip jika kurang dari 5 meter
      }
    }

    try {
      setState(() {
        // Tambahkan titik baru ke array titik
        _routePoints.add(newPoint);

        // Update polyline yang sudah ada
        _polylines.removeWhere((polyline) =>
            polyline.polylineId == const PolylineId('patrol_route'));

        _polylines.add(
          Polyline(
            polylineId: const PolylineId('patrol_route'),
            points: _routePoints,
            color: _polylineColor,
            width: 5,
          ),
        );
      });

      print('✅ Polyline updated: ${_routePoints.length} total points');

      // Save route count to db every 10 points
      if (_routePoints.length % 10 == 0) {
        print('📊 Route milestone: ${_routePoints.length} points collected');
      }
    } catch (e) {
      print('❌ Error updating polyline: $e');
    }
  }

// Metode untuk menampilkan rute yang tersimpan dari database
  void _displaySavedRoute(Map<String, dynamic>? routePath) {
    if (routePath == null || !_isMapReady) return;

    try {
      // Konversi route_path menjadi list koordinat yang diurutkan berdasarkan timestamp
      final entries = routePath.entries.toList()
        ..sort((a, b) => (a.value['timestamp'] as String)
            .compareTo(b.value['timestamp'] as String));

      // Reset _routePoints
      _routePoints.clear();

      // Tambahkan semua titik dari routePath
      for (var entry in entries) {
        final coordinates = entry.value['coordinates'] as List;
        _routePoints.add(LatLng(
          (coordinates[0] as num).toDouble(),
          (coordinates[1] as num).toDouble(),
        ));
      }

      // Perbarui polyline
      setState(() {
        _polylines.clear();
        if (_routePoints.isNotEmpty) {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('patrol_route'),
              points: _routePoints,
              color: _polylineColor,
              width: 5,
            ),
          );
        }
      });

      // Jika ada titik, zoom ke area yang mencakup semua titik
      if (_routePoints.isNotEmpty) {
        _zoomToPolyline();
      }
    } catch (e) {}
  }

  void _zoomToPolyline() {
    if (_routePoints.isEmpty || mapController == null) return;

    // Cari bounds untuk semua titik
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    for (var point in _routePoints) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }

    // Pastikan bounds cukup besar
    final padding = 0.01; // sekitar 1km pada kebanyakan latitude
    minLat -= padding;
    maxLat += padding;
    minLng -= padding;
    maxLng += padding;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // Animasi kamera ke bounds
    mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    try {
      print('🗺️ Map created, setting up controller');
      setState(() {
        mapController = controller;
        _isMapReady = true;
      });

      // ✅ Add route markers immediately after map is created
      if (widget.task.assignedRoute != null &&
          widget.task.assignedRoute!.isNotEmpty) {
        print('🗺️ Map ready, adding assigned route markers');
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _addRouteMarkers(widget.task.assignedRoute!);

          // Focus camera to route after small delay
          await Future.delayed(Duration(milliseconds: 500));
          _focusCameraToAssignedRoute();
        });
      } else {
        print('⚠️ No assigned route to display');

        // If no assigned route but have user location, focus there
        if (userCurrentLocation != null) {
          controller.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(userCurrentLocation!.latitude,
                  userCurrentLocation!.longitude),
              15,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error in map creation: $e');
    }
  }

  void _debugMapStatus() {}

  Future<void> _stopPatrol(BuildContext context, PatrolLoaded state) async {
    final endTime = DateTime.now();

    // Get final route path from local storage
    final localData = LocalPatrolService.getPatrolData(widget.task.taskId);
    Map<String, dynamic> finalRoutePath = localData?.routePath ?? {};

    if (mounted) {
      final result =
          await _showFinalReportDialog(context, state, endTime, finalRoutePath);
      if (result != true) {
        return;
      }
    }
  }

// Tampilkan dialog laporan akhir saat patroli selesai
  Future<bool> _showFinalReportDialog(
    BuildContext context,
    PatrolLoaded state,
    DateTime endTime,
    Map<String, dynamic> finalRoutePath,
  ) async {
    File? capturedImage;
    final noteController = TextEditingController();
    bool isSubmitting = false;
    bool result = false;

    await showDialog(
      context: context,
      barrierDismissible:
          false, // User tidak bisa tap di luar untuk tutup dialog
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return WillPopScope(
              onWillPop: () async {
                // Tampilkan dialog konfirmasi jika user mencoba keluar
                bool exitConfirmed = await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      'Batalkan Akhiri Patroli?',
                      style: boldTextStyle(size: 18),
                    ),
                    content: Text(
                      'Jika Anda keluar, patroli akan terus berlanjut. Yakin ingin keluar?',
                      style: regularTextStyle(size: 14),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context, false);
                          _resetLongPressAnimation();
                        },
                        child: Text(
                          'Tidak',
                          style: mediumTextStyle(color: kbpBlue900),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kbpBlue900,
                        ),
                        child: Text(
                          'Ya, Lanjut Patroli',
                          style: mediumTextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );

                return exitConfirmed;
              },
              child: Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Dialog title
                      Row(
                        children: [
                          const Icon(Icons.task_alt,
                              color: successG500, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Akhiri Patroli',
                                  style: boldTextStyle(
                                      size: 18, color: kbpBlue900),
                                  textAlign: TextAlign.left,
                                ),
                                Text(
                                  'Ambil foto sebagai bukti patroli telah selesai',
                                  style: regularTextStyle(
                                      size: 14, color: neutral700),
                                  textAlign: TextAlign.left,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Foto preview container
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: kbpBlue100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kbpBlue300),
                        ),
                        child: capturedImage == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    size: 48,
                                    color: kbpBlue700,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Foto wajib diambil',
                                    style: mediumTextStyle(color: kbpBlue700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Pastikan lokasi terlihat dengan jelas',
                                    style: regularTextStyle(
                                        color: kbpBlue700, size: 12),
                                  ),
                                ],
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Image.file(
                                  capturedImage!,
                                  width: double.infinity,
                                  height: 200,
                                  fit: BoxFit.cover,
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Tombol ambil foto
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.camera_alt),
                          label: Text(
                            capturedImage == null
                                ? 'Ambil Foto'
                                : 'Ambil Ulang',
                            style: mediumTextStyle(color: Colors.white),
                          ),
                          onPressed: () async {
                            try {
                              final ImagePicker picker = ImagePicker();
                              final XFile? photo = await picker.pickImage(
                                source: ImageSource.camera,
                                preferredCameraDevice: CameraDevice.rear,
                                maxWidth: 1024,
                                maxHeight: 1024,
                                imageQuality: 80,
                              );

                              if (photo != null) {
                                setState(() {
                                  capturedImage = File(photo.path);
                                });
                              }
                            } catch (e) {}
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue900,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Catatan tambahan
                      TextField(
                        controller: noteController,
                        decoration: InputDecoration(
                          labelText: 'Catatan Patroli (Opsional)',
                          labelStyle: regularTextStyle(color: neutral600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: 'Tambahkan catatan tentang patroli Anda',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 24),

                      // Button baris
                      Row(
                        children: [
                          // Tombol Batal
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      bool exit = await showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(
                                            'Batalkan Akhiri Patroli?',
                                            style: boldTextStyle(size: 18),
                                          ),
                                          content: Text(
                                            'Jika Anda keluar, patroli akan terus berlanjut. Yakin ingin keluar?',
                                            style: regularTextStyle(size: 14),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: Text(
                                                'Tidak',
                                                style: mediumTextStyle(
                                                    color: kbpBlue900),
                                              ),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: kbpBlue900,
                                              ),
                                              child: Text(
                                                'Ya, Lanjut Patroli',
                                                style: mediumTextStyle(
                                                    color: Colors.white),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (exit) {
                                        Navigator.pop(dialogContext, false);
                                      }
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: neutral700,
                                side: BorderSide(color: neutral700),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                'Batal',
                                style: mediumTextStyle(color: neutral700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // ✅ FIXED: Tombol Selesaikan Patroli dengan Sequential Processing
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSubmitting || capturedImage == null
                                  ? null
                                  : () async {
                                      setState(() {
                                        isSubmitting = true;
                                      });

                                      try {
                                        print(
                                            '🔄 Starting patrol completion sequence...');

                                        // ✅ STEP 1: STOP ALL PATROL SYSTEMS IMMEDIATELY
                                        print(
                                            '📍 Step 1: Stopping patrol systems...');
                                        _patrolTimer?.cancel();
                                        _positionStreamSubscription?.cancel();
                                        _disableWakelock();

                                        // ✅ STEP 2: SET COMPLETION STATE TO PREVENT FURTHER UPDATES
                                        print(
                                            '📍 Step 2: Setting completion state...');
                                        final completionTime = DateTime.now();

                                        // Set a flag to prevent any further location updates
                                        setState(() {
                                          _localIsPatrolling = false;
                                          _localPatrollingTaskId = null;
                                        });

                                        // ✅ STEP 3: UPLOAD PHOTO FIRST
                                        print(
                                            '📍 Step 3: Uploading final photo...');
                                        String photoUrl = '';
                                        try {
                                          final fileName =
                                              'final_report_${widget.task.taskId}_${completionTime.millisecondsSinceEpoch}.jpg';
                                          photoUrl =
                                              await _uploadPhotoToFirebase(
                                                  capturedImage!, fileName);
                                          print(
                                              '✅ Photo uploaded successfully: $photoUrl');
                                        } catch (uploadError) {
                                          print(
                                              '❌ Failed to upload photo: $uploadError');
                                          throw Exception(
                                              'Gagal upload foto: $uploadError');
                                        }

                                        // ✅ STEP 4: COMPLETE PATROL IN LOCAL STORAGE (BUT DON'T DELETE YET)
                                        print(
                                            '📍 Step 4: Completing patrol in local storage...');
                                        try {
                                          await LocalPatrolService
                                              .completePatrol(
                                            taskId: widget.task.taskId,
                                            endTime: completionTime,
                                            finalPhotoUrl: photoUrl,
                                            finalNote: noteController.text
                                                    .trim()
                                                    .isNotEmpty
                                                ? noteController.text.trim()
                                                : null,
                                            totalDistance: _totalDistance,
                                            elapsedSeconds:
                                                _elapsedTime.inSeconds,
                                          );
                                          print(
                                              '✅ Local storage updated successfully (marked as completed but not synced)');
                                        } catch (localError) {
                                          print(
                                              '❌ Failed to update local storage: $localError');
                                          throw Exception(
                                              'Gagal simpan data lokal: $localError');
                                        }

                                        // ✅ STEP 5: GET FINAL DATA FOR NAVIGATION
                                        print(
                                            '📍 Step 5: Preparing navigation data...');
                                        final localData =
                                            LocalPatrolService.getPatrolData(
                                                widget.task.taskId);

                                        List<List<double>> completeRoutePath =
                                            [];
                                        if (localData?.routePath.isNotEmpty ==
                                            true) {
                                          final sortedEntries = localData!
                                              .routePath.entries
                                              .toList()
                                            ..sort((a, b) => a
                                                .value['timestamp']
                                                .toString()
                                                .compareTo(b.value['timestamp']
                                                    .toString()));

                                          for (var entry in sortedEntries) {
                                            final coordinates = entry
                                                .value['coordinates'] as List;
                                            if (coordinates.length >= 2) {
                                              completeRoutePath.add([
                                                (coordinates[0] as num)
                                                    .toDouble(),
                                                (coordinates[1] as num)
                                                    .toDouble(),
                                              ]);
                                            }
                                          }
                                        }

                                        // Fallback to current route points if local data is empty
                                        if (completeRoutePath.isEmpty &&
                                            _routePoints.isNotEmpty) {
                                          completeRoutePath = _routePoints
                                              .map((point) => [
                                                    point.latitude,
                                                    point.longitude
                                                  ])
                                              .toList();
                                        }

                                        // ✅ STEP 6: CLOSE DIALOG FIRST
                                        print('📍 Step 6: Closing dialog...');
                                        if (Navigator.canPop(context)) {
                                          Navigator.pop(context, true);
                                        }

                                        // ✅ STEP 7: NAVIGATE TO SUMMARY IMMEDIATELY
                                        print(
                                            '📍 Step 7: Navigating to summary...');
                                        if (mounted) {
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PatrolSummaryScreen(
                                                task: widget.task,
                                                routePath: completeRoutePath,
                                                startTime: localData
                                                            ?.startTime !=
                                                        null
                                                    ? DateTime.parse(
                                                        localData!.startTime!)
                                                    : DateTime.now()
                                                        .subtract(_elapsedTime),
                                                endTime: completionTime,
                                                distance: localData?.distance ??
                                                    _totalDistance,
                                                finalReportPhotoUrl: photoUrl,
                                                initialReportPhotoUrl: localData
                                                    ?.initialReportPhotoUrl,
                                              ),
                                            ),
                                          );
                                        }

                                        // ✅ STEP 8: UPDATE FIREBASE ASYNC (WITH CLEANUP ONLY ON SUCCESS)
                                        print(
                                            '📍 Step 8: Starting Firebase sync (background)...');
                                        _updateFirebaseAsync(
                                            completionTime,
                                            photoUrl,
                                            noteController.text.trim(),
                                            finalRoutePath);

                                        result = true;
                                      } catch (e) {
                                        print(
                                            '❌ Critical error in patrol completion: $e');

                                        // ✅ ROLLBACK ON ERROR
                                        setState(() {
                                          isSubmitting = false;
                                          _localIsPatrolling = true;
                                          _localPatrollingTaskId =
                                              widget.task.taskId;
                                        });

                                        // Restart systems
                                        _startPatrolTimer();
                                        _startLocationTracking();

                                        if (mounted) {
                                          showCustomSnackbar(
                                            context: context,
                                            title:
                                                'Gagal Menyelesaikan Patroli',
                                            subtitle: e.toString(),
                                            type: SnackbarType.danger,
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: successG500,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Selesai',
                                      style: semiBoldTextStyle(
                                          color: Colors.white),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }

// ✅ NEW METHOD: Background Firebase update (non-blocking)
  void _updateFirebaseAsync(
    DateTime endTime,
    String photoUrl,
    String note,
    Map<String, dynamic> finalRoutePath,
  ) async {
    try {
      print('🔄 Starting background Firebase sync...');

      // Check connectivity first
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        print('❌ No internet for Firebase sync, will retry later');
        return;
      }

      // ✅ Update Firebase with retry mechanism
      int retryCount = 0;
      bool firebaseSuccess = false;

      while (!firebaseSuccess && retryCount < 3) {
        try {
          print('🔄 Firebase sync attempt ${retryCount + 1}...');

          // Stop patrol in BLoC
          if (mounted) {
            context.read<PatrolBloc>().add(StopPatrol(
                  endTime: endTime,
                  distance: _totalDistance,
                  finalRoutePath: finalRoutePath,
                ));

            // Submit final report
            context.read<PatrolBloc>().add(SubmitFinalReport(
                  photoUrl: photoUrl,
                  note: note.isNotEmpty ? note : null,
                  reportTime: endTime,
                ));
          }

          // Wait a bit for BLoC to process
          await Future.delayed(Duration(seconds: 2));

          // Force sync via SyncService
          final syncSuccess =
              await SyncService.forceSyncPatrol(widget.task.taskId);

          if (syncSuccess) {
            firebaseSuccess = true;
            print('✅ Firebase sync completed successfully');

            // ✅ ONLY DELETE LOCAL DATA AFTER SUCCESSFUL SYNC
            await LocalPatrolService.deletePatrolData(widget.task.taskId);
            print('✅ Local data cleaned up after successful sync');
          } else {
            throw Exception('SyncService returned false');
          }
        } catch (e) {
          retryCount++;
          print('❌ Firebase sync attempt $retryCount failed: $e');

          if (retryCount < 3) {
            await Future.delayed(Duration(seconds: retryCount * 2));
          }
        }
      }

      if (!firebaseSuccess) {
        print(
            '⚠️ All Firebase sync attempts failed, local data preserved for later sync');

        // ✅ SHOW USER NOTIFICATION THAT DATA WILL BE SYNCED LATER
        if (mounted) {
          showCustomSnackbar(
            context: context,
            title: 'Data disimpan untuk sinkronisasi',
            subtitle: 'Patroli selesai, data akan dikirim saat koneksi stabil',
            type: SnackbarType.warning,
          );
        }
      }
    } catch (e) {
      print('❌ Error in background Firebase sync: $e');
    }
  }

// ✅ REMOVE THE IMMEDIATE CLEANUP FROM _performImmediateSync
  void _performImmediateSync(String taskId) {
    // Don't await this - let it run in background
    Future.microtask(() async {
      try {
        print('🔄 Performing immediate sync for completed patrol...');

        // Check connection
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult == ConnectivityResult.none) {
          print('❌ No internet for immediate sync');
          return;
        }

        // Force sync without delay
        final success = await SyncService.forceSyncPatrol(taskId);

        if (success) {
          print('✅ Immediate sync completed successfully');
          // ✅ ONLY DELETE AFTER SUCCESSFUL SYNC
          await LocalPatrolService.deletePatrolData(taskId);
          print('✅ Local data deleted after successful immediate sync');
        } else {
          print(
              '⚠️ Immediate sync failed, local data preserved for later sync');
        }
      } catch (e) {
        print('❌ Error in immediate sync: $e');
      }
    });
  }

// ✅ UPDATE _cleanupCompletedPatrol TO BE MORE CAREFUL
  Future<void> _cleanupCompletedPatrol() async {
    try {
      final localData = LocalPatrolService.getPatrolData(widget.task.taskId);
      if (localData != null && localData.status == 'completed') {
        print('🧹 Checking completed patrol data for: ${widget.task.taskId}');

        // ✅ ONLY DELETE IF SUCCESSFULLY SYNCED
        if (localData.isSynced) {
          await LocalPatrolService.deletePatrolData(widget.task.taskId);
          print('✅ Deleted synced completed patrol data');
        } else {
          print('⚠️ Completed patrol not synced yet, preserving local data');

          // ✅ ATTEMPT TO SYNC AGAIN
          try {
            final connectivityResult = await Connectivity().checkConnectivity();
            if (connectivityResult != ConnectivityResult.none) {
              print('🔄 Attempting to sync unsynchronized completed patrol...');
              final syncSuccess =
                  await SyncService.forceSyncPatrol(widget.task.taskId);

              if (syncSuccess) {
                print('✅ Late sync successful, now deleting local data');
                await LocalPatrolService.deletePatrolData(widget.task.taskId);
              }
            }
          } catch (e) {
            print('❌ Error in late sync attempt: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Error cleaning up completed patrol: $e');
    }
  }

  void _showMockLocationInfoDialog(BuildContext context, int detectionCount) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header dengan icon warning
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: const BoxDecoration(
                color: dangerR500,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fake GPS Terdeteksi',
                          style: boldTextStyle(size: 18, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Peringatan Keamanan',
                          style:
                              regularTextStyle(size: 12, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aplikasi mendeteksi penggunaan Fake GPS atau Mock Location. Hal ini tidak diperbolehkan dan akan dicatat untuk keperluan pelaporan.',
                    style: regularTextStyle(size: 14, color: neutral700),
                  ),

                  const SizedBox(height: 24),

                  // Langkah-langkah perbaikan dalam card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kbpBlue50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kbpBlue300, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Langkah Perbaikan:',
                          style: semiBoldTextStyle(size: 14, color: kbpBlue900),
                        ),
                        const SizedBox(height: 12),

                        // Langkah-langkah dengan icon
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: kbpBlue200,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Text('1',
                                  style: semiBoldTextStyle(
                                      size: 12, color: kbpBlue900)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Nonaktifkan Fake GPS atau Mock Location',
                                style: mediumTextStyle(
                                    size: 13, color: neutral800),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: kbpBlue200,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Text('2',
                                  style: semiBoldTextStyle(
                                      size: 12, color: kbpBlue900)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Pastikan Developer Options tidak aktif',
                                style: mediumTextStyle(
                                    size: 13, color: neutral800),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: kbpBlue200,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Text('3',
                                  style: semiBoldTextStyle(
                                      size: 12, color: kbpBlue900)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Restart aplikasi jika diperlukan',
                                style: mediumTextStyle(
                                    size: 13, color: neutral800),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (detectionCount >= 3)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: dangerR50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: dangerR200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: dangerR500,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Patroli dengan fake GPS yang terdeteksi lebih dari 3 kali akan ditandai tidak valid.',
                              style:
                                  mediumTextStyle(color: dangerR500, size: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kbpBlue900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Saya Mengerti',
                  style: semiBoldTextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    print('🧹 Disposing MapScreen...');

    _patrolTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _longPressTimer?.cancel();
    mapController?.dispose();
    _disableWakelock();

    // ✅ Reset flags to prevent memory leaks
    _isInitializing = false;
    _hasResumedPatrol = false;
    _localIsPatrolling = false;
    _localPatrollingTaskId = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PatrolBloc, PatrolState>(
      listener: (context, state) {
        if (state is PatrolError) {
          showCustomSnackbar(
            context: context,
            title: 'Error',
            subtitle: state.message,
            type: SnackbarType.danger,
          );
        }

        if (state is PatrolLoaded) {
          if (state.isPatrolling) {
            _enableWakelock();
          } else {
            _disableWakelock();
          }
        }
      },
      child: BlocBuilder<PatrolBloc, PatrolState>(builder: (context, state) {
        final isPatrolling = state is PatrolLoaded && state.isPatrolling;
        final isMockDetected =
            (state is PatrolLoaded && state.mockLocationDetected) ||
                _mockLocationDetected;
        final mockCount = state is PatrolLoaded ? state.mockLocationCount : 0;
        if (_isRecoveringFromLocal) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Memulihkan Data Patroli...',
                    style: semiBoldTextStyle(size: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mohon tunggu sebentar',
                    style: regularTextStyle(color: neutral600),
                  ),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Patrol Tracking',
              style: boldTextStyle(size: 20, color: Colors.white),
            ),
            backgroundColor: kbpBlue900,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: Stack(
            children: [
              // Peta sebagai latar belakang

              GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: const CameraPosition(
                  target: LatLng(-6.927872391717073, 107.76910906700982),
                  zoom: 15,
                ),
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: false, // Sembunyikan tombol default
                zoomControlsEnabled: false, // Sembunyikan kontrol zoom default
                mapType: MapType.normal,
                compassEnabled: true,
                buildingsEnabled: true,
              ),

              if (state is PatrolLoaded && state.isOffline)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: dangerR500.withOpacity(0.8),
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.wifi_off,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mode Offline - Data akan disinkronkan saat terhubung',
                              textAlign: TextAlign.center,
                              style: mediumTextStyle(
                                  color: Colors.white, size: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Syncing Indicator
              if (state is PatrolLoaded && state.isSyncing)
                Positioned(
                  top: state.isOffline
                      ? 30
                      : 0, // Position below offline indicator if visible
                  left: 0,
                  right: 0,
                  child: Container(
                    color: kbpBlue700,
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Menyinkronkan data offline...',
                            style:
                                mediumTextStyle(color: Colors.white, size: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Panel informasi tugas - lebih rapi dengan kartu
              Positioned(
                top: 24,
                left: 16,
                right: 16,
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: kbpBlue900, width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Judul Panel
                        Text(
                          'Detail Tugas Patroli',
                          style: boldTextStyle(size: 16, color: kbpBlue900),
                        ),
                        const Divider(color: kbpBlue200, thickness: 1),
                        const SizedBox(height: 8),

                        // Informasi Petugas & Kendaraan
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: kbpBlue200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SvgPicture.asset(
                                'assets/icons/officer.svg',
                                width: 36,
                                height: 36,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.task.officerName,
                                    style: semiBoldTextStyle(size: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  // ✅ Gunakan _isCurrentlyPatrolling() untuk menampilkan info waktu
                                  if (!_isCurrentlyPatrolling())
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time,
                                            size: 16, color: kbpBlue900),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${DateFormat('dd MMM - HH:mm').format(widget.task.assignedStartTime!)}',
                                          style: regularTextStyle(size: 14),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.place,
                                          size: 16, color: kbpBlue900),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${widget.task.assignedRoute?.length ?? 0} titik patroli',
                                        style: regularTextStyle(size: 14),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Info Waktu & Jarak (saat patroli aktif)
                        BlocBuilder<PatrolBloc, PatrolState>(
                          builder: (context, state) {
                            // ✅ Gunakan _isCurrentlyPatrolling() untuk konsistensi
                            final actuallyPatrolling = _isCurrentlyPatrolling();

                            if (actuallyPatrolling) {
                              return Column(
                                children: [
                                  const SizedBox(height: 12),
                                  const Divider(
                                      color: kbpBlue200, thickness: 1),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Waktu
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: kbpBlue100,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text('Durasi',
                                                  style: regularTextStyle(
                                                      size: 12,
                                                      color: kbpBlue900)),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(Icons.timer,
                                                      color: kbpBlue900,
                                                      size: 18),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _formatDuration(
                                                        _elapsedTime),
                                                    style:
                                                        boldTextStyle(size: 16),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Jarak
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: kbpBlue100,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text('Jarak',
                                                  style: regularTextStyle(
                                                      size: 12,
                                                      color: kbpBlue900)),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(Icons.directions,
                                                      color: kbpBlue900,
                                                      size: 18),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${(_totalDistance / 1000).toStringAsFixed(2)} km',
                                                    style:
                                                        boldTextStyle(size: 16),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (isMockDetected)
                Positioned(
                  top: (state is PatrolLoaded && state.isOffline) ? 24 : 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: dangerR500,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'PERINGATAN: Fake GPS Terdeteksi',
                                  style: boldTextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Penggunaan fake GPS tidak diperbolehkan dan akan dilaporkan',
                            style:
                                mediumTextStyle(color: Colors.white, size: 12),
                          ),
                          if (mockCount >= 3)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Terdeteksi $mockCount kali. Patroli mungkin dibatalkan.',
                                style: boldTextStyle(
                                    color: Colors.white, size: 12),
                              ),
                            ),
                          const SizedBox(height: 4),
                          ElevatedButton(
                            onPressed: () {
                              _showMockLocationInfoDialog(context, mockCount);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: dangerR500,
                            ),
                            child: Text(
                              'Pelajari Lebih Lanjut',
                              style: semiBoldTextStyle(size: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Panel bawah - tombol kontrol
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: BlocBuilder<PatrolBloc, PatrolState>(
                  builder: (context, state) {
                    // ✅ Gunakan _isCurrentlyPatrolling() untuk konsistensi
                    final actuallyPatrolling = _isCurrentlyPatrolling();

                    return Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Tombol kiri - kontrol peta
                            Row(
                              children: [
                                // Zoom In
                                ActionButton(
                                  icon: Icons.add,
                                  onTap: () => mapController
                                      ?.animateCamera(CameraUpdate.zoomIn()),
                                  tooltip: 'Zoom In',
                                ),
                                const SizedBox(width: 8),
                                // Zoom Out
                                ActionButton(
                                  icon: Icons.remove,
                                  onTap: () => mapController
                                      ?.animateCamera(CameraUpdate.zoomOut()),
                                  tooltip: 'Zoom Out',
                                ),
                                const SizedBox(width: 8),
                                // Lokasi Saya
                                ActionButton(
                                  icon: Icons.my_location,
                                  onTap: () {
                                    if (userCurrentLocation != null &&
                                        mapController != null) {
                                      mapController!.animateCamera(
                                        CameraUpdate.newLatLngZoom(
                                          LatLng(userCurrentLocation!.latitude,
                                              userCurrentLocation!.longitude),
                                          18,
                                        ),
                                      );
                                    }
                                  },
                                  tooltip: 'Lokasi Saya',
                                ),
                              ],
                            ),

                            // Dalam bagian build method, ganti bagian tombol dengan ini:
                            Row(
                              children: [
                                // Tombol laporan (hanya saat patroli aktif)
                                if (actuallyPatrolling) // ✅ Gunakan actuallyPatrolling
                                  ActionButton(
                                    icon: Icons.report_problem,
                                    color: dangerR300,
                                    onTap: () => _showReportDialog(context),
                                    tooltip: 'Lapor Kejadian',
                                  ),
                                const SizedBox(width: 12),
                                // Tombol mulai/stop dengan UI yang lebih baik
                                _buildPatrolButtonUI(
                                    actuallyPatrolling), // ✅ Pass actuallyPatrolling
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// Widget untuk tombol aksi
class ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color color;

  const ActionButton({
    Key? key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color = kbpBlue900,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(
            icon,
            color: color,
            size: 24,
          ),
        ),
      ),
    );
  }
}
