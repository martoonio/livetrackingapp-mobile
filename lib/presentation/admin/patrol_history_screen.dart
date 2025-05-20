import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/report.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as Math;
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

class PatrolHistoryScreen extends StatefulWidget {
  final PatrolTask task;

  const PatrolHistoryScreen({
    super.key,
    required this.task,
  });

  @override
  State<PatrolHistoryScreen> createState() => _PatrolHistoryScreenState();
}

class _PatrolHistoryScreenState extends State<PatrolHistoryScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final dateFormatter = DateFormat('dd MMM yyyy', 'id_ID');
  final timeFormatter = DateFormat('HH:mm', 'id_ID');

  TabController? _tabController;
  bool _isMapReady = false;

  // Tambahkan variabel reports
  List<Report> _reports = [];
  bool _isLoadingReports = true;

  // Di dalam _PatrolHistoryScreenState
  String? _finalReportPhotoUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _prepareRouteAndMarkers();
    _loadReports();

    // Setel finalReportPhotoUrl awal jika ada
    _finalReportPhotoUrl = widget.task.finalReportPhotoUrl;

    // Jika tidak ada, coba ambil dari Firebase
    if (_finalReportPhotoUrl == null || _finalReportPhotoUrl!.isEmpty) {
      _loadFinalReportPhoto();
    }
  }

  Future<void> _loadFinalReportPhoto() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('tasks')
          .child(widget.task.taskId)
          .child('finalReportPhotoUrl')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        setState(() {
          _finalReportPhotoUrl = snapshot.value as String;
          // Update juga di objek task
          widget.task.finalReportPhotoUrl = _finalReportPhotoUrl;
        });
      }
    } catch (e) {
      print('Error loading final report photo URL: $e');
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _prepareRouteAndMarkers() {
    try {
      // Add assigned route markers and polyline
      if (widget.task.assignedRoute != null) {
        _addAssignedRouteMarkers();
        _addAssignedRoutePolyline();
      }

      // Add actual route path if completed
      if (widget.task.routePath != null) {
        _addActualRoutePath();
      }

      setState(() {});
    } catch (e) {
      print('Error preparing route and markers: $e');
    }
  }

  void _addAssignedRouteMarkers() {
    // Siapkan data checkpoint yang dikunjungi
    final Set<int> visitedCheckpoints = <int>{};

    if (widget.task.routePath != null) {
      // Ubah route path menjadi list posisi
      final List<LatLng> routePositions = [];
      final routePathMap = Map<String, dynamic>.from(widget.task.routePath!);

      routePathMap.forEach((key, value) {
        final coordinates = value['coordinates'] as List;
        if (coordinates.length >= 2) {
          routePositions.add(LatLng(
            coordinates[0] as double,
            coordinates[1] as double,
          ));
        }
      });

      // Tentukan checkpoint mana yang sudah dikunjungi
      for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
        final checkpoint = widget.task.assignedRoute![i];
        final checkpointLat = checkpoint[0] as double;
        final checkpointLng = checkpoint[1] as double;

        for (final position in routePositions) {
          final distance = Geolocator.distanceBetween(position.latitude,
              position.longitude, checkpointLat, checkpointLng);

          if (distance <= 5) {
            visitedCheckpoints.add(i);
            break;
          }
        }
      }
    }

    // Tambahkan marker untuk setiap checkpoint dengan warna yang sesuai
    for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
      final coord = widget.task.assignedRoute![i];
      final bool isVisited = visitedCheckpoints.contains(i);

      _markers.add(
        Marker(
          markerId: MarkerId('checkpoint-$i'),
          position: LatLng(coord[0], coord[1]),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              isVisited ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
              title: 'Checkpoint ${i + 1}',
              snippet: isVisited ? 'Dikunjungi' : 'Belum dikunjungi'),
        ),
      );
    }
  }

  void _addAssignedRoutePolyline() {
    final points = widget.task.assignedRoute!
        .map((coord) => LatLng(coord[0], coord[1]))
        .toList();

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('assigned_route'),
        points: points,
        color: Colors.green.withOpacity(0.7),
        width: 3,
        patterns: [
          PatternItem.dash(20),
          PatternItem.gap(10),
        ],
      ),
    );
  }

  void _addActualRoutePath() {
    if (widget.task.routePath == null) return;

    final routePathMap = Map<String, dynamic>.from(widget.task.routePath!);
    final sortedEntries = routePathMap.entries.toList()
      ..sort((a, b) => (a.value['timestamp'] as String)
          .compareTo(b.value['timestamp'] as String));

    final points = sortedEntries.map((entry) {
      final coordinates = entry.value['coordinates'] as List;
      return LatLng(
        coordinates[0] as double,
        coordinates[1] as double,
      );
    }).toList();

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('actual_route'),
        points: points,
        color: kbpBlue700,
        width: 5,
      ),
    );

    // Tambahkan marker untuk start dan end point jika ada
    if (points.isNotEmpty) {
      _markers.add(
        Marker(
          markerId: const MarkerId('start_point'),
          position: points.first,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: 'Titik Mulai',
            snippet: 'Petugas memulai patroli di sini',
          ),
        ),
      );

      _markers.add(
        Marker(
          markerId: const MarkerId('end_point'),
          position: points.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(
            title: 'Titik Akhir',
            snippet: 'Petugas mengakhiri patroli di sini',
          ),
        ),
      );
    }
  }

  void _fitMapToRoute() {
    if (_mapController == null) return;

    double minLat = 90, maxLat = -90;
    double minLng = 180, maxLng = -180;

    // Include assigned route points
    if (widget.task.assignedRoute != null) {
      for (var coord in widget.task.assignedRoute!) {
        minLat = (minLat > coord[0]) ? coord[0] : minLat;
        maxLat = (maxLat < coord[0]) ? coord[0] : maxLat;
        minLng = (minLng > coord[1]) ? coord[1] : minLng;
        maxLng = (maxLng < coord[1]) ? coord[1] : maxLng;
      }
    }

    // Include actual route points if available
    if (widget.task.routePath != null) {
      final routePathMap = Map<String, dynamic>.from(widget.task.routePath!);
      for (var entry in routePathMap.entries) {
        final coordinates = entry.value['coordinates'] as List;
        final lat = coordinates[0] as double;
        final lng = coordinates[1] as double;

        minLat = (minLat > lat) ? lat : minLat;
        maxLat = (maxLat < lat) ? lat : maxLat;
        minLng = (minLng > lng) ? lng : minLng;
        maxLng = (maxLng < lng) ? lng : maxLng;
      }
    }

    // Ensure bounds are valid and add padding
    try {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.01, minLng - 0.01),
            northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
          ),
          50,
        ),
      );

      setState(() {
        _isMapReady = true;
      });
    } catch (e) {
      print('Error fitting map to route: $e');
      // Fallback to default view if bounds calculation fails
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(
            target: LatLng(-6.927727934898599, 107.76911107969532),
            zoom: 12,
          ),
        ),
      );
    }
  }

  // Fungsi untuk memuat laporan
  Future<void> _loadReports() async {
    try {
      setState(() {
        _isLoadingReports = true;
      });

      final snapshot = await FirebaseDatabase.instance
          .ref('reports')
          .orderByChild('taskId')
          .equalTo(widget.task.taskId)
          .get();

      final List<Report> reports = [];

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          if (value is Map) {
            reports.add(Report.fromJson(
              key.toString(),
              Map<String, dynamic>.from(value),
            ));
          }
        });

        // Sort reports by timestamp
        reports.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }

      setState(() {
        _reports = reports;
        _isLoadingReports = false;

        // Tambahkan marker untuk setiap laporan
        _addReportMarkers();
      });
    } catch (e) {
      print('Error loading reports: $e');
      setState(() {
        _isLoadingReports = false;
      });
    }
  }

  // Tambahkan method untuk menambahkan marker laporan
  void _addReportMarkers() {
    for (var i = 0; i < _reports.length; i++) {
      final report = _reports[i];

      _markers.add(
        Marker(
          markerId: MarkerId('report-${report.id}'),
          position: LatLng(report.latitude, report.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: report.title,
            snippet: 'Klik untuk melihat detail',
            onTap: () {
              _showReportDetail(report);
            },
          ),
        ),
      );
    }

    setState(() {});
  }

  // Method untuk menampilkan detail laporan
  void _showReportDetail(Report report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Detail Laporan',
                    style: boldTextStyle(size: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Judul laporan
                      Text(
                        report.title,
                        style: boldTextStyle(size: 16),
                      ),
                      const SizedBox(height: 8),

                      // Waktu laporan
                      Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 16, color: neutral500),
                          const SizedBox(width: 4),
                          Text(
                            '${dateFormatter.format(report.timestamp)} ${timeFormatter.format(report.timestamp)}',
                            style:
                                regularTextStyle(size: 14, color: neutral600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Foto laporan
                      if (report.photoUrl.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: Text('Foto Laporan'),
                                    backgroundColor: kbpBlue900,
                                    foregroundColor: Colors.white,
                                  ),
                                  body: Center(
                                    child: InteractiveViewer(
                                      panEnabled: true,
                                      boundaryMargin: EdgeInsets.all(20),
                                      minScale: 0.5,
                                      maxScale: 3.0,
                                      child: Image.network(
                                        report.photoUrl,
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                          if (loadingProgress == null)
                                            return child;
                                          return Center(
                                            child: CircularProgressIndicator(
                                              value: loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                  : null,
                                            ),
                                          );
                                        },
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.broken_image,
                                                  size: 64, color: neutral400),
                                              SizedBox(height: 16),
                                              Text('Gagal memuat gambar',
                                                  style: mediumTextStyle()),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          child: Hero(
                            tag: 'report_image_${report.id}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                report.photoUrl,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    height: 200,
                                    color: neutral200,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 200,
                                    color: neutral200,
                                    child: const Center(
                                      child: Icon(Icons.broken_image,
                                          size: 48, color: neutral500),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: neutral200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_not_supported,
                                    size: 48, color: neutral500),
                                SizedBox(height: 8),
                                Text('Tidak ada foto'),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Deskripsi
                      Text(
                        'Deskripsi',
                        style: semiBoldTextStyle(size: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        report.description,
                        style: regularTextStyle(size: 14),
                      ),
                      const SizedBox(height: 16),

                      // Lokasi
                      Text(
                        'Lokasi',
                        style: semiBoldTextStyle(size: 16),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 16, color: kbpBlue700),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${report.latitude.toStringAsFixed(6)}, ${report.longitude.toStringAsFixed(6)}',
                              style: regularTextStyle(size: 14),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.map_outlined,
                                color: kbpBlue700),
                            onPressed: () async {
                              // Tutup dialog detail laporan dulu
                              Navigator.pop(context);

                              // Pindah ke tab peta (tab index 0)
                              _tabController!.animateTo(0);

                              // Tunggu sebentar agar UI terupdate
                              await Future.delayed(
                                  const Duration(milliseconds: 300));

                              // Zoom ke lokasi laporan
                              _mapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  LatLng(report.latitude, report.longitude),
                                  18, // Zoom level yang cukup detail
                                ),
                              );

                              // Opsional: tampilkan snackbar sebagai feedback
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Menampilkan lokasi laporan di peta',
                                    style: mediumTextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: kbpBlue900,
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            tooltip: 'Lihat di Peta Patroli',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Button to view on map
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('Tampilkan di Peta'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kbpBlue900,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);

                    // Pindah ke tab peta dan zoom ke posisi laporan
                    _tabController!.animateTo(0); // Tab peta adalah index 0

                    // Zoom ke lokasi laporan
                    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
                      LatLng(report.latitude, report.longitude),
                      18,
                    ));
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Tambahkan widget untuk menampilkan laporan
  Widget _buildReportsView() {
    if (_isLoadingReports) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kbpBlue700),
            SizedBox(height: 16),
            Text('Memuat data laporan...'),
          ],
        ),
      );
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.report_off, size: 64, color: neutral400),
            const SizedBox(height: 16),
            Text(
              'Tidak ada laporan untuk patroli ini',
              style: mediumTextStyle(size: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Petugas tidak mengirimkan laporan selama patroli berlangsung',
              style: regularTextStyle(size: 14, color: neutral600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final report = _reports[index];
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: InkWell(
            onTap: () => _showReportDetail(report),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header dengan judul dan timestamp
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kbpBlue100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.report_problem,
                          color: kbpBlue900,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report.title,
                              style: semiBoldTextStyle(size: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${dateFormatter.format(report.timestamp)} ${timeFormatter.format(report.timestamp)}',
                              style:
                                  regularTextStyle(size: 12, color: neutral600),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 16, color: neutral500),
                    ],
                  ),
                ),

                // Gambar laporan
                if (report.photoUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: Image.network(
                      report.photoUrl,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 180,
                          color: neutral200,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 180,
                          color: neutral200,
                          child: const Center(
                            child: Icon(Icons.broken_image,
                                size: 48, color: neutral500),
                          ),
                        );
                      },
                    ),
                  ),

                // Deskripsi jika tidak ada foto
                if (report.photoUrl.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          report.description,
                          style: regularTextStyle(size: 14),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detail Patroli',
          style: semiBoldTextStyle(color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: kbpBlue900,
            child: TabBar(
              controller: _tabController,
              indicatorColor: neutralWhite,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: semiBoldTextStyle(size: 14, color: neutralWhite),
              unselectedLabelStyle:
                  mediumTextStyle(size: 14, color: neutral200),
              tabs: [
                const Tab(text: 'Rute Patroli'),
                const Tab(text: 'Informasi'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Laporan'),
                      const SizedBox(width: 4),
                      if (_reports.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: neutralWhite,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_reports.length}',
                            style:
                                semiBoldTextStyle(size: 12, color: kbpBlue900),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Map view
          _buildMapView(),

          // Tab 2: Task details
          _buildTaskDetailsView(),

          // Tab 3: Reports
          _buildReportsView(),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    return Column(
      children: [
        _buildMapLegend(),
        Expanded(
          child: Stack(
            children: [
              GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                  _fitMapToRoute();
                },
                initialCameraPosition: const CameraPosition(
                  target: LatLng(-6.927727934898599, 107.76911107969532),
                  zoom: 15,
                ),
                markers: _markers,
                polylines: _polylines,
                mapType: MapType.normal,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: true,
                compassEnabled: true,
                scrollGesturesEnabled: true,
                rotateGesturesEnabled: true,
              ),
              if (!_isMapReady)
                const Center(
                  child: CircularProgressIndicator(color: kbpBlue700),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // Tambahkan fungsi _legendItem di dalam class _PatrolHistoryScreenState
  Widget _legendItem(Color color, String text, {bool isDashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 4,
          decoration: BoxDecoration(
            color: isDashed ? Colors.transparent : color,
          ),
          child: isDashed
              ? CustomPaint(
                  painter: DashedLinePainter(color: color),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: regularTextStyle(size: 12, color: neutral700),
        ),
      ],
    );
  }

  Widget _buildMapLegend() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: Colors.white,
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          _legendItem(Colors.green.withOpacity(0.7), 'Rute yang ditugaskan',
              isDashed: true),
          _legendItem(
            kbpBlue700,
            'Rute aktual petugas',
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                'Titik dikunjungi',
                style: regularTextStyle(size: 12, color: neutral700),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Text(
                'Titik belum dikunjungi',
                style: regularTextStyle(size: 12, color: neutral700),
              ),
            ],
          ),
          // Tambahkan legend untuk report markers
          if (_reports.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Laporan (${_reports.length})',
                  style: regularTextStyle(size: 12, color: neutral700),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTaskDetailsView() {
    final duration =
        widget.task.endTime != null && widget.task.startTime != null
            ? widget.task.endTime!.difference(widget.task.startTime!)
            : null;

    final startTimeStr = widget.task.startTime != null
        ? '${dateFormatter.format(widget.task.startTime!)} ${timeFormatter.format(widget.task.startTime!)}'
        : 'Belum dimulai';

    final endTimeStr = widget.task.endTime != null
        ? '${dateFormatter.format(widget.task.endTime!)} ${timeFormatter.format(widget.task.endTime!)}'
        : 'Belum selesai';

    final durationStr = duration != null
        ? '${duration.inHours}j ${duration.inMinutes % 60}m ${duration.inSeconds % 60}d'
        : 'N/A';

    // Perhitungan titik yang dikunjungi berdasarkan jarak radius 5 meter
    final visitData = _calculateVisitedPoints();
    int visitedPoints = visitData['visitedCount'];
    int totalPoints = visitData['totalCount'];

    final progress =
        totalPoints > 0 ? (visitedPoints / totalPoints * 100).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Task header card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: _getStatusColor(widget.task.status),
                        child: Icon(
                          _getStatusIcon(widget.task.status),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tugas #${widget.task.taskId.substring(0, Math.min(8, widget.task.taskId.length))}',
                              style: boldTextStyle(size: 16),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusBgColor(widget.task.status),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getStatusText(widget.task.status),
                                style: mediumTextStyle(
                                  color: _getStatusColor(widget.task.status),
                                  size: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _infoRow(
                      Icons.directions_car, 'Kendaraan', widget.task.vehicleId),
                  const SizedBox(height: 8),
                  _infoRow(
                    Icons.access_time,
                    'Waktu Mulai',
                    startTimeStr,
                  ),
                  const SizedBox(height: 8),
                  _infoRow(
                    Icons.flag,
                    'Waktu Selesai',
                    endTimeStr,
                  ),
                  const SizedBox(height: 8),
                  _infoRow(
                    Icons.timelapse,
                    'Durasi Patroli',
                    durationStr,
                  ),
                  if (widget.task.distance != null) ...[
                    const SizedBox(height: 8),
                    _infoRow(
                      Icons.route,
                      'Jarak Tempuh',
                      '${(widget.task.distance! / 1000).toStringAsFixed(2)} km',
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Tambahkan di dalam _buildTaskDetailsView(), tepat pada bagian "// Final Report Photo"
// ...

          const SizedBox(height: 16),

// Final Report Photo
          if (widget.task.finalReportPhotoUrl != null &&
              widget.task.finalReportPhotoUrl!.isNotEmpty)
            _buildReportPhoto(widget.task.finalReportPhotoUrl!),
          const SizedBox(height: 16),

          if (widget.task.initialReportPhotoUrl != null &&
              widget.task.initialReportPhotoUrl!.isNotEmpty)
            _buildReportPhoto(widget.task.initialReportPhotoUrl!),
          const SizedBox(height: 16),

          // Progress card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Progress Kunjungan',
                    style: semiBoldTextStyle(size: 16),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Titik Dikunjungi',
                        style: regularTextStyle(size: 14, color: neutral600),
                      ),
                      Text(
                        '$visitedPoints dari $totalPoints titik',
                        style: semiBoldTextStyle(size: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress / 100,
                    backgroundColor: neutral200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.task.status.toLowerCase() == 'finished' ||
                              widget.task.status.toLowerCase() == 'completed'
                          ? successG500
                          : widget.task.status.toLowerCase() == 'ongoing' ||
                                  widget.task.status.toLowerCase() == 'active'
                              ? kbpBlue700
                              : warningY500,
                    ),
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getProgressDescription(widget.task.status, progress),
                        style: regularTextStyle(size: 14, color: neutral700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Titik dianggap dikunjungi jika petugas berada dalam radius 5 meter.',
                        style: regularTextStyle(size: 12, color: neutral500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Activity timeline
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Timeline Aktivitas',
                    style: semiBoldTextStyle(size: 16),
                  ),
                  const SizedBox(height: 16),
                  _buildTimeline(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportPhoto(String imageUrl) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_camera, color: kbpBlue900),
                const SizedBox(width: 8),
                Text(
                  'Foto Laporan Akhir',
                  style: semiBoldTextStyle(size: 16),
                ),
                const Spacer(),
                if (widget.task.finalReportTime != null)
                  Text(
                    timeFormatter.format(widget.task.finalReportTime!),
                    style: regularTextStyle(size: 12, color: neutral600),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () =>
                  _showFullScreenImage(widget.task.finalReportPhotoUrl!),
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: neutral200,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                              color: kbpBlue700,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.broken_image,
                                  size: 48,
                                  color: neutral500,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Gagal memuat gambar',
                                  style: mediumTextStyle(color: neutral600),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      // Overlay dengan ikon zoom
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.zoom_in,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.task.finalReportNote != null &&
                widget.task.finalReportNote!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Catatan:',
                style: mediumTextStyle(size: 14),
              ),
              const SizedBox(height: 4),
              Text(
                widget.task.finalReportNote!,
                style: regularTextStyle(size: 14, color: neutral700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: neutral500),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: regularTextStyle(size: 14, color: neutral600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: mediumTextStyle(size: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    final events = <Map<String, dynamic>>[];

    // Assigned event
    events.add({
      'title': 'Tugas diberikan',
      'time': widget.task.createdAt ?? DateTime.now(),
      'status': 'assigned',
    });

    // Start patrol event
    if (widget.task.startTime != null) {
      events.add({
        'title': 'Patroli dimulai',
        'time': widget.task.startTime!,
        'status': 'started',
      });
    }

    // End patrol event
    if (widget.task.endTime != null) {
      events.add({
        'title': 'Patroli selesai',
        'time': widget.task.endTime!,
        'status': 'completed',
      });
    }

    // Sort events by time
    events.sort(
        (a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isLastItem = index == events.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getTimelineColor(event['status'] as String),
                  ),
                ),
                if (!isLastItem)
                  Container(
                    width: 2,
                    height: 50,
                    color: neutral300,
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event['title'] as String,
                    style: semiBoldTextStyle(size: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dateFormatter.format(event['time'] as DateTime)} ${timeFormatter.format(event['time'] as DateTime)}',
                    style: regularTextStyle(size: 12, color: neutral600),
                  ),
                  if (!isLastItem) const SizedBox(height: 36),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return 'Tugas Dijadwalkan';
      case 'ongoing':
      case 'active':
        return 'Sedang Patroli';
      case 'finished':
      case 'completed':
        return 'Patroli Selesai';
      case 'canceled':
        return 'Patroli Dibatalkan';
      default:
        return 'Status Tidak Diketahui';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return warningY500;
      case 'ongoing':
      case 'active':
        return kbpBlue700;
      case 'finished':
      case 'completed':
        return successG500;
      case 'canceled':
        return dangerR500;
      default:
        return neutral500;
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return warningY50;
      case 'ongoing':
      case 'active':
        return kbpBlue50;
      case 'finished':
      case 'completed':
        return successG50;
      case 'canceled':
        return dangerR50;
      default:
        return neutral200;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return Icons.assignment;
      case 'ongoing':
      case 'active':
        return Icons.directions_run;
      case 'finished':
      case 'completed':
        return Icons.check_circle;
      case 'canceled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  Color _getTimelineColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return warningY500;
      case 'started':
        return kbpBlue700;
      case 'completed':
        return successG500;
      default:
        return neutral500;
    }
  }

  String _getProgressDescription(String status, int progress) {
    if (status.toLowerCase() == 'assigned') {
      return 'Patroli belum dimulai. Petugas akan segera memulai tugasnya.';
    } else if (status.toLowerCase() == 'ongoing' ||
        status.toLowerCase() == 'active') {
      return 'Patroli sedang berlangsung. Petugas telah mengunjungi $progress% dari total titik.';
    } else if (status.toLowerCase() == 'finished' ||
        status.toLowerCase() == 'completed') {
      return 'Patroli telah selesai. Semua titik telah dikunjungi.';
    } else if (status.toLowerCase() == 'canceled') {
      return 'Patroli dibatalkan. Petugas tidak menyelesaikan kunjungan.';
    }
    return 'Status patroli tidak diketahui.';
  }

  // Tambahkan method ini di dalam class _PatrolHistoryScreenState
  void _showFullScreenImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              'Foto Laporan Akhir',
              style: semiBoldTextStyle(color: Colors.white),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () async {
                  try {
                    // Menggunakan package share_plus untuk berbagi gambar
                    // await Share.share('Laporan patroli: $imageUrl');

                    // Alternatif: copy URL ke clipboard
                    await Clipboard.setData(ClipboardData(text: imageUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('URL foto disalin ke clipboard')),
                    );
                  } catch (e) {
                    print('Error sharing image: $e');
                  }
                },
                tooltip: 'Bagikan',
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(80),
              child: Hero(
                tag: 'final_report_photo',
                child: Image.network(
                  imageUrl,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.broken_image,
                          size: 64,
                          color: Colors.white70,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Gagal memuat gambar',
                          style: mediumTextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Coba Lagi'),
                          onPressed: () {
                            Navigator.of(context).pop();
                            _showFullScreenImage(imageUrl);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          // Tambahkan tombol untuk membuka di browser
          floatingActionButton: FloatingActionButton(
            backgroundColor: kbpBlue900,
            child: const Icon(Icons.open_in_browser),
            onPressed: () async {
              if (await canLaunch(imageUrl)) {
                await launch(imageUrl);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Tidak dapat membuka gambar di browser')),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  // Tambahkan metode ini di dalam _PatrolHistoryScreenState
  Map<String, dynamic> _calculateVisitedPoints({double radiusInMeters = 5.0}) {
    final Set<int> visitedCheckpoints = <int>{};
    final List<LatLng> routePositions = [];

    if (widget.task.routePath != null && widget.task.assignedRoute != null) {
      // Ekstrak posisi dari route path
      final routePathMap = Map<String, dynamic>.from(widget.task.routePath!);
      routePathMap.forEach((key, value) {
        final coordinates = value['coordinates'] as List;
        if (coordinates.length >= 2) {
          routePositions.add(LatLng(
            coordinates[0] as double,
            coordinates[1] as double,
          ));
        }
      });

      // Periksa jarak terdekat untuk setiap checkpoint
      for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
        final checkpoint = widget.task.assignedRoute![i];
        final checkpointLat = checkpoint[0] as double;
        final checkpointLng = checkpoint[1] as double;

        double minDistance = double.infinity;
        for (final position in routePositions) {
          final distance = Geolocator.distanceBetween(position.latitude,
              position.longitude, checkpointLat, checkpointLng);

          minDistance = Math.min(minDistance, distance);
          if (distance <= radiusInMeters) {
            visitedCheckpoints.add(i);
            break;
          }
        }
      }
    }

    return {
      'visitedCheckpoints': visitedCheckpoints,
      'routePositions': routePositions,
      'visitedCount': visitedCheckpoints.length,
      'totalCount': widget.task.assignedRoute?.length ?? 0,
    };
  }
}

// Custom painter for dashed lines
class DashedLinePainter extends CustomPainter {
  final Color color;

  DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashWidth = 5;
    const dashSpace = 3;
    double currentX = 0;

    while (currentX < size.width) {
      canvas.drawLine(
        Offset(currentX, size.height / 2),
        Offset(currentX + dashWidth, size.height / 2),
        paint,
      );
      currentX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
