// import 'dart:async';
// import 'dart:io';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:flutter_svg/svg.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:livetrackingapp/domain/entities/report.dart';
// import 'package:livetrackingapp/patrol_summary_screen.dart';
// import 'package:livetrackingapp/presentation/report/bloc/report_bloc.dart';
// import 'package:livetrackingapp/presentation/report/bloc/report_event.dart';
// import '../../domain/entities/patrol_task.dart';
// import 'presentation/routing/bloc/patrol_bloc.dart';
// import 'package:livetrackingapp/presentation/component/utils.dart';
// import 'package:image_picker/image_picker.dart';

// class MapScreen extends StatefulWidget {
//   final PatrolTask task;
//   final VoidCallback onStart;

//   const MapScreen({
//     super.key,
//     required this.task,
//     required this.onStart,
//   });

//   @override
//   State<MapScreen> createState() => _MapScreenState();
// }

// class _MapScreenState extends State<MapScreen> {
//   GoogleMapController? mapController;
//   Position? userCurrentLocation;
//   StreamSubscription<Position>? _positionStreamSubscription;
//   final Set<Marker> _markers = {};
//   bool _isMapReady = false;
//   late final currentState;

//   Timer? _patrolTimer;
//   Duration _elapsedTime = Duration.zero;
//   double _totalDistance = 0;
//   Position? _lastPosition;

//   double _longPressProgress = 0.0; // Progress untuk animasi long press
//   Timer? _longPressTimer;

//   List<File> selectedPhotos = [];

//   void _startLongPressAnimation(BuildContext context, PatrolState state) {
//     const duration = Duration(seconds: 3); // Durasi long press
//     const interval =
//         Duration(milliseconds: 50); // Interval untuk update animasi
//     double increment = interval.inMilliseconds / duration.inMilliseconds;

//     _longPressTimer = Timer.periodic(interval, (timer) {
//       setState(() {
//         _longPressProgress += increment;
//         if (_longPressProgress >= 1.0) {
//           _longPressProgress = 1.0;
//           timer.cancel();
//           _handlePatrolButtonPress(context, state); // Jalankan aksi
//         }
//       });
//     });
//   }

//   void _resetLongPressAnimation() {
//     _longPressTimer?.cancel();
//     setState(() {
//       _longPressProgress = 0.0;
//     });
//   }

//   // Add method to start timer
//   void _startPatrolTimer() {
//     _patrolTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
//       if (mounted) {
//         setState(() {
//           _elapsedTime += const Duration(seconds: 1);
//         });
//       }
//     });
//   }

//   String _formatDuration(Duration duration) {
//     String twoDigits(int n) => n.toString().padLeft(2, '0');
//     final hours = twoDigits(duration.inHours);
//     final minutes = twoDigits(duration.inMinutes.remainder(60));
//     final seconds = twoDigits(duration.inSeconds.remainder(60));
//     return '$hours:$minutes:$seconds';
//   }

//   void _updateDistance(Position newPosition) {
//     if (_lastPosition != null) {
//       final distanceInMeters = Geolocator.distanceBetween(
//         _lastPosition!.latitude,
//         _lastPosition!.longitude,
//         newPosition.latitude,
//         newPosition.longitude,
//       );
//       _totalDistance += distanceInMeters;
//       print('Distance updated: $_totalDistance meters');
//     } else {
//       print(
//           'First position set: ${newPosition.latitude}, ${newPosition.longitude}');
//     }
//     _lastPosition = newPosition;
//   }

//   @override
//   void initState() {
//     super.initState();
//     currentState = context.read<PatrolBloc>().state;

//     // Check if this is a resumed patrol
//     if (currentState is PatrolLoaded &&
//         currentState.isPatrolling &&
//         currentState.task?.startTime != null) {
//       print('Resuming patrol tracking...');
//       _resumePatrolTracking(currentState.task!.startTime!);
//     }

//     WidgetsBinding.instance.addPostFrameCallback((_) async {
//       await widget.task.fetchOfficerName(FirebaseDatabase.instance.ref());
//       if (mounted) {
//         setState(() {}); // Perbarui UI setelah officerName dimuat
//       }
//     });

//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       context.read<PatrolBloc>().add(LoadRouteData(userId: widget.task.userId));
//     });
//     _initializeMap();
//   }

//   Future<void> _addRouteMarkers(List<List<double>> coordinates) async {
//     if (!_isMapReady || mapController == null) return;

//     try {
//       setState(() {
//         _markers.clear();
//         for (int i = 0; i < coordinates.length; i++) {
//           final coord = coordinates[i];
//           _markers.add(
//             Marker(
//               markerId: MarkerId('route-$i'),
//               position: LatLng(coord[0], coord[1]),
//               infoWindow: InfoWindow(title: 'Point ${i + 1}'),
//             ),
//           );
//         }
//       });

//       // Fit map to show all markers
//       if (coordinates.isNotEmpty) {
//         final bounds = _getRouteBounds(coordinates);
//         mapController?.animateCamera(
//           CameraUpdate.newLatLngBounds(bounds, 50),
//         );
//       }
//     } catch (e) {
//       print('Error adding route markers: $e');
//     }
//   }

//   LatLngBounds _getRouteBounds(List<List<double>> coordinates) {
//     double minLat = 90.0, maxLat = -90.0;
//     double minLng = 180.0, maxLng = -180.0;

//     for (var coord in coordinates) {
//       minLat = minLat < coord[0] ? minLat : coord[0];
//       maxLat = maxLat > coord[0] ? maxLat : coord[0];
//       minLng = minLng < coord[1] ? minLng : coord[1];
//       maxLng = maxLng > coord[1] ? maxLng : coord[1];
//     }

//     return LatLngBounds(
//       southwest: LatLng(minLat, minLng),
//       northeast: LatLng(maxLat, maxLng),
//     );
//   }

//   Future<void> _initializeMap() async {
//     await _getUserLocation();
//     if (widget.task.assignedRoute != null) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         _addRouteMarkers(widget.task.assignedRoute!);
//       });
//     }
//     setState(() {
//       _isMapReady = true;
//     });
//   }

//   Future<Position?> _getUserLocation() async {
//     bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
//     if (!serviceEnabled) {
//       return Future.error('Location services are disabled');
//     }

//     LocationPermission permission = await Geolocator.checkPermission();
//     if (permission == LocationPermission.denied) {
//       permission = await Geolocator.requestPermission();
//       if (permission == LocationPermission.denied) {
//         return Future.error('Location permissions are denied');
//       }
//     }

//     if (permission == LocationPermission.deniedForever) {
//       return Future.error('Location permissions are permanently denied');
//     }

//     _positionStreamSubscription = Geolocator.getPositionStream(
//       locationSettings: const LocationSettings(
//         accuracy: LocationAccuracy.best,
//         distanceFilter: 5, // Update lokasi setiap 10 meter
//       ),
//     ).listen(
//       (Position position) {
//         if (mounted) {
//           setState(() {
//             userCurrentLocation = position;
//             if (mapController != null) {
//               _updateUserMarker(position);
//             }
//           });

//           final state = context.read<PatrolBloc>().state;
//           if (state is PatrolLoaded && state.isPatrolling) {
//             print('Patrol is active, updating distance...');
//             _updateDistance(position);
//           } else {
//             print('Patrol is not active, skipping distance update.');
//           }
//         }
//       },
//       onError: (error) {
//         print('Location tracking error: $error');
//       },
//     );

//     return await Geolocator.getCurrentPosition();
//   }

//   void _updateUserMarker(Position position) {
//     setState(() {
//       _markers.removeWhere(
//           (marker) => marker.markerId == const MarkerId('user-location'));
//       _markers.add(
//         Marker(
//           markerId: const MarkerId('user-location'),
//           position: LatLng(position.latitude, position.longitude),
//           icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
//           infoWindow: const InfoWindow(title: 'Current Location'),
//         ),
//       );
//     });

//     // Update camera to follow user if patrolling
//     final state = context.read<PatrolBloc>().state;
//     if (state is PatrolLoaded && state.isPatrolling) {
//       mapController?.animateCamera(
//         CameraUpdate.newLatLng(
//           LatLng(position.latitude, position.longitude),
//         ),
//       );
//     }
//   }

//   void _onMapCreated(GoogleMapController controller) {
//     print('Map creation started');
//     try {
//       setState(() {
//         mapController = controller;
//         _isMapReady = true;
//       });
//       _debugMapStatus();

//       // Add initial position check
//       if (userCurrentLocation != null) {
//         controller.animateCamera(
//           CameraUpdate.newLatLngZoom(
//             LatLng(
//               userCurrentLocation!.latitude,
//               userCurrentLocation!.longitude,
//             ),
//             15,
//           ),
//         );
//       }
//     } catch (e) {
//       print('Error in map creation: $e');
//     }
//   }

//   void _debugMapStatus() {
//     print('=== Google Maps Debug Info ===');
//     print('Map Controller: ${mapController != null ? 'Initialized' : 'Null'}');
//     print('Is Map Ready: $_isMapReady');
//     print('Markers Count: ${_markers.length}');
//     print('User Location: $userCurrentLocation');
//     print('Has Assigned Route: ${widget.task.assignedRoute != null}');
//     print('===========================');
//   }

//   void _resumePatrolTracking(DateTime startTime) {
//     // Calculate elapsed time
//     _elapsedTime = DateTime.now().difference(startTime);
//     _startPatrolTimer();

//     // Resume location tracking
//     _startLocationTracking();

//     print('Patrol resumed - Elapsed time: $_elapsedTime');
//   }

//   void _startLocationTracking() {
//     String timeNow = DateTime.now().toIso8601String();
//     print('ini debug Starting location tracking... jam $timeNow');
//     _positionStreamSubscription?.cancel();
//     _positionStreamSubscription = Geolocator.getPositionStream(
//       locationSettings: const LocationSettings(
//         accuracy: LocationAccuracy.best,
//         distanceFilter: 5,
//       ),
//     ).listen(
//       (Position position) {
//         if (mounted) {
//           setState(() {
//             userCurrentLocation = position;
//             if (mapController != null) {
//               _updateUserMarker(position);
//             }
//           });

//           final state = context.read<PatrolBloc>().state;
//           print('ini debug state sekarang $state jam $timeNow');
//           if (state is PatrolLoaded && state.isPatrolling) {
//             // Update location in Firebase
//             context.read<PatrolBloc>().add(UpdatePatrolLocation(
//                   position: position,
//                   timestamp: DateTime.now(),
//                 ));
//             _updateDistance(position);
//           }
//         }
//       },
//       onError: (error) {
//         print('Location tracking error: $error');
//       },
//     );
//   }

//   void _handlePatrolButtonPress(BuildContext context, PatrolState state) async {
//     if (state is PatrolLoaded) {
//       if (state.isPatrolling || state.task?.status == 'ongoing') {
//         await _stopPatrol(context, state);
//       } else {
//         print('Dispatching StartPatrol event...');
//         _startPatrol(context);
//       }
//     } else {
//       print('Dispatching LoadRouteData event...');
//       context.read<PatrolBloc>().add(LoadRouteData(userId: widget.task.userId));
//     }
//   }

//   Future<void> _stopPatrol(BuildContext context, PatrolLoaded state) async {
//     final endTime = DateTime.now();

//     // Convert route path
//     List<List<double>> convertedPath = [];
//     try {
//       if (state.task?.routePath != null && state.task!.routePath is Map) {
//         final map = state.task!.routePath as Map;

//         // Sort entries by timestamp
//         final sortedEntries = map.entries.toList()
//           ..sort((a, b) => (a.value['timestamp'] as String)
//               .compareTo(b.value['timestamp'] as String));

//         // Convert coordinates
//         convertedPath = sortedEntries.map((entry) {
//           final coordinates = entry.value['coordinates'] as List;
//           return [
//             (coordinates[0] as num).toDouble(),
//             (coordinates[1] as num).toDouble(),
//           ];
//         }).toList();
//       }
//     } catch (e) {
//       print('Error converting route path: $e');
//     }

//     // Stop patrol
//     context.read<PatrolBloc>().add(StopPatrol(endTime: endTime));

//     // Wait briefly for state to update
//     await Future.delayed(const Duration(milliseconds: 100));

//     // Navigate to summary screen
//     if (mounted) {
//       Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(
//           builder: (_) => PatrolSummaryScreen(
//             task: widget.task,
//             routePath: convertedPath,
//             startTime: state.task?.startTime ?? DateTime.now(),
//             endTime: endTime,
//           ),
//         ),
//       );
//     }
//   }

//   void _startPatrol(BuildContext context) {
//     final startTime = DateTime.now();

//     print('Starting patrol at $startTime');

//     // Update task status
//     context.read<PatrolBloc>().add(UpdateTask(
//           taskId: widget.task.taskId,
//           updates: {
//             'status': 'ongoing',
//             'startTime': startTime.toIso8601String(),
//           },
//         ));

//     // Start patrol
//     context.read<PatrolBloc>().add(StartPatrol(
//           task: widget.task,
//           startTime: startTime,
//         ));

//     _startPatrolTimer(); // Start timer
//     _elapsedTime = Duration.zero; // Reset timer
//     _totalDistance = 0; // Reset distance
//     _lastPosition = null;
//     _startLocationTracking(); // Start location tracking
//     print('ini debug patroli udah mulai');

//     widget.onStart();
//   }

//   void _showReportDialog(BuildContext context) {
//     final TextEditingController kejadianController = TextEditingController();
//     final TextEditingController catatanController = TextEditingController();

//     Future<void> pickImagesFromCamera() async {
//       try {
//         final pickedFile = await ImagePicker().pickImage(
//           source: ImageSource.camera,
//           maxWidth: 1024,
//           maxHeight: 1024,
//           imageQuality: 85, // Mengurangi ukuran file
//         );
//         if (pickedFile != null) {
//           setState(() {
//             selectedPhotos.add(File(pickedFile.path));
//           });
//         }
//       } catch (e) {
//         print('Error picking image: $e');
//       }
//     }

//     showDialog(
//       context: context,
//       builder: (context) {
//         return Dialog(
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(16),
//           ),
//           child: StatefulBuilder(
//             builder: (context, setState) {
//               return Padding(
//                 padding: const EdgeInsets.all(16.0),
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // Title
//                     Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                       children: [
//                         const Text(
//                           'Laporan Kejadian',
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                         IconButton(
//                           icon: const Icon(Icons.close),
//                           onPressed: () {
//                             Navigator.pop(context);
//                             selectedPhotos.clear();
//                           },
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 16),
//                     // Input Kejadian
//                     const Text('kejadian'),
//                     const SizedBox(height: 8),
//                     TextField(
//                       controller: kejadianController,
//                       decoration: inputDecoration('Judul kejadian...'),
//                     ),
//                     const SizedBox(height: 16),
//                     // Input Catatan
//                     const Text('catatan'),
//                     const SizedBox(height: 8),
//                     TextField(
//                       controller: catatanController,
//                       maxLines: 3,
//                       decoration: inputDecoration('Deskripsi kejadian...'),
//                     ),
//                     const SizedBox(height: 16),
//                     // Bukti Kejadian
//                     const Text('bukti kejadian'),
//                     const SizedBox(height: 8),
//                     Wrap(
//                       spacing: 8,
//                       runSpacing: 8,
//                       children: [
//                         // Foto yang dipilih
//                         ...selectedPhotos.map((photo) {
//                           return Stack(
//                             children: [
//                               ClipRRect(
//                                 borderRadius: BorderRadius.circular(8),
//                                 child: Image.file(
//                                   photo,
//                                   width: 80,
//                                   height: 80,
//                                   fit: BoxFit.cover,
//                                 ),
//                               ),
//                               Positioned(
//                                 top: 4,
//                                 right: 4,
//                                 child: GestureDetector(
//                                   onTap: () {
//                                     setState(() {
//                                       selectedPhotos.remove(photo);
//                                     });
//                                   },
//                                   child: Container(
//                                     decoration: const BoxDecoration(
//                                       shape: BoxShape.circle,
//                                       color: Colors.red,
//                                     ),
//                                     padding: const EdgeInsets.all(4),
//                                     child: const Icon(
//                                       Icons.close,
//                                       color: Colors.white,
//                                       size: 16,
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           );
//                         }).toList(),
//                         // Tombol untuk menambah foto
//                         GestureDetector(
//                           onTap: () async {
//                             await pickImagesFromCamera();
//                             setState(() {}); // Pastikan dialog diperbarui
//                           },
//                           child: Container(
//                             width: 80,
//                             height: 80,
//                             decoration: BoxDecoration(
//                               border: Border.all(color: Colors.grey),
//                               borderRadius: BorderRadius.circular(8),
//                             ),
//                             child: const Center(
//                               child: Icon(
//                                 Icons.camera_alt,
//                                 size: 32,
//                                 color: Colors.grey,
//                               ),
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 16),
//                     // Button Kirim Laporan
//                     SizedBox(
//                       width: double.infinity,
//                       child: ElevatedButton(
//                         onPressed: () {
//                           if (kejadianController.text.isNotEmpty &&
//                               catatanController.text.isNotEmpty &&
//                               selectedPhotos.isNotEmpty) {
//                             // Simpan semua foto ke Firebase Storage
//                             final report = Report(
//                               id: DateTime.now()
//                                   .millisecondsSinceEpoch
//                                   .toString(),
//                               title: kejadianController.text,
//                               description: catatanController.text,
//                               photoUrl: selectedPhotos
//                                   .map((photo) => photo.path)
//                                   .join(','), // Gabungkan path foto
//                               timestamp: DateTime.now(),
//                               latitude: userCurrentLocation?.latitude ?? 0.0,
//                               longitude: userCurrentLocation?.longitude ?? 0.0,
//                               taskId: widget.task.taskId,
//                             );

//                             context
//                                 .read<ReportBloc>()
//                                 .add(CreateReportEvent(report));
//                             showCustomSnackbar(
//                               context: context,
//                               title: 'Laporan berhasil dikirim',
//                               subtitle: 'Terima kasih atas laporan Anda',
//                               type: SnackbarType.success,
//                             );
//                             selectedPhotos.clear();
//                             kejadianController.clear();
//                             catatanController.clear();
//                             Navigator.pop(context);
//                           } else {
//                             showCustomSnackbar(
//                               context: context,
//                               title: 'Data belum lengkap',
//                               subtitle: 'Silakan isi semua data laporan',
//                               type: SnackbarType.danger,
//                             );
//                           }
//                         },
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: Colors.black,
//                           padding: const EdgeInsets.symmetric(vertical: 16),
//                         ),
//                         child: const Text(
//                           'kirim laporan',
//                           style: TextStyle(color: Colors.white),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               );
//             },
//           ),
//         );
//       },
//     );
//   }

//   @override
//   void dispose() {
//     _patrolTimer?.cancel();
//     _positionStreamSubscription?.cancel();
//     _longPressTimer?.cancel();
//     mapController?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return BlocListener<PatrolBloc, PatrolState>(
//       listener: (context, state) {
//         print('ini debug state patroli paling atas $state');
//         if (state is PatrolError) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(content: Text('Error: ${state.message}')),
//           );
//         }
//       },
//       child: Scaffold(
//         appBar: AppBar(
//           title: Text('Task: ${widget.task.taskId}'),
//         ),
//         body: Stack(
//           children: [
//             GoogleMap(
//               onMapCreated: _onMapCreated,
//               initialCameraPosition: const CameraPosition(
//                 target: LatLng(-6.927872391717073, 107.76910906700982),
//                 zoom: 15,
//               ),
//               markers: _markers,
//               myLocationEnabled: true,
//               myLocationButtonEnabled: true,
//               zoomControlsEnabled: true,
//               mapType: MapType.normal,
//               compassEnabled: true,
//               tiltGesturesEnabled: true,
//               zoomGesturesEnabled: true,
//               rotateGesturesEnabled: true,
//               trafficEnabled: false,
//               buildingsEnabled: true,
//             ),
//             // Task details card
//             Positioned(
//               top: 16,
//               left: 16,
//               right: 16,
//               child: Container(
//                 decoration: BoxDecoration(
//                   color: kbpBlue300,
//                   borderRadius: BorderRadius.circular(8),
//                   border: Border.all(
//                     color: kbpBlue500,
//                     width: 3,
//                   ),
//                 ),
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   children: [
//                     Row(
//                       children: [
//                         SvgPicture.asset(
//                           'assets/icons/officer.svg',
//                           width: 50,
//                           height: 50,
//                         ),
//                         8.width,
//                         Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           mainAxisSize: MainAxisSize.min,
//                           children: [
//                             rowInfo(
//                                 widget.task.vehicleId, widget.task.vehicleId),
//                             4.height,
//                             rowInfo(widget.task.officerName, null),
//                           ],
//                         ),
//                       ],
//                     ),
//                     8.height,
//                     if (context.watch<PatrolBloc>().state is PatrolLoaded &&
//                         (context.watch<PatrolBloc>().state as PatrolLoaded)
//                             .isPatrolling)
//                       Card(
//                         color: Colors.white.withOpacity(0.9),
//                         child: Padding(
//                           padding: const EdgeInsets.all(16),
//                           child: Row(
//                             children: [
//                               SvgPicture.asset(
//                                 'assets/icons/stopwatch.svg',
//                                 width: 50,
//                                 height: 50,
//                               ),
//                               8.width,
//                               Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 mainAxisSize: MainAxisSize.min,
//                                 children: [
//                                   rowInfo(_formatDuration(_elapsedTime), null),
//                                   8.height,
//                                   rowInfo(
//                                       '${(_totalDistance / 1000).toStringAsFixed(2)} km',
//                                       null),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                   ],
//                 ),
//               ),
//             ),

//             // Start/Stop button
//             Positioned(
//               bottom: 16,
//               left: 16,
//               right: 16,
//               child: Row(
//                 mainAxisAlignment: widget.task.status == 'ongoing'
//                     ? MainAxisAlignment.spaceBetween
//                     : MainAxisAlignment.center,
//                 children: [
//                   if (widget.task.status == 'ongoing')
//                     GestureDetector(
//                       onTap: () {
//                         _showReportDialog(context);
//                       },
//                       child: Container(
//                         width: 70,
//                         height: 70,
//                         decoration: BoxDecoration(
//                           shape: BoxShape.circle,
//                           color: Colors.white,
//                           boxShadow: [
//                             BoxShadow(
//                               color: Colors.black.withOpacity(0.3),
//                               blurRadius: 8,
//                               offset: const Offset(0, 4),
//                             ),
//                           ],
//                         ),
//                         child: const Center(
//                           child: Icon(
//                             Icons.report,
//                             color: Colors.red,
//                             size: 32,
//                           ),
//                         ),
//                       ),
//                     ),
//                   BlocConsumer<PatrolBloc, PatrolState>(
//                     listener: (context, state) {
//                       print('ini debug state patroli bawah$state');
//                       if (state is PatrolError) {
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           SnackBar(content: Text('Error: ${state.message}')),
//                         );
//                         print('ini debug error mulai patroli ${state.message}');
//                       }
//                     },
//                     builder: (context, state) {
//                       return GestureDetector(
//                         onLongPressStart: (_) {
//                           print('debug tekan lama mulai patroli');
//                           _startLongPressAnimation(context, state);
//                         },
//                         onLongPressEnd: (_) {
//                           _resetLongPressAnimation();
//                         },
//                         child: Stack(
//                           alignment: Alignment.center,
//                           children: [
//                             // Background circle with animation
//                             TweenAnimationBuilder<double>(
//                               tween: Tween<double>(
//                                 begin: 0.0,
//                                 end: _longPressProgress,
//                               ),
//                               duration: const Duration(milliseconds: 50),
//                               builder: (context, value, child) {
//                                 return SizedBox(
//                                   width: 80,
//                                   height: 80,
//                                   child: CircularProgressIndicator(
//                                     value: value,
//                                     strokeWidth: 6.0,
//                                     color: state is PatrolLoaded &&
//                                             state.isPatrolling
//                                         ? dangerR300
//                                         : successG300,
//                                   ),
//                                 );
//                               },
//                             ),
//                             // Icon button
//                             Container(
//                               width: 70,
//                               height: 70,
//                               decoration: BoxDecoration(
//                                 shape: BoxShape.circle,
//                                 color:
//                                     state is PatrolLoaded && state.isPatrolling
//                                         ? dangerR300
//                                         : successG300,
//                                 boxShadow: [
//                                   BoxShadow(
//                                     color: Colors.black.withOpacity(0.3),
//                                     blurRadius: 8,
//                                     offset: const Offset(0, 4),
//                                   ),
//                                 ],
//                               ),
//                               child: Center(
//                                 child: Icon(
//                                   state is PatrolLoaded && state.isPatrolling
//                                       ? Icons.stop
//                                       : Icons.play_arrow,
//                                   color: Colors.white,
//                                   size: 32,
//                                 ),
//                               ),
//                             ),
//                           ],
//                         ),
//                       );
//                     },
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
