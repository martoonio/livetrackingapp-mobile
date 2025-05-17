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
  State<OfficerManagementScreen> createState() => _OfficerManagementScreenState();
}

class _OfficerManagementScreenState extends State<OfficerManagementScreen> {
  final List<String> _shiftOptions = ['Pagi', 'Siang', 'Malam'];

  @override
  void initState() {
    super.initState();
    // Load cluster details
    context.read<AdminBloc>().add(LoadClusterDetails(clusterId: widget.clusterId));
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
          } else if (state is ClusterDetailsLoaded) {
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: neutral300,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: neutral300),
                        ),
                        child: Text(
                          'Shift ${officer.shift}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      8.width,
                      Text(
                        'ID: ${officer.id}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: neutral500,
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
    String selectedShift = _shiftOptions.first;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Tambah Petugas Baru',
          style: boldTextStyle(),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name field
              const Text(
                'Nama Petugas',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: neutral800,
                ),
              ),
              8.height,
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: 'Masukkan nama petugas',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Nama petugas wajib diisi';
                  }
                  return null;
                },
              ),
              16.height,
              
              // Shift selection
              const Text(
                'Shift Kerja',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: neutral800,
                ),
              ),
              8.height,
              DropdownButtonFormField<String>(
                value: selectedShift,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: _shiftOptions.map((shift) {
                  return DropdownMenuItem(
                    value: shift,
                    child: Text(shift),
                  );
                }).toList(),
                onChanged: (value) {
                  selectedShift = value!;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Batal'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kbpBlue900,
              foregroundColor: neutralWhite,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                // Create new officer
                final newOfficer = Officer(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text,
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
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
  }

  void _showEditOfficerDialog(BuildContext context, Officer officer) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: officer.name);
    String selectedShift = officer.shift;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Edit Petugas',
          style: boldTextStyle(),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name field
              const Text(
                'Nama Petugas',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: neutral800,
                ),
              ),
              8.height,
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Nama petugas wajib diisi';
                  }
                  return null;
                },
              ),
              16.height,
              
              // Shift selection
              const Text(
                'Shift Kerja',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: neutral800,
                ),
              ),
              8.height,
              DropdownButtonFormField<String>(
                value: selectedShift,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: _shiftOptions.map((shift) {
                  return DropdownMenuItem(
                    value: shift,
                    child: Text(shift),
                  );
                }).toList(),
                onChanged: (value) {
                  selectedShift = value!;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Batal'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kbpBlue900,
              foregroundColor: neutralWhite,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                // Update officer
                final updatedOfficer = Officer(
                  id: officer.id,
                  name: nameController.text,
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
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Officer officer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: Text(
          'Apakah Anda yakin ingin menghapus petugas "${officer.name}"?'
          '\n\nTindakan ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            child: const Text('Batal'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerR500,
              foregroundColor: neutralWhite,
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
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}