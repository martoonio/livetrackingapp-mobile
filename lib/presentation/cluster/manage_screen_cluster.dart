import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/cluster/cluster_detail_screen.dart';
import 'package:livetrackingapp/presentation/cluster/create_cluster_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart';
// NEW IMPORT: For date formatting
import 'package:intl/intl.dart';

class ManageClustersScreen extends StatefulWidget {
  const ManageClustersScreen({Key? key}) : super(key: key);

  @override
  State<ManageClustersScreen> createState() => _ManageClustersScreenState();
}

class _ManageClustersScreenState extends State<ManageClustersScreen> {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    context.read<AdminBloc>().add(const LoadAllClusters());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Tatar'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: BlocBuilder<AdminBloc, AdminState>(
              builder: (context, state) {
                if (state is AdminLoading) {
                  return Center(
                    child: LottieBuilder.asset(
                      'assets/lottie/maps_loading.json',
                      width: 200,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  );
                } else if (state is ClustersLoaded) {
                  return _buildClustersList(state.clusters);
                } else if (state is AdminError) {
                  return Center(
                    child: Text(
                      'Error: ${state.message}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                return Center(
                  child: LottieBuilder.asset(
                    'assets/lottie/maps_loading.json',
                    width: 200,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kbpBlue900,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateClusterScreen(),
            ),
          ).then((_) {
            // Reload clusters after returning
            context.read<AdminBloc>().add(LoadAllClusters());
          });
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Cari cluster...',
          prefixIcon: const Icon(Icons.search, color: kbpBlue900),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: kbpBlue900),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                    context.read<AdminBloc>().add(LoadAllClusters());
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kbpBlue700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kbpBlue700),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kbpBlue900, width: 2),
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
          if (_searchQuery.isEmpty) {
            context.read<AdminBloc>().add(LoadAllClusters());
          } else {
            context.read<AdminBloc>().add(SearchClustersEvent(_searchQuery));
          }
        },
      ),
    );
  }

  Widget _buildClustersList(List<User> clusters) {
    if (clusters.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_city_outlined,
              size: 64,
              color: neutral400,
            ),
            const SizedBox(height: 16),
            Text(
              'Tidak ada cluster ditemukan',
              style: semiBoldTextStyle(size: 16, color: neutral600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tambahkan cluster baru untuk mulai mengelola',
              style: regularTextStyle(size: 14, color: neutral500),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: clusters.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final cluster = clusters[index];
        return _buildEnhancedClusterCard(cluster);
      },
    );
  }

  // NEW: Get tatar battery info untuk cluster ini (hanya 1 user per cluster)
  User? _getTatarUser(String clusterId) {
    final adminState = context.read<AdminBloc>().state;

    if (adminState is AdminLoaded) {
      // Cari user yang merupakan tatar untuk cluster ini
      // Cluster ID sama dengan User ID untuk tatar
      try {
        return adminState.clusters.firstWhere(
          (user) => user.id == clusterId && user.role == 'patrol',
        );
      } catch (e) {
        return null; // Tidak ditemukan tatar user
      }
    }

    return null;
  }

  // UPDATE: Enhanced cluster card dengan tampilan battery yang lebih sederhana
  Widget _buildEnhancedClusterCard(User cluster) {
    final officers = cluster.officers ?? [];
    final officerCount = officers.length;

    // Get tatar user battery info (hanya 1 user per cluster)
    final tatarUser = cluster;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side:
            const BorderSide(color: Color(0xFF90CAF9), width: 1), // kbpBlue200
      ),
      elevation: 3,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClusterDetailScreen(clusterId: cluster.id),
            ),
          ).then((_) {
            context.read<AdminBloc>().add(const LoadAllClusters());
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section - HAPUS status online/offline
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF1565C0),
                          Color(0xFF0D47A1)
                        ], // kbpBlue600, kbpBlue800
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1565C0).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_city_rounded,
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
                          cluster.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cluster.email,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF757575), // neutral600
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Statistics Section
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.people_rounded,
                      label: 'Total Petugas',
                      value: officerCount.toString(),
                      color: const Color(0xFF1565C0), // kbpBlue600
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.location_on_rounded,
                      label: 'Koordinat',
                      value: '${cluster.clusterCoordinates?.length ?? 0}',
                      color: const Color(0xFFFF8F00), // warningY600
                    ),
                  ),
                ],
              ),

              // NEW: Battery Status Section yang disederhanakan
              const SizedBox(height: 16),
              _buildSimpleBatteryInfo(tatarUser),

              const SizedBox(height: 16),

              // Action Buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ClusterDetailScreen(
                              clusterId: cluster.id,
                              initialTab: 2, // Officers tab
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.people_outline, size: 16),
                      label: Text(
                        'Kelola Petugas',
                        style: mediumTextStyle(color: kbpBlue700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1976D2), // kbpBlue700
                        side: const BorderSide(
                            color: Color(0xFF64B5F6)), // kbpBlue300
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ClusterDetailScreen(clusterId: cluster.id),
                          ),
                        );
                      },
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text('Detail'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2), // kbpBlue700
                        foregroundColor: Colors.white,
                        elevation: 2,
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
    );
  }

  // NEW: Simplified battery info - hanya level baterai dan update terakhir
  Widget _buildSimpleBatteryInfo(User? tatarUser) {
    if (tatarUser == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5), // neutral100
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0E0E0)), // neutral300
        ),
        child: Row(
          children: [
            const Icon(
              Icons.smartphone_outlined,
              color: Color(0xFF9E9E9E), // neutral500
              size: 16,
            ),
            const SizedBox(width: 8),
            const Text(
              'Akun tatar belum terdaftar',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF616161), // neutral700
              ),
            ),
          ],
        ),
      );
    }

    // Get battery info
    final batteryLevel = tatarUser.batteryLevel;
    final lastUpdate = tatarUser.lastBatteryUpdate;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD).withOpacity(0.3), // kbpBlue50
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFF90CAF9).withOpacity(0.3)), // kbpBlue200
      ),
      child: Row(
        children: [
          // Battery icon dengan level
          Icon(
            _getBatteryIcon(batteryLevel),
            color: _getBatteryLevelColor(batteryLevel),
            size: 16,
          ),
          const SizedBox(width: 8),

          // Battery level text
          Text(
            batteryLevel != null ? '$batteryLevel%' : 'Tidak diketahui',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _getBatteryLevelColor(batteryLevel),
            ),
          ),

          // Spacer
          const Spacer(),

          // Update terakhir dengan icon
          if (lastUpdate != null) ...[
            const Icon(
              Icons.access_time_rounded,
              color: Color(0xFF757575), // neutral600
              size: 12,
            ),
            const SizedBox(width: 4),
            Text(
              _formatLastUpdate(lastUpdate),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF616161), // neutral700
              ),
            ),
          ] else ...[
            const Icon(
              Icons.help_outline_rounded,
              color: Color(0xFF9E9E9E), // neutral500
              size: 12,
            ),
            const SizedBox(width: 4),
            const Text(
              'Belum ada data',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF9E9E9E), // neutral500
              ),
            ),
          ],
        ],
      ),
    );
  }

  // UPDATE: Battery level color dengan null handling
  Color _getBatteryLevelColor(int? batteryLevel) {
    if (batteryLevel == null) return const Color(0xFF9E9E9E); // neutral500
    if (batteryLevel < 20) return const Color(0xFFD32F2F); // dangerR500
    if (batteryLevel <= 50) return const Color(0xFFFF9800); // warningY500
    return const Color(0xFF4CAF50); // successG500
  }

  // Helper methods untuk battery display (keep existing)
  IconData _getBatteryIcon(int? batteryLevel) {
    if (batteryLevel == null) return Icons.battery_unknown_rounded;
    if (batteryLevel > 80) return Icons.battery_full_rounded;
    if (batteryLevel > 60) return Icons.battery_6_bar_rounded;
    if (batteryLevel > 40) return Icons.battery_4_bar_rounded;
    if (batteryLevel > 20) return Icons.battery_2_bar_rounded;
    return Icons.battery_1_bar_rounded;
  }

  String _formatLastUpdate(DateTime lastUpdate) {
    final now = DateTime.now();
    final difference = now.difference(lastUpdate);

    if (difference.inMinutes < 1) {
      return 'Baru saja';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} menit lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} jam lalu';
    } else {
      return DateFormat('dd/MM').format(lastUpdate);
    }
  }

  // Keep existing _buildStatItem method
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF757575), // neutral600
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
