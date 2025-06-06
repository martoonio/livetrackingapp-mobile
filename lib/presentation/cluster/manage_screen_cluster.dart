import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/notification_utils.dart';
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

    final batteryLevel = tatarUser.batteryLevel;
    final batteryState = tatarUser.batteryState;
    final lastUpdate = tatarUser.lastBatteryUpdate;
    final shouldShowChargeButton = batteryLevel != null && batteryLevel <= 30;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: shouldShowChargeButton
            ? const Color(0xFFFFF3E0).withOpacity(
                0.8) // warningY50 - orange background for low battery
            : const Color(0xFFE3F2FD).withOpacity(0.3), // kbpBlue50
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: shouldShowChargeButton
              ? const Color(0xFFFFCC02).withOpacity(0.5) // warningY400
              : const Color(0xFF90CAF9).withOpacity(0.3), // kbpBlue200
        ),
      ),
      child: Column(
        children: [
          // Row pertama dengan battery level dan state
          Row(
            children: [
              // Battery icon dengan level
              Icon(
                _getBatteryIcon(batteryLevel),
                color: _getBatteryLevelColor(batteryLevel),
                size: 16,
              ),
              const SizedBox(width: 6),

              // Battery level text
              Text(
                batteryLevel != null ? '$batteryLevel%' : 'N/A',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _getBatteryLevelColor(batteryLevel),
                ),
              ),

              const SizedBox(width: 8),

              // Battery state indicator
              _buildBatteryStateChip(batteryState),

              // Spacer
              const Spacer(),

              // Update terakhir dengan icon
              if (lastUpdate != null) ...[
                const Icon(
                  Icons.access_time_rounded,
                  color: Color(0xFF757575), // neutral600
                  size: 11,
                ),
                const SizedBox(width: 3),
                Text(
                  _formatLastUpdate(lastUpdate),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF616161), // neutral700
                  ),
                ),
              ] else ...[
                const Icon(
                  Icons.help_outline_rounded,
                  color: Color(0xFF9E9E9E), // neutral500
                  size: 11,
                ),
                const SizedBox(width: 3),
                const Text(
                  'Belum ada data',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9E9E9E), // neutral500
                  ),
                ),
              ],
            ],
          ),

          // Battery status detail untuk semua state
          if (batteryState != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  _getBatteryStateIcon(batteryState),
                  color: _getChargingColor(batteryState),
                  size: 12,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _getChargingStatusText(batteryState, batteryLevel),
                    style: TextStyle(
                      fontSize: 10,
                      color: _getChargingColor(batteryState),
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // TAMBAHAN: Charge notification button (hanya muncul jika battery <= 30%)
          if (shouldShowChargeButton) ...[
            const SizedBox(height: 8),
            _buildChargeNotificationButton(tatarUser),
          ],
        ],
      ),
    );
  }

  // TAMBAHAN: Button untuk mengirim notifikasi pengingat charge
  Widget _buildChargeNotificationButton(User tatarUser) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _sendChargeNotification(tatarUser),
        icon: const Icon(
          Icons.battery_alert,
          size: 14,
          color: Colors.white,
        ),
        label: const Text(
          'Kirim Pengingat Charge',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF8F00), // warningY600
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          shadowColor: const Color(0xFFFF8F00).withOpacity(0.3),
        ),
      ),
    );
  }

  // TAMBAHAN: Method untuk mengirim notifikasi charge
  Future<void> _sendChargeNotification(User tatarUser) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: Color(0xFFFF8F00), // warningY600
                ),
                const SizedBox(height: 16),
                Text(
                  'Mengirim notifikasi...',
                  style: mediumTextStyle(size: 14),
                ),
              ],
            ),
          ),
        ),
      );

      // IMPLEMENTASI: Kirim notifikasi via notification_utils
      final success = await sendLowBatteryChargeReminderNotification(
        officerId: tatarUser.id,
        officerName: tatarUser.name,
        clusterName:
            tatarUser.name, // Assuming cluster name is user name for tatar
        batteryLevel: tatarUser.batteryLevel ?? 0,
        batteryState: tatarUser.batteryState ?? 'unknown',
      );

      // Close loading dialog
      if (context.mounted) Navigator.of(context).pop();

      if (success) {
        // Show success message
        _showNotificationDialog(
          title: 'Berhasil',
          message:
              'Notifikasi pengingat charge berhasil dikirim ke ${tatarUser.name}',
          icon: Icons.check_circle,
          iconColor: const Color(0xFF4CAF50), // successG500
        );
      } else {
        _showNotificationDialog(
          title: 'Gagal',
          message:
              'Gagal mengirim notifikasi: Tidak ada token perangkat yang valid',
          icon: Icons.error_outline,
          iconColor: const Color(0xFFD32F2F), // dangerR500
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (context.mounted) Navigator.of(context).pop();

      // Show error message
      _showNotificationDialog(
        title: 'Gagal',
        message: 'Gagal mengirim notifikasi: ${e.toString()}',
        icon: Icons.error_outline,
        iconColor: const Color(0xFFD32F2F), // dangerR500
      );
    }
  }

  // TAMBAHAN: Dialog untuk menampilkan hasil notifikasi
  void _showNotificationDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 10.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                title,
                style: boldTextStyle(size: 18),
              ),
              const SizedBox(height: 8),

              // Message
              Text(
                message,
                textAlign: TextAlign.center,
                style: regularTextStyle(
                    color: const Color(0xFF616161)), // neutral700
              ),
              const SizedBox(height: 24),

              // OK Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatteryStateChip(String? batteryState) {
    if (batteryState == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE0E0E0), // neutral300
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.help_outline,
              size: 8,
              color: Color(0xFF9E9E9E), // neutral500
            ),
            const SizedBox(width: 2),
            const Text(
              'Unknown',
              style: TextStyle(
                fontSize: 8,
                color: Color(0xFF9E9E9E), // neutral500
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final color = _getBatteryStateColor(batteryState);
    final icon = _getBatteryStateIcon(batteryState);
    final text = _getBatteryStateText(batteryState);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 8,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // TAMBAHAN: Helper methods untuk battery state

  bool _isCharging(String? batteryState) {
    if (batteryState == null) return false;
    return batteryState.toLowerCase() == 'charging';
  }

  Color _getBatteryStateColor(String batteryState) {
    final state = batteryState.toLowerCase();
    switch (state) {
      case 'charging':
        return const Color(0xFF2E7D32); // successG700 - hijau untuk charging
      case 'discharging':
        return const Color(
            0xFFFF8F00); // warningY600 - orange untuk discharging
      case 'connectednotcharging':
        return const Color(
            0xFF1565C0); // kbpBlue600 - biru untuk connected not charging
      default:
        return const Color(0xFF9E9E9E); // neutral500 - abu untuk unknown
    }
  }

  Color _getChargingColor(String batteryState) {
    final state = batteryState.toLowerCase();
    switch (state) {
      case 'charging':
        return const Color(0xFF4CAF50); // successG500 - hijau untuk charging
      case 'connectednotcharging':
        return const Color(
            0xFF2196F3); // kbpBlue500 - biru untuk connected not charging
      default:
        return const Color(0xFF2E7D32); // successG700 - default
    }
  }

  IconData _getBatteryStateIcon(String batteryState) {
    final state = batteryState.toLowerCase();
    switch (state) {
      case 'charging':
        return Icons.power; // Charging icon
      case 'discharging':
        return Icons.power_off; // Discharging icon
      case 'connectednotcharging':
        return Icons.power_outlined; // Connected but not charging
      default:
        return Icons.battery_unknown; // Unknown state
    }
  }

  String _getBatteryStateText(String batteryState) {
    final state = batteryState.toLowerCase();
    switch (state) {
      case 'charging':
        return 'Charging';
      case 'discharging':
        return 'Discharge';
      case 'connectednotcharging':
        return 'Connected';
      default:
        return 'Unknown';
    }
  }

  String _getChargingStatusText(String batteryState, int? batteryLevel) {
    final state = batteryState.toLowerCase();
    switch (state) {
      case 'charging':
        if (batteryLevel != null && batteryLevel >= 95) {
          return 'Hampir penuh (${batteryLevel}%)';
        } else if (batteryLevel != null && batteryLevel >= 80) {
          return 'Sedang mengisi daya (${batteryLevel}%)';
        }
        return 'Sedang mengisi daya';

      case 'connectednotcharging':
        if (batteryLevel != null && batteryLevel >= 95) {
          return 'Terhubung - Battery penuh';
        }
        return 'Terhubung tapi tidak mengisi';

      case 'discharging':
        if (batteryLevel != null && batteryLevel <= 20) {
          return 'Battery hampir habis (${batteryLevel}%)';
        } else if (batteryLevel != null && batteryLevel <= 50) {
          return 'Battery sedang (${batteryLevel}%)';
        }
        return 'Sedang digunakan';

      default:
        return 'Status tidak diketahui';
    }
  }

  // EXISTING: Battery level color dengan null handling (keep as is)
  Color _getBatteryLevelColor(int? batteryLevel) {
    if (batteryLevel == null) return const Color(0xFF9E9E9E); // neutral500
    if (batteryLevel < 20) return const Color(0xFFD32F2F); // dangerR500
    if (batteryLevel <= 50) return const Color(0xFFFF9800); // warningY500
    return const Color(0xFF4CAF50); // successG500
  }

  // EXISTING: Helper methods untuk battery display (keep existing)
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
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
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
