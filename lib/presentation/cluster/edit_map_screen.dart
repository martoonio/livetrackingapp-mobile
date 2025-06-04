import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class EditMapScreen extends StatefulWidget {
  final String clusterId;
  final List<LatLng> points;
  final String clusterName;

  const EditMapScreen({
    Key? key,
    required this.clusterId,
    required this.points,
    required this.clusterName,
  }) : super(key: key);

  @override
  State<EditMapScreen> createState() => _EditMapScreenState();
}

class _EditMapScreenState extends State<EditMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  List<LatLng> _selectedPoints = [];
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _selectedPoints = List<LatLng>.from(widget.points);
    _updateMarkers();
  }

  // PERBAIKAN: Update method _updateMarkers untuk handle tap pada marker
  void _updateMarkers() {
    _markers.clear();
    for (int i = 0; i < _selectedPoints.length; i++) {
      _markers.add(
        Marker(
          markerId: MarkerId('point_$i'),
          position: _selectedPoints[i],
          infoWindow: InfoWindow(
            title: 'Titik ${i + 1}',
            snippet: 'Tap untuk menghapus',
          ),
          // TAMBAHAN: Custom icon untuk membedakan marker yang bisa dihapus
          icon: BitmapDescriptor.defaultMarkerWithHue(
            i == 0 ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
          ),
          // TAMBAHAN: onTap callback untuk handle tap pada marker
          onTap: () => _showDeleteMarkerDialog(i),
        ),
      );
    }
  }

  void _handleMapTap(LatLng position) {
    setState(() {
      _selectedPoints.add(position);
      _updateMarkers();
      _hasChanges = true;
    });
  }

  // TAMBAHAN: Method untuk menampilkan dialog konfirmasi hapus marker
  void _showDeleteMarkerDialog(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: dangerR500,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Hapus Titik',
                style: boldTextStyle(size: 18, color: dangerR500),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Apakah Anda yakin ingin menghapus Titik ${index + 1}?',
                style: regularTextStyle(color: neutral700, size: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: warningY50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: warningY200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: warningY400,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Penghapusan titik akan mengubah urutan titik-titik berikutnya',
                        style: regularTextStyle(color: warningY500, size: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: neutral600,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: neutral300),
                ),
              ),
              child: Text(
                'Batal',
                style: mediumTextStyle(color: neutral600),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _deleteMarker(index);
              },
              icon: const Icon(Icons.delete, size: 18, color: Colors.white),
              label: Text(
                'Hapus',
                style: mediumTextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: dangerR500,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
          elevation: 8,
          backgroundColor: Colors.white,
        );
      },
    );
  }

  // TAMBAHAN: Method untuk menghapus marker berdasarkan index
  void _deleteMarker(int index) {
    if (index >= 0 && index < _selectedPoints.length) {
      setState(() {
        _selectedPoints.removeAt(index);
        _updateMarkers();
        _hasChanges = true;
      });

      // TAMBAHAN: Tampilkan snackbar konfirmasi
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Titik ${index + 1} berhasil dihapus',
                style: mediumTextStyle(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: successG500,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );

      // TAMBAHAN: Zoom ke titik-titik yang tersisa jika ada
      if (_selectedPoints.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _zoomToPoints();
        });
      }
    }
  }

  // TAMBAHAN: Method untuk menghapus semua marker
  void _clearAllMarkers() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.clear_all,
                color: dangerR500,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Hapus Semua Titik',
                style: boldTextStyle(size: 18, color: dangerR500),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Apakah Anda yakin ingin menghapus semua ${_selectedPoints.length} titik patroli?',
                style: regularTextStyle(color: neutral700, size: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: dangerR50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: dangerR200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: dangerR500,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tindakan ini tidak dapat dibatalkan',
                        style: semiBoldTextStyle(color: dangerR300, size: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: neutral600,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: neutral300),
                ),
              ),
              child: Text(
                'Batal',
                style: mediumTextStyle(color: neutral600),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _selectedPoints.clear();
                  _updateMarkers();
                  _hasChanges = true;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Semua titik berhasil dihapus',
                          style: mediumTextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    backgroundColor: successG500,
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              },
              icon: const Icon(Icons.clear_all, size: 18, color: Colors.white),
              label: Text(
                'Hapus Semua',
                style: mediumTextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: dangerR500,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
          elevation: 8,
          backgroundColor: Colors.white,
        );
      },
    );
  }

  void _zoomToPoints() {
    if (_selectedPoints.isEmpty || _mapController == null) return;

    try {
      double minLat = double.infinity;
      double maxLat = -double.infinity;
      double minLng = double.infinity;
      double maxLng = -double.infinity;

      for (var point in _selectedPoints) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      // Add padding
      final padding = 0.002; // About 200 meters
      minLat -= padding;
      maxLat += padding;
      minLng -= padding;
      maxLng += padding;

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50),
      );
    } catch (e) {
      print('Error zooming to points: $e');
    }
  }

  void _saveChanges() {
    final coordinates = _selectedPoints
        .map((point) => [point.latitude, point.longitude])
        .toList();

    context.read<AdminBloc>().add(
          UpdateClusterCoordinates(
            clusterId: widget.clusterId,
            coordinates: coordinates,
          ),
        );

    Navigator.pop(context, _selectedPoints);
  }

  void _showDiscardChangesDialog() {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Batalkan Perubahan',
          style: boldTextStyle(size: 18, color: kbpBlue900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: warningY500,
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              'Anda memiliki perubahan yang belum disimpan. Apakah Anda yakin ingin membatalkan perubahan?',
              style: regularTextStyle(color: neutral700),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.all(16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: kbpBlue900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Lanjutkan Mengedit',
              style: mediumTextStyle(color: kbpBlue900),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerR500,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Buang Perubahan',
              style: mediumTextStyle(color: Colors.white),
            ),
          ),
        ],
        actionsAlignment: MainAxisAlignment.end,
        elevation: 4,
        backgroundColor: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_hasChanges) {
          _showDiscardChangesDialog();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Edit Titik Patroli - ${widget.clusterName}'),
          backgroundColor: kbpBlue900,
          foregroundColor: Colors.white,
          actions: [
            // TAMBAHAN: Icon button untuk hapus semua
            if (_selectedPoints.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.clear_all),
                onPressed: _clearAllMarkers,
                tooltip: 'Hapus Semua Titik',
              ),
            ],
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _zoomToPoints,
              tooltip: 'Zoom ke Titik',
            ),
          ],
        ),
        body: Stack(
          children: [
            GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: _selectedPoints.isNotEmpty
                  ? CameraPosition(
                      target: _selectedPoints.first,
                      zoom: 17,
                    )
                  : const CameraPosition(
                      target: LatLng(-6.8737, 107.5757), // Default: Bandung
                      zoom: 14,
                    ),
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              onTap: _handleMapTap,
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                if (_selectedPoints.isNotEmpty) {
                  _zoomToPoints();
                }
              },
            ),

            // TAMBAHAN: Info overlay untuk instruksi
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: kbpBlue900,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Klik peta untuk tambah titik, klik marker untuk hapus',
                        style: mediumTextStyle(color: kbpBlue900, size: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom action panel - PERBAIKAN
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Titik Patroli (${_selectedPoints.length})',
                          style: boldTextStyle(size: 16),
                        ),
                        if (_selectedPoints.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: successG100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 12,
                                  color: successG300,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_selectedPoints.length} titik',
                                  style: semiBoldTextStyle(
                                      color: successG300, size: 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Klik pada peta untuk menambah titik baru. Klik pada marker untuk menghapus titik tersebut.',
                      style: regularTextStyle(color: neutral600, size: 12),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _selectedPoints.isEmpty
                                ? null
                                : () {
                                    setState(() {
                                      if (_selectedPoints.isNotEmpty) {
                                        _selectedPoints.removeLast();
                                        _updateMarkers();
                                        _hasChanges = true;
                                      }
                                    });
                                  },
                            icon: const Icon(Icons.undo,
                                color: Colors.white, size: 18),
                            label: const Text('Undo Terakhir'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kbpBlue700,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: neutral300,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _selectedPoints.isEmpty ? null : _saveChanges,
                            icon: const Icon(Icons.save,
                                color: Colors.white, size: 18),
                            label: const Text('Simpan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kbpBlue900,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: neutral300,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
