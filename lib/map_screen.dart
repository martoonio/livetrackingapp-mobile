import 'dart:async';
import 'dart:io';
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
import 'package:livetrackingapp/presentation/report/bloc/report_bloc.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_event.dart';
import 'package:livetrackingapp/services/location_validator.dart';
import '../../domain/entities/patrol_task.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:image_picker/image_picker.dart';

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

  void _resetLongPressAnimation() {
    _longPressTimer?.cancel();
    setState(() {
      _longPressProgress = 0.0;
    });
  }

  // Add method to start timer
  void _startPatrolTimer() {
    _patrolTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedTime += const Duration(seconds: 1);
        });
      }
    });
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

      print('Distance updated: $_totalDistance meters');
    } else {
      print(
          'First position set: ${newPosition.latitude}, ${newPosition.longitude}');
    }
    _lastPosition = newPosition;
  }

  @override
  void initState() {
    super.initState();

    final task = widget.task;

    print('=== MAP INITIALIZATION ===');
    print('Task ID: ${task.taskId}');
    print('Task Status: ${task.status}');
    print('Task Start Time: ${task.startTime}');

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.task.fetchOfficerName(FirebaseDatabase.instance.ref());
      if (mounted) {
        setState(() {}); // Refresh UI after name is loaded
      }
    });

    currentState = context.read<PatrolBloc>().state;

    if (task.status == 'ongoing' || task.status == 'in_progress') {
      print('Task is already in progress, resuming patrol...');
      // We need to wait for widget to be built before triggering resume
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resumeExistingPatrol(task);
      });
    } else {
      print('Task is not in progress: ${task.status}');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PatrolBloc>().add(LoadRouteData(userId: widget.task.userId));
    });

    _initializeMap();
  }

  bool _canStartPatrol() {
    // Jika patroli sedang berlangsung, selalu return true
    final state = context.read<PatrolBloc>().state;
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

  void _resumeExistingPatrol(PatrolTask task) {
    if (task.startTime == null) {
      print('Cannot resume patrol: no start time found in task');
      return;
    }

    print('Resuming patrol that started at ${task.startTime}');

    // Get route path data
    final routePath = task.routePath as Map<dynamic, dynamic>?;
    print('Found route path with ${routePath?.length ?? 0} points');

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
      print('Successfully converted ${existingRoutePath.length} route points');
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
          print(
              'Loaded ${_routePoints.length} points for route polyline display');
        } catch (e) {
          print('Error extracting route points: $e');
        }
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
            print(
                'Restored last position: ${_lastPosition!.latitude}, ${_lastPosition!.longitude}');
          }
        } catch (e) {
          print('Error restoring last position: $e');
        }
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

        print('Displayed saved route path with ${_routePoints.length} points');
      });
    }

    print(
        'Patrol resumed with elapsed time: $_elapsedTime, distance: $_totalDistance');

    // Notify user
    showCustomSnackbar(
      context: context,
      title: 'Patroli Dilanjutkan',
      subtitle: 'Melanjutkan patroli yang sedang berlangsung',
      type: SnackbarType.success,
    );
  }

  void _startLocationTracking() {
    String timeNow = DateTime.now().toIso8601String();
    print('Starting location tracking... time: $timeNow');

    // Cancel any existing subscription
    _positionStreamSubscription?.cancel();

    // Preserve existing route points if applicable
    final isResuming = widget.task.status == 'ongoing' && _routePoints.isEmpty;
    if (isResuming && widget.task.routePath != null) {
      print('Patrol is being resumed - preserve route data');
      // Route points will be loaded by _displaySavedRoute
    } else if (!isResuming) {
      print('Starting new tracking - clearing route data');
      setState(() {
        _routePoints.clear();
        _polylines.clear();
      });
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) async {
        if (mounted) {
          // Log lokasi untuk debugging
          print('Position update: ${position.latitude}, ${position.longitude}');

          // Check for mock location
          final isMocked = await LocationValidator.isLocationMocked(position);
          print('Is location mocked: $isMocked');

          if (isMocked) {
            print(
                'MOCK LOCATION DETECTED in UI: ${position.latitude}, ${position.longitude}');

            // TAMBAHAN: Log langsung ke Firebase tanpa melalui bloc
            try {
              // Ambil state untuk cek apakah sedang patroli
              final state = context.read<PatrolBloc>().state;
              final isPatrollingInBloc =
                  state is PatrolLoaded && state.isPatrolling;
              final isPatrollingInTask = widget.task.status == 'ongoing' ||
                  widget.task.status == 'in_progress';
              final isPatrolActive = isPatrollingInBloc || isPatrollingInTask;

              if (isPatrolActive) {
                // Ambil mockCount dari bloc atau gunakan nilai default
                int mockCount = 1;
                if (state is PatrolLoaded) {
                  mockCount = state.mockLocationCount + 1;
                }

                // Siapkan data mock location
                final mockData = {
                  'timestamp': DateTime.now().toIso8601String(),
                  'coordinates': [position.latitude, position.longitude],
                  'accuracy': position.accuracy,
                  'speed': position.speed,
                  'altitude': position.altitude,
                  'heading': position.heading,
                  'count': mockCount,
                };

                print('Logging mock location directly: $mockData');

                // 1. Update flag pada task
                final taskRef = FirebaseDatabase.instance
                    .ref()
                    .child('tasks/${widget.task.taskId}');
                await taskRef.update({
                  'mockLocationDetected': true,
                  'mockLocationCount': mockCount,
                  'lastMockDetection': mockData['timestamp'],
                });

                print('✓ Updated task mock flags successfully');

                // 2. Catat detail percobaan ke node khusus di database
                await taskRef.child('mock_detections').push().set(mockData);
                print('✓ Mock detection saved to task');

                // 3. Simpan juga di koleksi terpisah untuk analisis
                await FirebaseDatabase.instance
                    .ref()
                    .child('mock_location_logs')
                    .push()
                    .set({
                  ...mockData,
                  'taskId': widget.task.taskId,
                  'userId': widget.task.userId,
                  'detectionTime': ServerValue.timestamp,
                });

                print('✓ Mock detection saved to global logs');

                // 4. Update mockCount dalam state bloc supaya UI terupdate
                context
                    .read<PatrolBloc>()
                    .add(UpdateMockCount(mockCount: mockCount));
              }
            } catch (e) {
              print('Error logging mock location directly: $e');
              print(StackTrace.current);
            }

            // Tampilkan peringatan di UI
            setState(() {
              _mockLocationDetected = true;
            });

            // Tampilkan snackbar jika belum ditampilkan
            if (!_snackbarShown) {
              _snackbarShown = true;
              showCustomSnackbar(
                context: context,
                title: 'Fake GPS Terdeteksi!',
                subtitle:
                    'Penggunaan fake GPS tidak diperbolehkan dan akan dilaporkan',
                type: SnackbarType.danger,
              );

              // Reset flag setelah beberapa detik
              Future.delayed(Duration(seconds: 6), () {
                _snackbarShown = false;
              });
            }
          } else if (_mockLocationDetected) {
            // Reset mock flag jika sudah tidak terdeteksi lagi
            setState(() {
              _mockLocationDetected = false;
            });
          }

          setState(() {
            userCurrentLocation = position;
            if (mapController != null) {
              _updateUserMarker(position);
            }
          });

          // Check both local state and bloc state
          final state = context.read<PatrolBloc>().state;
          final isPatrollingInBloc =
              state is PatrolLoaded && state.isPatrolling;
          final isPatrollingInTask = widget.task.status == 'ongoing' ||
              widget.task.status == 'in_progress';
          final isPatrolActive = isPatrollingInBloc || isPatrollingInTask;

          if (isPatrolActive) {
            print('Patrol active, updating location');
            // IMPORTANT: This is where we send location updates to bloc
            final timestamp = DateTime.now();
            context.read<PatrolBloc>().add(UpdatePatrolLocation(
                  position: position,
                  timestamp: timestamp,
                ));
            print(
                'Location update dispatched to bloc: ${position.latitude}, ${position.longitude}');

            // For local UI updates
            _updateDistance(position);
            _updatePolyline(position);
          } else {
            print(
                'Patrol not active (Bloc: $isPatrollingInBloc, Task: $isPatrollingInTask)');
          }
        }
      },
      onError: (error) {
        print('Location tracking error: $error');
      },
    );
  }

  void _handlePatrolButtonPress(BuildContext context, PatrolState state) async {
    // Periksa apakah sudah bisa mulai patroli
    if (!_canStartPatrol() && !(state is PatrolLoaded && state.isPatrolling)) {
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

    // Kode yang sudah ada untuk menghentikan atau memulai patroli
    final isPatrollingInBloc = state is PatrolLoaded && state.isPatrolling;
    final isPatrollingInTask =
        widget.task.status == 'ongoing' || widget.task.status == 'in_progress';
    final isPatrolActive = isPatrollingInBloc || isPatrollingInTask;

    print(
        'Patrol button pressed - Bloc state: $isPatrollingInBloc, Task status: $isPatrollingInTask');

    if (isPatrolActive) {
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

  // Tombol mulai/stop
  Widget _buildPatrolButtonUI(bool isPatrolling) {
    final canStartNow = _canStartPatrol();

    // Jika tidak bisa mulai dan tidak sedang patroli
    if (!canStartNow && !isPatrolling) {
      return Container(
        width: 120, // Lebih lebar untuk menampung teks
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(12),
          color: neutral500, // Abu-abu untuk menunjukkan inactive
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

    // Kode yang sudah ada sebelumnya untuk tombol aktif
    return GestureDetector(
      onTap: () {
        // Tampilkan tooltip manual saat tap biasa
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPatrolling
                  ? 'Tekan 3 detik untuk selesai'
                  : 'Tekan 3 detik untuk mulai',
              style: mediumTextStyle(color: Colors.white),
            ),
            backgroundColor: isPatrolling ? dangerR300 : kbpBlue900,
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
                  color: isPatrolling ? dangerR300 : successG300,
                  backgroundColor: isPatrolling
                      ? dangerR300.withOpacity(0.3)
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
              color: isPatrolling ? dangerR300 : successG300,
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
                isPatrolling ? Icons.stop : Icons.play_arrow,
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
                        onPressed: () {
                          Navigator.pop(context, false);
                        },
                        child: Text(
                          'Tidak',
                          style: mediumTextStyle(color: kbpBlue900),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, true);
                        },
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
                              print('Error taking photo: $e');
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
                                  ? null // Disable jika belum ada foto atau sedang submit
                                  : () async {
                                      setState(() {
                                        isSubmitting = true;
                                      });

                                      try {
                                        // Upload foto ke Firebase Storage
                                        final fileName =
                                            'initial_report_${widget.task.taskId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

                                        // Upload foto ke Firebase Storage
                                        final photoUrl =
                                            await _uploadPhotoToFirebase(
                                                capturedImage!, fileName);

                                        initialReportPhotoUrl = photoUrl;

                                        // Set URL dan update state
                                        if (mounted) {
                                          setState(() {
                                            isSubmitting = false;
                                          });
                                        }

                                        // Update task dengan data laporan awal
                                        context
                                            .read<PatrolBloc>()
                                            .add(SubmitInitialReport(
                                              photoUrl: initialReportPhotoUrl!,
                                              note: noteController.text,
                                              reportTime: DateTime.now(),
                                            ));

                                        final localDialogContext =
                                            dialogContext;
                                        final localContext = context;

                                        // PENTING: Simpan data hasil dialog
                                        result = true;

                                        if (localDialogContext != null &&
                                            Navigator.canPop(
                                                localDialogContext)) {
                                          Navigator.pop(localDialogContext);
                                        }

                                        // PENTING: Tunggu sedikit sebelum memanggil _startPatrol
                                        // untuk memastikan dialog sudah benar-benar ditutup
                                        await Future.delayed(
                                            Duration(milliseconds: 100));

                                        if (mounted) {
                                          _startPatrol(localContext);

                                          // Tampilkan snackbar sukses
                                          showCustomSnackbar(
                                            context: context,
                                            title: 'Laporan awal berhasil',
                                            subtitle:
                                                'Patroli akan segera dimulai',
                                            type: SnackbarType.success,
                                          );
                                        }
                                      } catch (e) {
                                        // Tangani error
                                        setState(() {
                                          isSubmitting = false;
                                        });
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
    } catch (e) {
      print('Error adding route markers: $e');
    }
  }

  LatLngBounds _getRouteBounds(List<List<double>> coordinates) {
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    for (var coord in coordinates) {
      minLat = minLat < coord[0] ? minLat : coord[0];
      maxLat = maxLat > coord[0] ? maxLat : coord[0];
      minLng = minLng < coord[1] ? minLng : coord[1];
      maxLng = maxLng > coord[1] ? maxLng : coord[1];
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _initializeMap() async {
    await _getUserLocation();
    if (widget.task.assignedRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addRouteMarkers(widget.task.assignedRoute!);
      });
    }
    setState(() {
      _isMapReady = true;
    });
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
            print('Patrol is active, updating distance...');
            _updateDistance(position);
          } else {
            print('Patrol is not active, skipping distance update.');
          }
        }
      },
      onError: (error) {
        print('Location tracking error: $error');
      },
    );

    return await Geolocator.getCurrentPosition();
  }

  void _updateUserMarker(Position position) {
    setState(() {
      _markers.removeWhere(
          (marker) => marker.markerId == const MarkerId('user-location'));
      _markers.add(
        Marker(
          markerId: const MarkerId('user-location'),
          position: LatLng(position.latitude, position.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Current Location'),
        ),
      );
    });

    // Update camera to follow user if patrolling
    final state = context.read<PatrolBloc>().state;
    if (state is PatrolLoaded && state.isPatrolling) {
      // Update polyline jika sedang patroli
      _updatePolyline(position);

      mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    print('Map creation started');
    try {
      setState(() {
        mapController = controller;
        _isMapReady = true;
      });
      _debugMapStatus();

      // Add initial position check
      if (userCurrentLocation != null) {
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(
              userCurrentLocation!.latitude,
              userCurrentLocation!.longitude,
            ),
            15,
          ),
        );
      }
    } catch (e) {
      print('Error in map creation: $e');
    }
  }

  void _debugMapStatus() {
    print('=== Google Maps Debug Info ===');
    print('Map Controller: ${mapController != null ? 'Initialized' : 'Null'}');
    print('Is Map Ready: $_isMapReady');
    print('Markers Count: ${_markers.length}');
    print('User Location: $userCurrentLocation');
    print('Has Assigned Route: ${widget.task.assignedRoute != null}');
    print('===========================');
  }

  Future<void> _stopPatrol(BuildContext context, PatrolLoaded state) async {
    final endTime = DateTime.now();
    print('Stopping patrol at $endTime');

    // Convert route path
    List<List<double>> convertedPath = [];
    Map<String, dynamic> finalRoutePath = {};

    try {
      if (state.task?.routePath != null && state.task!.routePath is Map) {
        finalRoutePath =
            Map<String, dynamic>.from(state.task!.routePath as Map);
      }
    } catch (e) {
      print('Error processing route path: $e');
    }

    if (mounted) {
      final result =
          await _showFinalReportDialog(context, state, endTime, finalRoutePath);

      if (result != true) {
        print('User canceled patrol ending process');
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
                            } catch (e) {
                              print('Error taking photo: $e');
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

                          // Tombol Selesaikan Patroli
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSubmitting || capturedImage == null
                                  ? null // Disable jika belum ada foto atau sedang submit
                                  : () async {
                                      setState(() {
                                        isSubmitting = true;
                                      });

                                      try {
                                        // Upload foto ke Firebase Storage
                                        final fileName =
                                            'final_report_${widget.task.taskId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

                                        // Simpan referensi context dialog untuk digunakan nanti
                                        final currentDialogContext =
                                            dialogContext;

                                        // Upload foto ke Firebase Storage menggunakan fungsi yang sudah diperbaiki
                                        final photoUrl =
                                            await _uploadPhotoToFirebase(
                                                capturedImage!, fileName);

                                        if (mounted) {
                                          setState(() {
                                            finalReportPhotoUrl = photoUrl;
                                            isSubmitting = false;
                                          });
                                        }

                                        // Set result ke true untuk menandakan dialog berhasil
                                        result = true;

                                        // Tutup dialog laporan akhir
                                        if (Navigator.canPop(
                                            currentDialogContext)) {
                                          Navigator.pop(
                                              currentDialogContext, true);
                                        }

                                        // Beri jeda singkat untuk memastikan dialog tertutup
                                        await Future.delayed(
                                            const Duration(milliseconds: 100));

                                        if (mounted) {
                                          // Kirim event stop patrol dan final report
                                          context
                                              .read<PatrolBloc>()
                                              .add(StopPatrol(
                                                endTime: endTime,
                                                distance: _totalDistance,
                                                finalRoutePath: finalRoutePath,
                                              ));

                                          // Kirim event submit final report
                                          context.read<PatrolBloc>().add(
                                                SubmitFinalReport(
                                                  photoUrl: photoUrl,
                                                  note: noteController.text
                                                          .trim()
                                                          .isNotEmpty
                                                      ? noteController.text
                                                          .trim()
                                                      : null,
                                                  reportTime: endTime,
                                                ),
                                              );

                                          // Tampilkan loading dialog untuk persiapan ringkasan
                                          if (mounted) {
                                            showDialog(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (loadingContext) =>
                                                  WillPopScope(
                                                onWillPop: () async => false,
                                                child: Center(
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const CircularProgressIndicator(),
                                                        const SizedBox(
                                                            height: 16),
                                                        Text(
                                                          'Menyiapkan ringkasan patroli...',
                                                          style:
                                                              mediumTextStyle(),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }

                                          // Ambil data lengkap dari database
                                          try {
                                            // Ambil data task terbaru dari Firebase
                                            final taskSnapshot =
                                                await FirebaseDatabase.instance
                                                    .ref()
                                                    .child(
                                                        'tasks/${widget.task.taskId}')
                                                    .get();

                                            // Tutup dialog loading
                                            if (mounted &&
                                                Navigator.canPop(context)) {
                                              Navigator.pop(
                                                  context); // Close loading dialog
                                            }

                                            if (!taskSnapshot.exists) {
                                              print(
                                                  'Error: Task tidak ditemukan di database');
                                              throw Exception(
                                                  'Task tidak ditemukan di database');
                                            }

                                            // Konversi data rute
                                            final taskData = taskSnapshot.value
                                                as Map<dynamic, dynamic>;
                                            List<List<double>>
                                                completeRoutePath = [];

                                            // Ekstrak route path dari database
                                            if (taskData['route_path'] !=
                                                    null &&
                                                taskData['route_path'] is Map) {
                                              final routePathMap =
                                                  taskData['route_path']
                                                      as Map<dynamic, dynamic>;

                                              // Urutkan entry berdasarkan timestamp
                                              final sortedEntries = routePathMap
                                                  .entries
                                                  .toList()
                                                ..sort((a, b) =>
                                                    (a.value['timestamp']
                                                            as String)
                                                        .compareTo(
                                                            b.value['timestamp']
                                                                as String));

                                              // Konversi ke format List<List<double>>
                                              for (var entry in sortedEntries) {
                                                if (entry.value is Map &&
                                                    entry.value[
                                                            'coordinates'] !=
                                                        null) {
                                                  final coordinates =
                                                      entry.value['coordinates']
                                                          as List;
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
                                            }

                                            // Navigasi ke PatrolSummaryScreen
                                            if (mounted) {
                                              Navigator.pushReplacement(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      PatrolSummaryScreen(
                                                    task: widget.task,
                                                    routePath: completeRoutePath
                                                            .isNotEmpty
                                                        ? completeRoutePath
                                                        : _routePoints
                                                            .map((point) => [
                                                                  point
                                                                      .latitude,
                                                                  point
                                                                      .longitude
                                                                ])
                                                            .toList(),
                                                    startTime:
                                                        state.task?.startTime ??
                                                            DateTime.now(),
                                                    endTime: endTime,
                                                    distance: _totalDistance,
                                                    finalReportPhotoUrl:
                                                        photoUrl,
                                                    initialReportPhotoUrl: state
                                                        .task
                                                        ?.initialReportPhotoUrl,
                                                  ),
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            print(
                                                'Error saat menyiapkan ringkasan patroli: $e');

                                            // Tutup dialog loading jika masih ada
                                            if (mounted &&
                                                Navigator.canPop(context)) {
                                              Navigator.pop(context);
                                            }

                                            // Fallback: gunakan data yang ada di memory
                                            if (mounted) {
                                              Navigator.pushReplacement(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      PatrolSummaryScreen(
                                                    task: widget.task,
                                                    routePath: _routePoints
                                                        .map((point) => [
                                                              point.latitude,
                                                              point.longitude
                                                            ])
                                                        .toList(),
                                                    startTime:
                                                        state.task?.startTime ??
                                                            DateTime.now(),
                                                    endTime: endTime,
                                                    distance: _totalDistance,
                                                    finalReportPhotoUrl:
                                                        photoUrl,
                                                    initialReportPhotoUrl: state
                                                        .task
                                                        ?.initialReportPhotoUrl,
                                                  ),
                                                ),
                                              );
                                            }

                                            // Tampilkan pesan warning
                                            showCustomSnackbar(
                                              context: context,
                                              title: 'Perhatian',
                                              subtitle:
                                                  'Data rute mungkin tidak lengkap karena error',
                                              type: SnackbarType.warning,
                                            );
                                          }
                                        }
                                      } catch (e) {
                                        // Tangani error dan kembalikan state dialog
                                        if (mounted) {
                                          setState(() {
                                            isSubmitting = false;
                                          });

                                          print(
                                              'Error submitting final report: $e');
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text('Error: $e')),
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
                    print('Error in upload progress: $e');

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
      print('Error uploading photo: $e');
      throw Exception('Failed to upload photo: $e');
    }
  }

  void _startPatrol(BuildContext context) {
    final startTime = DateTime.now();

    print('Starting patrol at $startTime');

    // Update task status
    context.read<PatrolBloc>().add(UpdateTask(
          taskId: widget.task.taskId,
          updates: {
            'status': 'ongoing',
            'startTime': startTime.toIso8601String(),
          },
        ));

    // Start patrol
    context.read<PatrolBloc>().add(
          StartPatrol(
            task: widget.task,
            startTime: startTime,
          ),
        );

    _startPatrolTimer(); // Start timer
    _elapsedTime = Duration.zero; // Reset timer
    _totalDistance = 0; // Reset distance
    _lastPosition = null;
    _startLocationTracking(); // Start location tracking
    print('Patroli telah dimulai setelah laporan awal');

    widget.onStart();
  }

  void _updatePolyline(Position position) {
    if (!_isMapReady || mapController == null) return;

    final LatLng newPoint = LatLng(position.latitude, position.longitude);

    // Debug info
    print(
        'Adding point to polyline: ${position.latitude}, ${position.longitude}');

    // Cek jika titik berubah signifikan
    if (_routePoints.isNotEmpty) {
      final lastPoint = _routePoints.last;
      final distance = Geolocator.distanceBetween(lastPoint.latitude,
          lastPoint.longitude, newPoint.latitude, newPoint.longitude);

      // Hanya tambahkan titik jika jarak cukup signifikan
      if (distance < 5) {
        print('Point too close, skipping');
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

      // Save route count to db
      final state = context.read<PatrolBloc>().state;
      if (state is PatrolLoaded &&
          state.task != null &&
          _routePoints.length % 10 == 0) {
        print('Saving route with ${_routePoints.length} points');
      }
    } catch (e) {
      print('Error updating polyline: $e');
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

      print('Loaded saved route with ${_routePoints.length} points');

      // Jika ada titik, zoom ke area yang mencakup semua titik
      if (_routePoints.isNotEmpty) {
        _zoomToPolyline();
      }
    } catch (e) {
      print('Error loading saved route: $e');
    }
  }

// Metode untuk zoom ke polyline
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

  // Perbaikan tampilan dialog laporan

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
      } catch (e) {
        print('Error picking image: $e');
      }
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
                                onPressed: () {
                                  if (kejadianController.text.isNotEmpty &&
                                      catatanController.text.isNotEmpty &&
                                      selectedPhotos.isNotEmpty) {
                                    // Simpan semua foto ke Firebase Storage
                                    final report = Report(
                                      id: DateTime.now()
                                          .millisecondsSinceEpoch
                                          .toString(),
                                      title: kejadianController.text,
                                      description: catatanController.text,
                                      photoUrl: selectedPhotos
                                          .map((photo) => photo.path)
                                          .join(','), // Gabungkan path foto
                                      timestamp: DateTime.now(),
                                      latitude:
                                          userCurrentLocation?.latitude ?? 0.0,
                                      longitude:
                                          userCurrentLocation?.longitude ?? 0.0,
                                      taskId: widget.task.taskId,
                                    );

                                    context
                                        .read<ReportBloc>()
                                        .add(CreateReportEvent(report));
                                    showCustomSnackbar(
                                      context: context,
                                      title: 'Laporan berhasil dikirim',
                                      subtitle:
                                          'Terima kasih atas laporan Anda',
                                      type: SnackbarType.success,
                                    );
                                    selectedPhotos.clear();
                                    kejadianController.clear();
                                    catatanController.clear();
                                    Navigator.pop(context);
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

  void _showMockLocationInfoDialog(BuildContext context, int detectionCount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Fake GPS Terdeteksi',
          style: boldTextStyle(size: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aplikasi mendeteksi penggunaan Fake GPS atau Mock Location. Hal ini tidak diperbolehkan dan akan dicatat untuk keperluan pelaporan.',
              style: regularTextStyle(size: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Untuk melanjutkan patroli:',
              style: semiBoldTextStyle(size: 14),
            ),
            const SizedBox(height: 8),
            Text('1. Nonaktifkan Fake GPS atau Mock Location'),
            Text('2. Pastikan Developer Options tidak aktif'),
            Text('3. Restart aplikasi jika diperlukan'),
            if (detectionCount >= 3)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'PERINGATAN: Patroli dengan fake GPS yang terdeteksi lebih dari 3 kali akan ditandai tidak valid.',
                  style: TextStyle(
                    color: dangerR500,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Mengerti',
              style: mediumTextStyle(color: kbpBlue900),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _patrolTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _longPressTimer?.cancel();
    mapController?.dispose();
    super.dispose();
  }

  // Perbaikan tampilan MapScreen

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
      },
      child: BlocBuilder<PatrolBloc, PatrolState>(builder: (context, state) {
        print('MapScreen state: ${state is PatrolLoaded && state.isOffline}');
        final isPatrolling = state is PatrolLoaded && state.isPatrolling;
        final isMockDetected =
            (state is PatrolLoaded && state.mockLocationDetected) ||
                _mockLocationDetected;
        final mockCount = state is PatrolLoaded ? state.mockLocationCount : 0;
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
                                    widget.task.officerName ?? 'Petugas',
                                    style: semiBoldTextStyle(size: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.directions_car,
                                          size: 16, color: kbpBlue900),
                                      const SizedBox(width: 4),
                                      Text(
                                        widget.task.vehicleId,
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

                        if (!isPatrolling) 8.height,
                        Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 16, color: kbpBlue900),
                            const SizedBox(width: 4),
                            Text(
                              'Patroli dimulai pada ${DateFormat('dd MMM - HH:mm').format(widget.task.assignedStartTime!)}',
                              style: regularTextStyle(size: 14),
                            ),
                          ],
                        ),

                        // Info Waktu & Jarak (saat patroli aktif)
                        BlocBuilder<PatrolBloc, PatrolState>(
                          builder: (context, state) {
                            if (state is PatrolLoaded && state.isPatrolling) {
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
                    final isPatrolling =
                        state is PatrolLoaded && state.isPatrolling;

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
                                if (isPatrolling)
                                  ActionButton(
                                    icon: Icons.report_problem,
                                    color: dangerR300,
                                    onTap: () => _showReportDialog(context),
                                    tooltip: 'Lapor Kejadian',
                                  ),
                                const SizedBox(width: 12),
                                // Tombol mulai/stop dengan UI yang lebih baik
                                _buildPatrolButtonUI(isPatrolling),
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
