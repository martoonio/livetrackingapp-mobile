import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart';

class OfficerManagementScreen extends StatefulWidget {
  final String clusterId;
  final String clusterName;

  const OfficerManagementScreen({
    Key? key,
    required this.clusterId,
    required this.clusterName,
  }) : super(key: key);

  @override
  State<OfficerManagementScreen> createState() =>
      _OfficerManagementScreenState();
}

class _OfficerManagementScreenState extends State<OfficerManagementScreen> {
  // Map untuk menampung shift options berdasarkan tipe
  final Map<OfficerType, List<ShiftType>> _typeShifts = {
    OfficerType.organik: [
      ShiftType.pagi, // 07:00-15:00
      ShiftType.sore, // 15:00-23:00
      ShiftType.malam, // 23:00-07:00
    ],
    OfficerType.outsource: [
      ShiftType.siang, // 07:00-19:00
      ShiftType.malamPanjang, // 19:00-07:00
    ],
  };

  @override
  void initState() {
    super.initState();
    // Load cluster details
    context.read<AdminBloc>().add(GetClusterDetail(widget.clusterId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Petugas ${widget.clusterName}'),
        backgroundColor: kbpBlue900,
        foregroundColor: neutralWhite,
      ),
      body: BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) {
          if (state is ClusterDetailsLoading) {
            return Center(
              child: Lottie.asset(
                'assets/lottie/maps_loading.json',
                width: 200,
                height: 100,
              ),
            );
          } else if (state is ClusterDetailLoaded) {
            final officers = state.cluster.officers ?? [];

            return Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: kbpBlue50,
                  child: Row(
                    children: [
                      const Icon(Icons.people, color: kbpBlue900),
                      16.width,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Petugas: ${officers.length}',
                              style: boldTextStyle(),
                            ),
                            Text(
                              'Pengelolaan petugas yang tergabung dalam cluster ${widget.clusterName}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: neutral600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Officer list
                Expanded(
                  child: officers.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: officers.length,
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, index) {
                            final officer = officers[index];
                            return _buildOfficerCard(officer);
                          },
                        ),
                ),
              ],
            );
          } else if (state is ClusterDetailsError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: dangerR300),
                  16.height,
                  Text(
                    'Error: ${state.message}',
                    textAlign: TextAlign.center,
                  ),
                  24.height,
                  ElevatedButton(
                    child: const Text('Coba Lagi'),
                    onPressed: () {
                      context.read<AdminBloc>().add(
                            LoadClusterDetails(clusterId: widget.clusterId),
                          );
                    },
                  ),
                ],
              ),
            );
          }

          print('Unknown state: $state');

          return const Center(child: CircularProgressIndicator());
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kbpBlue900,
        child: const Icon(Icons.add, color: neutralWhite),
        onPressed: () => _showAddOfficerDialog(context),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, size: 64, color: neutral400),
          24.height,
          const Text(
            'Belum ada petugas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: neutral600,
            ),
          ),
          8.height,
          const Text(
            'Tambahkan petugas untuk cluster ini',
            style: TextStyle(color: neutral500),
          ),
          24.height,
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Tambah Petugas'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kbpBlue900,
              foregroundColor: neutralWhite,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
            onPressed: () => _showAddOfficerDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildOfficerCard(Officer officer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar or default icon
            CircleAvatar(
              radius: 24,
              backgroundColor: kbpBlue100,
              backgroundImage: officer.photoUrl != null
                  ? NetworkImage(officer.photoUrl!)
                  : null,
              child: officer.photoUrl == null
                  ? const Icon(Icons.person, color: kbpBlue900)
                  : null,
            ),
            16.width,
            // Officer details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    officer.name,
                    style: boldTextStyle(),
                  ),
                  8.height,
                  Wrap(
                    spacing: 8,
                    children: [
                      // Tipe badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: officer.type == OfficerType.organik
                              ? successG50
                              : warningY50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          officer.typeDisplay,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: officer.type == OfficerType.organik
                                ? successG500
                                : warningY500,
                          ),
                        ),
                      ),

                      // Shift badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kbpBlue50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          getShortShiftText(officer.shift),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: kbpBlue700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Actions
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditOfficerDialog(context, officer);
                } else if (value == 'delete') {
                  _showDeleteConfirmation(officer);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: dangerR500),
                      SizedBox(width: 8),
                      Text('Hapus', style: TextStyle(color: dangerR500)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOfficerDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    OfficerType selectedType = OfficerType.organik;
    ShiftType selectedShift = _typeShifts[OfficerType.organik]!.first;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Tambah Petugas Baru',
            style: boldTextStyle(color: kbpBlue900),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name field
                  Text(
                    'Nama Petugas',
                    style: mediumTextStyle(size: 14, color: neutral800),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: 'Masukkan nama petugas',
                      hintStyle: regularTextStyle(size: 14, color: neutral500),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: neutral300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: kbpBlue700, width: 1.5),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Nama petugas wajib diisi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Tipe Petugas selection
                  Text(
                    'Tipe Petugas',
                    style: mediumTextStyle(size: 14, color: neutral800),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: neutral300),
                    ),
                    child: DropdownButtonFormField<OfficerType>(
                      value: selectedType,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: InputBorder.none,
                        hintStyle:
                            regularTextStyle(size: 14, color: neutral600),
                      ),
                      style: mediumTextStyle(size: 14, color: neutral800),
                      items: OfficerType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type == OfficerType.organik
                              ? 'Organik'
                              : 'Outsource'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedType = value;
                            // Reset shift ke opsi pertama untuk tipe yang dipilih
                            selectedShift = _typeShifts[value]!.first;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Shift selection - dinamis berdasarkan tipe
                  Text(
                    'Shift Kerja',
                    style: mediumTextStyle(size: 14, color: neutral800),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: neutral300),
                    ),
                    child: DropdownButtonFormField<ShiftType>(
                      value: selectedShift,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: InputBorder.none,
                        hintStyle:
                            regularTextStyle(size: 14, color: neutral600),
                      ),
                      style: mediumTextStyle(size: 14, color: neutral800),
                      items: _typeShifts[selectedType]!.map((shift) {
                        return DropdownMenuItem(
                          value: shift,
                          child: Text(_getShiftDisplayText(shift)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedShift = value;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kbpBlue900,
                        side: const BorderSide(color: kbpBlue900),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Batal',
                        style: mediumTextStyle(color: kbpBlue900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kbpBlue900,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          // Create new officer
                          final newOfficer = Officer(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            name: nameController.text.trim(),
                            type: selectedType,
                            shift: selectedShift,
                            clusterId: widget.clusterId,
                          );

                          context.read<AdminBloc>().add(
                                AddOfficerToClusterEvent(
                                  clusterId: widget.clusterId,
                                  officer: newOfficer,
                                ),
                              );

                          Navigator.pop(context);

                          showCustomSnackbar(
                            context: context,
                            title: 'Berhasil',
                            subtitle: 'Petugas baru telah ditambahkan',
                            type: SnackbarType.success,
                          );
                        }
                      },
                      child: Text(
                        'Tambah',
                        style: mediumTextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditOfficerDialog(BuildContext context, Officer officer) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: officer.name);
    OfficerType selectedType = officer.type;
    ShiftType selectedShift = officer.shift;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Edit Petugas',
            style: boldTextStyle(color: kbpBlue900),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name field
                  Text(
                    'Nama Petugas',
                    style: mediumTextStyle(size: 14, color: neutral800),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: 'Masukkan nama petugas',
                      hintStyle: regularTextStyle(size: 14, color: neutral500),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: neutral300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: kbpBlue700, width: 1.5),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Nama petugas wajib diisi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Tipe Petugas selection
                  Text(
                    'Tipe Petugas',
                    style: mediumTextStyle(size: 14, color: neutral800),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: neutral300),
                    ),
                    child: DropdownButtonFormField<OfficerType>(
                      value: selectedType,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: InputBorder.none,
                        hintStyle:
                            regularTextStyle(size: 14, color: neutral600),
                      ),
                      style: mediumTextStyle(size: 14, color: neutral800),
                      items: OfficerType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type == OfficerType.organik
                              ? 'Organik'
                              : 'Outsource'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedType = value;
                            // Reset shift ke opsi pertama untuk tipe yang dipilih
                            if (!_typeShifts[value]!.contains(selectedShift)) {
                              selectedShift = _typeShifts[value]!.first;
                            }
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Shift selection - dinamis berdasarkan tipe
                  Text(
                    'Shift Kerja',
                    style: mediumTextStyle(size: 14, color: neutral800),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: neutral300),
                    ),
                    child: DropdownButtonFormField<ShiftType>(
                      value: _typeShifts[selectedType]!.contains(selectedShift)
                          ? selectedShift
                          : _typeShifts[selectedType]!.first,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: InputBorder.none,
                        hintStyle:
                            regularTextStyle(size: 14, color: neutral600),
                      ),
                      style: mediumTextStyle(size: 14, color: neutral800),
                      items: _typeShifts[selectedType]!.map((shift) {
                        return DropdownMenuItem(
                          value: shift,
                          child: Text(_getShiftDisplayText(shift)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedShift = value;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kbpBlue900,
                        side: const BorderSide(color: kbpBlue900),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Batal',
                        style: mediumTextStyle(color: kbpBlue900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kbpBlue900,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          // Update officer
                          final updatedOfficer = Officer(
                            id: officer.id,
                            name: nameController.text.trim(),
                            type: selectedType,
                            shift: selectedShift,
                            clusterId: widget.clusterId,
                            photoUrl: officer.photoUrl,
                          );

                          context.read<AdminBloc>().add(
                                UpdateOfficerInClusterEvent(
                                  clusterId: widget.clusterId,
                                  officer: updatedOfficer,
                                ),
                              );

                          Navigator.pop(context);

                          showCustomSnackbar(
                            context: context,
                            title: 'Berhasil',
                            subtitle: 'Informasi petugas telah diperbarui',
                            type: SnackbarType.success,
                          );
                        }
                      },
                      child: Text(
                        'Simpan',
                        style: mediumTextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Officer officer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Konfirmasi Hapus',
          style: boldTextStyle(color: dangerR500),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: warningY500, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Anda akan menghapus petugas ini',
                    style: semiBoldTextStyle(size: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Apakah Anda yakin ingin menghapus petugas "${officer.name}"? Tindakan ini tidak dapat dibatalkan.',
              style: regularTextStyle(size: 14, color: neutral700),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kbpBlue900,
                    side: const BorderSide(color: kbpBlue900),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Batal',
                    style: mediumTextStyle(color: kbpBlue900),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dangerR500,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  onPressed: () {
                    context.read<AdminBloc>().add(
                          RemoveOfficerFromClusterEvent(
                            clusterId: widget.clusterId,
                            officerId: officer.id,
                          ),
                        );

                    Navigator.pop(context);

                    showCustomSnackbar(
                      context: context,
                      title: 'Berhasil',
                      subtitle: 'Petugas telah dihapus dari cluster',
                      type: SnackbarType.success,
                    );
                  },
                  child: Text(
                    'Hapus',
                    style: mediumTextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper untuk mendapatkan text shift pendek
  String getShortShiftText(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi (07-15)';
      case ShiftType.sore:
        return 'Sore (15-23)';
      case ShiftType.malam:
        return 'Malam (23-07)';
      case ShiftType.siang:
        return 'Siang (07-19)';
      case ShiftType.malamPanjang:
        return 'Malam (19-07)';
    }
  }

  // Helper untuk mendapatkan teks shift lengkap
  String _getShiftDisplayText(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi (07:00 - 15:00)';
      case ShiftType.sore:
        return 'Sore (15:00 - 23:00)';
      case ShiftType.malam:
        return 'Malam (23:00 - 07:00)';
      case ShiftType.siang:
        return 'Siang (07:00 - 19:00)';
      case ShiftType.malamPanjang:
        return 'Malam (19:00 - 07:00)';
    }
  }
}
