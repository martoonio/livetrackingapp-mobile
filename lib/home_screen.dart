// lib/home_screen.dart

import 'dart:async';
import 'dart:developer';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:livetrackingapp/map_screen.dart';
import 'package:livetrackingapp/notification_utils.dart';
import 'package:livetrackingapp/patrol_summary_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart' as lottie;
import '../../domain/entities/patrol_task.dart';
import '../../domain/entities/user.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';
import 'presentation/task/task_dialog.dart';
import 'presentation/patrol/patrol_history_list_screen.dart'; // Pastikan ini diimpor

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _taskSubscription;
  User? _currentUser;

  // Variabel untuk lastKey pagination
  String? _upcomingLastKey;
  String? _historyLastKey;
  String? _ongoingLastKey;

  // Pagination variables untuk upcoming tasks
  List<PatrolTask> _allUpcomingTasks = [];
  List<PatrolTask> _displayedUpcomingTasks = [];
  int _upcomingCurrentPage = 0;
  final int _upcomingItemsPerPage = 10;
  bool _hasMoreUpcomingTasks = false;
  bool _isLoadingMoreUpcoming = false;

  // Pagination variables untuk history tasks
  List<PatrolTask> _allHistoryTasks = [];
  List<PatrolTask> _displayedHistoryTasks = [];
  int _historyCurrentPage = 0;
  final int _historyItemsPerPage = 10;
  bool _hasMoreHistoryTasks = false;
  bool _isLoadingMoreHistory = false;

  // Pagination variables untuk ongoing tasks
  List<PatrolTask> _allOngoingTasks = [];
  List<PatrolTask> _displayedOngoingTasks = [];
  int _ongoingCurrentPage = 0;
  final int _ongoingItemsPerPage = 10;
  bool _hasMoreOngoingTasks = false;
  bool _isLoadingMoreOngoing = false;

  bool _isLoading = true; // State loading utama
  bool _isUpcomingExpanded =
      false; // State untuk expanded/collapsed upcoming tasks
  final int _upcomingPreviewLimit = 5; // Batas preview untuk upcoming tasks

  // Timer refresh utama (dapat disesuaikan frekuensinya atau dihapus jika menggunakan listener yang lebih granular)
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData(); // Panggil fungsi utama untuk memuat data

    // Mulai timer refresh (sesuaikan frekuensi sesuai kebutuhan)
    // Jika Anda menggunakan listener onChildAdded/Changed/Removed di AdminMapScreen,
    // maka timer di sini mungkin bisa lebih jarang atau dihapus jika tidak ada kebutuhan sinkronisasi lain.
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _loadUserData();
      // Tampilkan notifikasi refresh jika perlu
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Memperbarui data...',
              style: mediumTextStyle(color: Colors.white),
            ),
            backgroundColor: kbpBlue800,
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _taskSubscription?.cancel();
    super.dispose();
  }

  // Helper untuk setState yang aman
  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // --- Fungsi Utama Memuat Data Pengguna dan Tugas ---
  Future<void> _loadUserData() async {
    if (!mounted) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      _currentUser = authState.user;

      if (_currentUser!.role == 'patrol') {
        // Untuk pengguna dengan role 'patrol', load tugas berdasarkan cluster mereka
        await _loadClusterOfficerTasks(
            refresh: true); // Memuat ulang semua data dan mereset paginasi
        if (!mounted) return;
        await _checkForExpiredTasks();
      } else {
        // Untuk pengguna dengan role 'commandCenter' (jika HomeScreen juga menampilkan data mereka)
        // Saat ini, HomeScreen lebih fokus ke role 'patrol'. Jika commandCenter mengakses ini,
        // perlu adaptasi atau redireksi ke AdminDashboardScreen.
        // Untuk contoh ini, saya asumsikan commandCenter akan menggunakan AdminDashboardScreen.
        // Jika perlu, implementasi serupa untuk commandCenter di sini.

        // Memastikan patrol_bloc memiliki current task dan finished tasks dari stream
        context.read<PatrolBloc>().add(LoadRouteData(userId: _currentUser!.id));

        // Memeriksa tugas yang sudah expired (ini bisa dipindahkan ke cron job atau Cloud Function)
        final currentTask = await context
            .read<PatrolBloc>()
            .repository
            .getCurrentTask(_currentUser!.id);
        if (currentTask != null) {
          final now = DateTime.now();
          if (currentTask.status == 'active' &&
              currentTask.assignedEndTime != null &&
              now.isAfter(currentTask.assignedEndTime!) &&
              currentTask.startTime == null) {
            await _markTaskAsExpired(currentTask);
          }
        }
      }
    } catch (e, stack) {
      log('Error in _loadUserData: $e\n$stack');
    } finally {
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }

  // --- REKOMENDASI UTAMA: Fungsi untuk Memuat Tugas Cluster/Officer dengan Paginasi ---
  // Parameter `loadMore` digunakan untuk menentukan apakah akan menambahkan data ke daftar yang sudah ada.
  // Parameter `statusFilter` digunakan untuk memfilter status tugas.
  // Parameter `lastKey` digunakan untuk mengambil data selanjutnya dalam paginasi.
  Future<void> _loadClusterOfficerTasks({
    bool refresh = false, // Menentukan apakah ini refresh total atau loadMore
    String? statusFilter, // Filter opsional berdasarkan status tugas
    bool loadMore = false, // Menentukan apakah ini permintaan "load more"
  }) async {
    if (!mounted || _currentUser == null) return;

    final clusterId = _currentUser!.id;

    if (refresh) {
      _resetPaginationData(); // Reset semua data paginasi saat refresh total
      _safeSetState(() {
        _isLoading = true; // Tampilkan loading overlay untuk refresh total
      });
    } else if (loadMore) {
      // Set status loading spesifik untuk loadMore
      if (statusFilter == 'ongoing')
        _safeSetState(() => _isLoadingMoreOngoing = true);
      else if (statusFilter == 'active')
        _safeSetState(() => _isLoadingMoreUpcoming = true);
      else if (statusFilter == 'finished')
        _safeSetState(() => _isLoadingMoreHistory = true);
    } else {
      _safeSetState(() {
        _isLoading =
            true; // Tampilkan loading overlay jika bukan refresh atau loadMore
      });
    }

    try {
      // Ambil data officer (biasanya tidak banyak berubah dan tidak perlu paginasi)
      final officerSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users/$clusterId/officers')
          .get();
      Map<String, Map<String, String>> officerInfo = {};
      if (officerSnapshot.exists) {
        if (officerSnapshot.value is List) {
          final officersList = List.from(
              (officerSnapshot.value as List).where((item) => item != null));
          for (var officer in officersList) {
            if (officer is Map) {
              final offId = officer['id']?.toString();
              if (offId != null && offId.isNotEmpty) {
                officerInfo[offId] = {
                  'name': officer['name']?.toString() ?? 'Unknown',
                  'photo_url': officer['photo_url']?.toString() ?? '',
                };
              }
            }
          }
        } else if (officerSnapshot.value is Map) {
          final officersData = officerSnapshot.value as Map<dynamic, dynamic>;
          officersData.forEach((offId, offData) {
            if (offData is Map) {
              final idKey = offData['id']?.toString() ?? offId.toString();
              officerInfo[idKey] = {
                'name': offData['name']?.toString() ?? 'Unknown',
                'photo_url': offData['photo_url']?.toString() ?? '',
              };
            }
          });
        }
      }

      // Ambil tasks yang ongoing (aktif saat ini)
      if (statusFilter == null || statusFilter == 'ongoing') {
        final List<PatrolTask> newOngoingTasks =
            await context.read<PatrolBloc>().repository.getClusterTasks(
                  clusterId,
                  status: 'ongoing',
                  limit: _ongoingItemsPerPage,
                  lastKey: loadMore
                      ? _ongoingLastKey
                      : null, // Gunakan lastKey untuk loadMore
                );
        _ongoingLastKey =
            newOngoingTasks.isNotEmpty ? newOngoingTasks.last.taskId : null;

        // Tambahkan ke _allOngoingTasks
        if (loadMore) {
          _allOngoingTasks.addAll(newOngoingTasks);
        } else {
          _allOngoingTasks = newOngoingTasks; // Ganti jika bukan loadMore
        }
      }

      // Ambil tasks yang active (mendatang/dijadwalkan)
      if (statusFilter == null || statusFilter == 'active') {
        final List<PatrolTask> newUpcomingTasks =
            await context.read<PatrolBloc>().repository.getClusterTasks(
                  clusterId,
                  status: 'active',
                  limit: _upcomingItemsPerPage,
                  lastKey: loadMore
                      ? _upcomingLastKey
                      : null, // Gunakan lastKey untuk loadMore
                );
        _upcomingLastKey =
            newUpcomingTasks.isNotEmpty ? newUpcomingTasks.last.taskId : null;

        // Tambahkan ke _allUpcomingTasks
        if (loadMore) {
          _allUpcomingTasks.addAll(newUpcomingTasks);
        } else {
          _allUpcomingTasks = newUpcomingTasks; // Ganti jika bukan loadMore
        }
      }

      // Ambil tasks yang finished (riwayat)
      if (statusFilter == null || statusFilter == 'finished') {
        final List<PatrolTask> newHistoryTasks =
            await context.read<PatrolBloc>().repository.getClusterTasks(
                  clusterId,
                  status: 'finished',
                  limit: _historyItemsPerPage,
                  lastKey: loadMore
                      ? _historyLastKey
                      : null, // Gunakan lastKey untuk loadMore
                );
        _historyLastKey =
            newHistoryTasks.isNotEmpty ? newHistoryTasks.last.taskId : null;

        // Tambahkan ke _allHistoryTasks
        if (loadMore) {
          _allHistoryTasks.addAll(newHistoryTasks);
        } else {
          _allHistoryTasks = newHistoryTasks; // Ganti jika bukan loadMore
        }
      }

      // Populate officer info after all tasks are loaded
      for (var taskList in [
        _allOngoingTasks,
        _allUpcomingTasks,
        _allHistoryTasks
      ]) {
        for (var task in taskList) {
          final userId = task.userId;
          if (officerInfo.containsKey(userId)) {
            task.officerName = officerInfo[userId]!['name'].toString();
            task.officerPhotoUrl = officerInfo[userId]!['photo_url'].toString();
          }
        }
      }

      // Sort tasks after populating officer info
      _allOngoingTasks.sort((a, b) => (b.startTime ?? DateTime.now())
          .compareTo(a.startTime ?? DateTime.now()));
      _allUpcomingTasks.sort((a, b) => (a.assignedStartTime ?? DateTime.now())
          .compareTo(b.assignedStartTime ?? DateTime.now()));
      _allHistoryTasks.sort((a, b) =>
          (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()));

      _safeSetState(() {
        // Inisialisasi/perbarui displayed tasks (menggunakan paginasi dari _allTasks)
        _initializeOngoingPagination(_allOngoingTasks);
        _initializeUpcomingPagination(_allUpcomingTasks);
        _initializeHistoryPagination(_allHistoryTasks);

        _isLoading = false;
        // Nonaktifkan loading spesifik untuk loadMore
        _isLoadingMoreOngoing = false;
        _isLoadingMoreUpcoming = false;
        _isLoadingMoreHistory = false;
      });

      log('Loaded total: ${_allOngoingTasks.length} ongoing, ${_allUpcomingTasks.length} upcoming, ${_allHistoryTasks.length} history');
    } catch (e, stack) {
      log('Error in _loadClusterOfficerTasks: $e\n$stack');
      _safeSetState(() {
        _isLoading = false;
        _isLoadingMoreOngoing = false;
        _isLoadingMoreUpcoming = false;
        _isLoadingMoreHistory = false;
      });
    }
  }

  // --- Fungsi untuk Mereset Data Paginasi ---
  void _resetPaginationData() {
    _allUpcomingTasks.clear();
    _displayedUpcomingTasks.clear();
    _upcomingCurrentPage = 0;
    _hasMoreUpcomingTasks = false;
    _isLoadingMoreUpcoming = false;
    _upcomingLastKey = null; // Reset lastKey
    _isUpcomingExpanded = false;

    _allOngoingTasks.clear();
    _displayedOngoingTasks.clear();
    _ongoingCurrentPage = 0;
    _hasMoreOngoingTasks = false;
    _ongoingLastKey = null; // Reset lastKey

    _allHistoryTasks.clear();
    _displayedHistoryTasks.clear();
    _historyCurrentPage = 0;
    _hasMoreHistoryTasks = false;
    _historyLastKey = null; // Reset lastKey
  }

  // --- Fungsi Load More Upcoming Tasks ---
  void _loadMoreUpcomingTasks() async {
    if (_isLoadingMoreUpcoming || !_hasMoreUpcomingTasks) return;

    _safeSetState(() {
      _isLoadingMoreUpcoming = true;
    });

    // Panggil fungsi utama untuk memuat data dengan parameter loadMore
    await _loadClusterOfficerTasks(
      loadMore: true,
      statusFilter: 'active', // Hanya memuat tasks dengan status 'active'
    );

    _safeSetState(() {
      _isLoadingMoreUpcoming = false;
      // Perbarui status _hasMoreUpcomingTasks berdasarkan jumlah data yang baru dimuat
      _hasMoreUpcomingTasks =
          _allUpcomingTasks.length % _upcomingItemsPerPage == 0 &&
              _allUpcomingTasks.isNotEmpty;
    });
  }

  // --- Fungsi Load More Ongoing Tasks ---
  void _loadMoreOngoingTasks() async {
    if (_isLoadingMoreOngoing || !_hasMoreOngoingTasks) return;

    _safeSetState(() {
      _isLoadingMoreOngoing = true;
    });

    // Panggil fungsi utama untuk memuat data dengan parameter loadMore
    await _loadClusterOfficerTasks(
      loadMore: true,
      statusFilter: 'ongoing', // Hanya memuat tasks dengan status 'ongoing'
    );

    _safeSetState(() {
      _isLoadingMoreOngoing = false;
      _hasMoreOngoingTasks =
          _allOngoingTasks.length % _ongoingItemsPerPage == 0 &&
              _allOngoingTasks.isNotEmpty;
    });
  }

  // --- Fungsi Load More History Tasks ---
  void _loadMoreHistoryTasks() async {
    if (_isLoadingMoreHistory || !_hasMoreHistoryTasks) return;

    _safeSetState(() {
      _isLoadingMoreHistory = true;
    });

    // Panggil fungsi utama untuk memuat data dengan parameter loadMore
    await _loadClusterOfficerTasks(
      loadMore: true,
      statusFilter: 'finished', // Hanya memuat tasks dengan status 'finished'
    );

    _safeSetState(() {
      _isLoadingMoreHistory = false;
      _hasMoreHistoryTasks =
          _allHistoryTasks.length % _historyItemsPerPage == 0 &&
              _allHistoryTasks.isNotEmpty;
    });
  }

  // --- Inisialisasi Paginasi untuk Tugas yang Sedang Berlangsung ---
  void _initializeOngoingPagination(List<PatrolTask> allTasks) {
    _allOngoingTasks = List.from(allTasks);
    _displayedOngoingTasks =
        _allOngoingTasks.take(_ongoingItemsPerPage).toList();
    _ongoingCurrentPage = 0;
    _hasMoreOngoingTasks = _allOngoingTasks.length > _ongoingItemsPerPage;
    _isLoadingMoreOngoing = false;
  }

  // --- Inisialisasi Paginasi untuk Tugas Mendatang ---
  void _initializeUpcomingPagination(List<PatrolTask> allTasks) {
    // Sort berdasarkan assignedStartTime yang paling dekat dengan waktu sekarang
    final now = DateTime.now();
    allTasks.sort((a, b) {
      final aTime = a.assignedStartTime ??
          DateTime(2099, 12, 31); // Default jauh di masa depan
      final bTime = b.assignedStartTime ?? DateTime(2099, 12, 31);

      // Prioritas: tugas yang siap dimulai (dalam ±10 menit), lalu yang terdekat ke depan
      final aCanStart = aTime.difference(now).inMinutes <= 10 &&
          aTime.difference(now).inMinutes >= -5;
      final bCanStart = bTime.difference(now).inMinutes <= 10 &&
          bTime.difference(now).inMinutes >= -5;

      if (aCanStart && !bCanStart) return -1;
      if (!aCanStart && bCanStart) return 1;

      return aTime.compareTo(bTime);
    });

    _allUpcomingTasks = List.from(allTasks);
    _displayedUpcomingTasks = _allUpcomingTasks
        .take(
            _isUpcomingExpanded ? _upcomingItemsPerPage : _upcomingPreviewLimit)
        .toList();
    _upcomingCurrentPage = 0;
    _hasMoreUpcomingTasks =
        _allUpcomingTasks.length > _displayedUpcomingTasks.length;
    _isLoadingMoreUpcoming = false;
  }

  // --- Inisialisasi Paginasi untuk Riwayat Tugas ---
  void _initializeHistoryPagination(List<PatrolTask> allTasks) {
    _allHistoryTasks = List.from(allTasks);
    _displayedHistoryTasks =
        _allHistoryTasks.take(_historyItemsPerPage).toList();
    _historyCurrentPage = 0;
    _hasMoreHistoryTasks = _allHistoryTasks.length > _historyItemsPerPage;
    _isLoadingMoreHistory = false;
  }

  // --- Fungsi untuk Memeriksa Tugas yang Sudah Expired ---
  Future<void> _checkForExpiredTasks() async {
    if (!mounted || _currentUser?.role != 'patrol') return;

    final now = DateTime.now();
    List<PatrolTask> expiredTasks = [];

    // Loop melalui semua tugas mendatang untuk mencari yang sudah expired
    for (final task in _allUpcomingTasks) {
      if (task.status == 'active' &&
          task.assignedEndTime != null &&
          now.isAfter(task.assignedEndTime!) &&
          task.startTime == null) {
        expiredTasks.add(task);

        // Update status di database
        try {
          if (!mounted) return;
          await context.read<PatrolBloc>().repository.updateTask(
            task.taskId,
            {
              'status': 'expired',
              'expiredAt': now.toIso8601String(),
            },
          );
          // Kirim notifikasi ke command center
          await sendPushNotificationToCommandCenter(
            title: 'Petugas Tidak Melakukan Patroli',
            body:
                'Petugas ${task.officerName} telah melewati batas waktu tugas',
          );
        } catch (e) {
          log('Error updating expired task: $e');
        }
      }
    }

    // Refresh task list jika ada yang expired
    if (expiredTasks.isNotEmpty && mounted) {
      await _loadClusterOfficerTasks(refresh: true);
    }
  }

  // --- Fungsi untuk Menandai Tugas sebagai Expired ---
  Future<void> _markTaskAsExpired(PatrolTask task) async {
    if (!mounted) return;

    final now = DateTime.now();

    try {
      await context.read<PatrolBloc>().repository.updateTask(
        task.taskId,
        {
          'status': 'expired',
          'expiredAt': now.toIso8601String(),
        },
      );

      if (!mounted) return;

      final updatedTask = task.copyWith(status: 'expired');
      context.read<PatrolBloc>().add(UpdateCurrentTask(task: updatedTask));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tugas patroli telah melewati batas waktu dan tidak dapat dimulai',
              style: mediumTextStyle(color: Colors.white),
            ),
            backgroundColor: dangerR500,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      log('Error marking task as expired: $e');
    }
  }

  // --- Widget Build Utama ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutral200,
      appBar: AppBar(
        title: Text(
          'Patrol Dashboard',
          style: semiBoldTextStyle(size: 18, color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        automaticallyImplyLeading: false,
        centerTitle: true,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: neutralWhite),
            onPressed: () {
              _loadUserData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Memperbarui data...',
                      style: mediumTextStyle(color: Colors.white),
                    ),
                    backgroundColor: kbpBlue800,
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadUserData();
        },
        color: kbpBlue900,
        child: _isLoading
            ? Center(
                child: lottie.LottieBuilder.asset(
                  'assets/lottie/maps_loading.json',
                  width: 200,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUserGreetingCard(),
                    const SizedBox(height: 24),

                    // Ongoing patrols section - hanya tampil jika ada ongoing tasks
                    if (_currentUser?.role == 'patrol' &&
                        _displayedOngoingTasks.isNotEmpty) ...[
                      _buildSectionHeader(
                        icon: Icons.play_circle,
                        title: 'Patroli Sedang Berlangsung',
                        color: successG500,
                      ),
                      const SizedBox(height: 12),
                      _buildOngoingPatrolsContent(),
                      const SizedBox(height: 24),
                    ],

                    _buildSectionHeader(
                      icon: Icons.access_time,
                      title: 'Patroli Mendatang',
                    ),
                    const SizedBox(height: 12),
                    _currentUser?.role == 'patrol'
                        ? _buildUpcomingPatrolsContent()
                        : _buildUpcomingPatrolsForOfficer(), // Mungkin perlu disesuaikan jika commandCenter punya tugas mendatang
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      icon: Icons.history,
                      title: 'Riwayat Patroli',
                    ),
                    const SizedBox(height: 12),
                    _currentUser?.role == 'patrol'
                        ? _buildHistoryContent()
                        : _buildPatrolHistoryForOfficer(), // Sama seperti di atas
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  // --- Helper Widgets (tetap seperti yang sudah ada, dengan sedikit penyesuaian untuk paginasi) ---

  Widget _buildSectionHeader(
      {required IconData icon, required String title, Color? color}) {
    final iconColor = color ?? kbpBlue900;
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: semiBoldTextStyle(size: 18, color: iconColor),
        ),
      ],
    );
  }

  Widget _buildUserGreetingCard() {
    final now = DateTime.now();
    String greeting;

    if (now.hour < 12) {
      greeting = 'Selamat Pagi';
    } else if (now.hour < 17) {
      greeting = 'Selamat Siang';
    } else if (now.hour < 20) {
      greeting = 'Selamat Sore';
    } else {
      greeting = 'Selamat Malam';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: kbpBlue50,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: kbpBlue900,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _currentUser?.role == 'patrol' ? Icons.group : Icons.person,
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
                    greeting,
                    style: regularTextStyle(size: 14, color: kbpBlue800),
                  ),
                  Text(
                    _currentUser?.name ?? 'User',
                    style: semiBoldTextStyle(size: 18, color: kbpBlue900),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _currentUser?.role == 'patrol'
                        ? 'Petugas Patroli'
                        : 'Command Center',
                    style: regularTextStyle(size: 14, color: kbpBlue700),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${now.day}/${now.month}/${now.year}',
                    style: mediumTextStyle(size: 14, color: kbpBlue900),
                  ),
                  Text(
                    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                    style: boldTextStyle(size: 16, color: kbpBlue900),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard({required String icon, required String message}) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: neutral400, width: 1),
        ),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                icon,
                height: 80,
                width: 80,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: mediumTextStyle(size: 14, color: neutral700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingPatrolsContent() {
    if (_displayedUpcomingTasks.isEmpty &&
        !_isLoadingMoreUpcoming &&
        _allUpcomingTasks.isEmpty) {
      return _buildEmptyStateCard(
        icon: 'assets/state/noTask.svg',
        message: 'Belum ada tugas patroli\nyang dijadwalkan',
      );
    }

    return Column(
      children: [
        if (_displayedUpcomingTasks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: kbpBlue50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kbpBlue200),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 14, color: kbpBlue600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isUpcomingExpanded
                        ? 'Menampilkan ${_displayedUpcomingTasks.length} dari ${_allUpcomingTasks.length} tugas mendatang'
                        : 'Menampilkan ${_displayedUpcomingTasks.length} tugas terdekat dari ${_allUpcomingTasks.length} total',
                    style: mediumTextStyle(size: 12, color: kbpBlue700),
                  ),
                ),
                if (!_isUpcomingExpanded &&
                    _allUpcomingTasks.length > _upcomingPreviewLimit)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '+${_allUpcomingTasks.length - _upcomingPreviewLimit}',
                      style: boldTextStyle(size: 10, color: kbpBlue700),
                    ),
                  ),
              ],
            ),
          ),
        _buildPriorityTasksIndicator(DateTime.now()),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kbpBlue200, width: 1),
          ),
          color: Colors.white,
          child: Column(
            children: [
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _displayedUpcomingTasks.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: kbpBlue100),
                itemBuilder: (context, index) {
                  final task = _displayedUpcomingTasks[index];
                  final isUrgent = _isTaskUrgent(task, DateTime.now());
                  return _buildUpcomingTaskItem(task, index, isUrgent);
                },
              ),
              if (_isUpcomingExpanded &&
                  (_hasMoreUpcomingTasks || _isLoadingMoreUpcoming)) ...[
                const Divider(height: 1, color: kbpBlue200),
                if (_isLoadingMoreUpcoming)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kbpBlue600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Memuat tugas lainnya...',
                          style: mediumTextStyle(size: 14, color: kbpBlue600),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loadMoreUpcomingTasks,
                        icon: const Icon(Icons.expand_more, size: 16),
                        label: Text('Muat ${_upcomingItemsPerPage} Tugas Lagi'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kbpBlue700,
                          side: BorderSide(color: kbpBlue300, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                        ),
                      ),
                    ),
                  ),
              ],
              if (_allUpcomingTasks.length > _upcomingPreviewLimit ||
                  _isUpcomingExpanded) ...[
                if (!_isUpcomingExpanded || !_hasMoreUpcomingTasks)
                  const Divider(height: 1, color: kbpBlue200),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _toggleUpcomingExpanded,
                      icon: AnimatedRotation(
                        turns: _isUpcomingExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down, size: 18),
                      ),
                      label: Text(
                        _isUpcomingExpanded
                            ? 'Tampilkan Lebih Sedikit'
                            : 'Lihat Semua ${_allUpcomingTasks.length} Tugas',
                        style: mediumTextStyle(size: 14, color: kbpBlue700),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: kbpBlue700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriorityTasksIndicator(DateTime now) {
    final urgentTasks = _displayedUpcomingTasks
        .where((task) => _isTaskUrgent(task, now))
        .length;

    if (urgentTasks == 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: warningY50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warningY300),
      ),
      child: Row(
        children: [
          Icon(Icons.priority_high, size: 16, color: warningY400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$urgentTasks tugas siap dimulai (dalam 10 menit ke depan)',
              style: semiBoldTextStyle(size: 12, color: warningY500),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: warningY400,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$urgentTasks',
              style: boldTextStyle(size: 10, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  bool _isTaskUrgent(PatrolTask task, DateTime now) {
    if (task.assignedStartTime == null) return false;
    final timeDifference = task.assignedStartTime!.difference(now);
    return timeDifference.inMinutes <= 10 && timeDifference.inMinutes >= -5;
  }

  Widget _buildUpcomingTaskItem(PatrolTask task, int index, bool isUrgent) {
    final now = DateTime.now();
    final canStart = task.assignedStartTime != null &&
        task.assignedStartTime!.difference(now).inMinutes <= 10;

    return Container(
      decoration: BoxDecoration(
        color: isUrgent ? warningY50.withOpacity(0.3) : Colors.transparent,
        borderRadius: index == 0 && index == _displayedUpcomingTasks.length - 1
            ? BorderRadius.circular(12)
            : index == 0
                ? const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  )
                : index == _displayedUpcomingTasks.length - 1
                    ? const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      )
                    : BorderRadius.zero,
      ),
      child: InkWell(
        onTap: () => _showTaskDialog(task),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isUrgent ? warningY400 : kbpBlue300,
                        width: isUrgent ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: task.officerPhotoUrl.isNotEmpty
                          ? Image.network(
                              task.officerPhotoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Text(
                                    task.officerName
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: semiBoldTextStyle(
                                        size: 16, color: kbpBlue900),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                task.officerName.substring(0, 1).toUpperCase(),
                                style: semiBoldTextStyle(
                                    size: 16, color: kbpBlue900),
                              ),
                            ),
                    ),
                  ),
                  if (isUrgent)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: warningY500,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.priority_high,
                          size: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.officerName,
                            style: semiBoldTextStyle(
                              size: 15,
                              color: isUrgent ? warningY500 : kbpBlue900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.place,
                          size: 14,
                          color: isUrgent ? warningY400 : kbpBlue600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "${task.assignedRoute?.length ?? 0} titik patroli",
                          style: regularTextStyle(
                            size: 12,
                            color: isUrgent ? warningY500 : kbpBlue700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: canStart ? successG500 : kbpBlue600,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            canStart ? 'Siap Dimulai' : 'Terjadwal',
                            style: boldTextStyle(size: 10, color: Colors.white),
                          ),
                        ),
                        if (isUrgent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: warningY500,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'PRIORITAS',
                              style:
                                  boldTextStyle(size: 10, color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isUrgent ? warningY100 : kbpBlue50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isUrgent ? warningY300 : kbpBlue200,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          task.assignedStartTime != null
                              ? formatDateFromString(
                                  task.assignedStartTime.toString())
                              : 'N/A',
                          style: mediumTextStyle(
                            size: 10,
                            color: isUrgent ? warningY500 : kbpBlue700,
                          ),
                        ),
                        Text(
                          task.assignedStartTime != null
                              ? formatTimeFromString(
                                  task.assignedStartTime.toString())
                              : 'N/A',
                          style: boldTextStyle(
                            size: 12,
                            color: isUrgent ? warningY500 : kbpBlue900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 80,
                    height: 32,
                    child: ElevatedButton(
                      onPressed: () => _showTaskDialog(task),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canStart ? successG500 : kbpBlue900,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        canStart ? 'Mulai' : 'Detail',
                        style: mediumTextStyle(size: 11, color: Colors.white),
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

  String _getTimeUntilStart(PatrolTask task, DateTime now) {
    if (task.assignedStartTime == null) return 'Waktu tidak tersedia';

    final difference = task.assignedStartTime!.difference(now);

    if (difference.inMinutes <= 0) {
      return 'Sekarang';
    } else if (difference.inMinutes <= 60) {
      return '${difference.inMinutes} menit lagi';
    } else if (difference.inHours <= 24) {
      return '${difference.inHours} jam lagi';
    } else {
      return '${difference.inDays} hari lagi';
    }
  }

  void _toggleUpcomingExpanded() {
    _safeSetState(() {
      _isUpcomingExpanded = !_isUpcomingExpanded;

      if (_isUpcomingExpanded) {
        _displayedUpcomingTasks = _allUpcomingTasks;
      } else {
        _displayedUpcomingTasks =
            _allUpcomingTasks.take(_upcomingPreviewLimit).toList();
      }
      _hasMoreUpcomingTasks =
          _displayedUpcomingTasks.length < _allUpcomingTasks.length;
    });
  }

  Widget _buildOngoingPatrolsContent() {
    if (_displayedOngoingTasks.isEmpty && !_isLoadingMoreOngoing) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (_displayedOngoingTasks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: successG50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: successG200),
            ),
            child: Row(
              children: [
                Icon(Icons.play_circle, size: 14, color: successG400),
                const SizedBox(width: 8),
                Text(
                  'Tolong selesaikan tugas patroli ini terlebih dahulu',
                  style: mediumTextStyle(size: 12, color: successG500),
                ),
                if (_hasMoreOngoingTasks) ...[
                  const Spacer(),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: successG400),
                ],
              ],
            ),
          ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount:
              _displayedOngoingTasks.length + (_hasMoreOngoingTasks ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _displayedOngoingTasks.length) {
              return _isLoadingMoreOngoing
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: successG400,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Memuat patroli lainnya...',
                            style:
                                mediumTextStyle(size: 14, color: successG400),
                          ),
                        ],
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loadMoreOngoingTasks,
                        icon: const Icon(Icons.expand_more, size: 18),
                        label:
                            Text('Lihat ${_ongoingItemsPerPage} Patroli Lagi'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: successG500,
                          side: BorderSide(color: successG400, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    );
            }
            final task = _displayedOngoingTasks[index];
            return _buildOngoingTaskItem(task);
          },
        ),
      ],
    );
  }

  Widget _buildOngoingTaskItem(PatrolTask task) {
    final startTime = task.startTime ?? DateTime.now();
    final currentTime = DateTime.now();
    final elapsedDuration = currentTime.difference(startTime);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: successG200),
        boxShadow: [
          BoxShadow(
            color: successG100.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [successG400, successG400],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.navigation,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: successG500,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'LIVE',
                            style: boldTextStyle(size: 10, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Patroli sedang berlangsung',
                            style:
                                semiBoldTextStyle(size: 14, color: successG500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.place, size: 14, color: successG400),
                        const SizedBox(width: 4),
                        Text(
                          "${task.assignedRoute?.length ?? 0} Titik Patroli",
                          style: regularTextStyle(size: 12, color: successG500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.timer, size: 14, color: successG400),
                        const SizedBox(width: 4),
                        Text(
                          'Berlangsung ${_formatDuration(elapsedDuration)}',
                          style: regularTextStyle(size: 12, color: successG500),
                        ),
                      ],
                    ),
                    if (task.distance != null && task.distance! > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.straighten,
                              size: 14, color: successG400),
                          const SizedBox(width: 4),
                          Text(
                            'Jarak: ${(task.distance! / 1000).toStringAsFixed(2)} km',
                            style:
                                regularTextStyle(size: 12, color: successG500),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: successG100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      formatDateFromString(startTime.toString()),
                      style: mediumTextStyle(size: 10, color: successG500),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatTimeFromString(startTime.toString()),
                    style: semiBoldTextStyle(size: 12, color: successG500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dimulai',
                    style: regularTextStyle(size: 10, color: successG400),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapScreen(
                          task: task,
                          onStart: () {
                            // Task already started
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map, size: 16),
                  label: Text(
                    'Lanjutkan Patroli',
                    style: mediumTextStyle(size: 12, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: successG400,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showTaskDialog(task),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: Text(
                    'Detail',
                    style: mediumTextStyle(size: 12, color: successG500),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: successG500,
                    side: BorderSide(color: successG400, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status, {DateTime? assignedStartTime}) {
    if (status.toLowerCase() == 'active' && assignedStartTime != null) {
      final now = DateTime.now();
      final timeDifference = assignedStartTime.difference(now);
      if (timeDifference.inMinutes > 10) {
        return 'Belum dimulai';
      }
    }
    switch (status.toLowerCase()) {
      case 'active':
        return 'Aktif';
      case 'ongoing':
      case 'in_progress':
        return 'Sedang Berjalan';
      case 'finished':
        return 'Selesai';
      case 'expired':
        return 'Tidak Dilaksanakan';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status, {DateTime? assignedStartTime}) {
    if (status.toLowerCase() == 'active' && assignedStartTime != null) {
      final now = DateTime.now();
      final timeDifference = assignedStartTime.difference(now);
      if (timeDifference.inMinutes > 10) {
        return neutral500;
      }
    }
    switch (status.toLowerCase()) {
      case 'active':
        return kbpBlue700;
      case 'ongoing':
      case 'in_progress':
        return successG500;
      case 'finished':
        return neutral700;
      case 'expired':
        return dangerR500;
      default:
        return kbpBlue700;
    }
  }

  Color _getTimelinessColor(String? timeliness) {
    switch (timeliness?.toLowerCase()) {
      case 'ontime':
        return successG500;
      case 'late':
        return warningY500;
      case 'pastdue':
        return dangerR500;
      default:
        return neutral500;
    }
  }

  String _getTimelinessText(String? timeliness) {
    switch (timeliness?.toLowerCase()) {
      case 'ontime':
        return 'Tepat Waktu';
      case 'late':
        return timeliness!;
      case 'pastdue':
        return 'Melewati Batas';
      default:
        return 'Belum Dimulai';
    }
  }

  Widget _buildHistoryContent() {
    if (_displayedHistoryTasks.isEmpty &&
        !_isLoadingMoreHistory &&
        _allHistoryTasks.isEmpty) {
      return _buildEmptyStateCard(
        icon: 'assets/nodata.svg',
        message: 'Belum ada riwayat patroli',
      );
    }

    return Column(
      children: [
        if (_displayedHistoryTasks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: successG50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: successG200),
            ),
            child: Row(
              children: [
                Icon(Icons.history, size: 14, color: successG300),
                const SizedBox(width: 8),
                Text(
                  'Menampilkan ${_displayedHistoryTasks.length} dari ${_allHistoryTasks.length} riwayat',
                  style: mediumTextStyle(size: 12, color: successG400),
                ),
                if (_hasMoreHistoryTasks) ...[
                  const Spacer(),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: successG500),
                ],
              ],
            ),
          ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kbpBlue200, width: 1),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _displayedHistoryTasks.length +
                      (_hasMoreHistoryTasks ? 1 : 0),
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: kbpBlue200),
                  itemBuilder: (context, index) {
                    if (index == _displayedHistoryTasks.length) {
                      return _isLoadingMoreHistory
                          ? Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: kbpBlue600,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Memuat riwayat lainnya...',
                                    style: mediumTextStyle(
                                        size: 14, color: kbpBlue600),
                                  ),
                                ],
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _loadMoreHistoryTasks,
                                  icon: const Icon(Icons.expand_more, size: 16),
                                  label: Text(
                                      'Lihat ${_historyItemsPerPage} Riwayat Lagi'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: successG500,
                                    side: BorderSide(
                                        color: successG300, width: 1.5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                  ),
                                ),
                              ),
                            );
                    }
                    final task = _displayedHistoryTasks[index];
                    return _buildHistoryItem(task);
                  },
                ),
                if (_allHistoryTasks.length > _displayedHistoryTasks.length &&
                    !_hasMoreHistoryTasks &&
                    !_isLoadingMoreHistory)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PatrolHistoryListScreen(
                              tasksList: _allHistoryTasks,
                              isClusterView: _currentUser?.role == 'patrol',
                            ),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Lihat Semua Riwayat',
                            style: mediumTextStyle(color: kbpBlue900),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward,
                              size: 16, color: kbpBlue900),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarFallback(PatrolTask task) {
    return Center(
      child: Text(
        task.officerName.substring(0, 1).toUpperCase(),
        style: semiBoldTextStyle(size: 16, color: kbpBlue900),
      ),
    );
  }

  Widget _buildHistoryItem(PatrolTask task) {
    final duration = task.endTime != null && task.startTime != null
        ? task.endTime!.difference(task.startTime!)
        : Duration.zero;

    return SizedBox(
      height: 90,
      child: InkWell(
        onTap: () => task.status.toLowerCase() == 'expired'
            ? _showExpiredTaskDetails(task)
            : _showPatrolSummary(task),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: kbpBlue100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kbpBlue200, width: 1),
                ),
                child: task.officerPhotoUrl.isNotEmpty
                    ? Image.network(
                        task.officerPhotoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildAvatarFallback(task);
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _buildAvatarFallback(task);
                        },
                      )
                    : _buildAvatarFallback(task),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.officerName,
                            style:
                                semiBoldTextStyle(size: 14, color: kbpBlue900),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    const SizedBox(height: 4),
                    task.status.toLowerCase() == 'expired'
                        ? Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 14, color: dangerR500),
                              const SizedBox(width: 4),
                              Text(
                                task.assignedStartTime != null
                                    ? formatDateFromString(
                                        task.assignedStartTime.toString())
                                    : 'Tanggal tidak tersedia',
                                style: regularTextStyle(
                                    size: 12, color: dangerR500),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.access_time,
                                  size: 14, color: dangerR500),
                              const SizedBox(width: 4),
                              Text(
                                task.assignedStartTime != null
                                    ? formatTimeFromString(
                                        task.assignedStartTime.toString())
                                    : 'Jam tidak tersedia',
                                style: regularTextStyle(
                                    size: 12, color: dangerR500),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              const Icon(Icons.timer,
                                  size: 14, color: kbpBlue700),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(duration),
                                style: regularTextStyle(size: 12),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.straighten,
                                  size: 14, color: kbpBlue700),
                              const SizedBox(width: 4),
                              Text(
                                '${((task.distance ?? 0) / 1000).toStringAsFixed(2)} km',
                                style: regularTextStyle(size: 12),
                              ),
                            ],
                          ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getStatusColor(task.status),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getStatusText(task.status),
                          style: mediumTextStyle(size: 10, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.navigate_next, color: kbpBlue900),
                  onPressed: () => task.status.toLowerCase() == 'expired'
                      ? _showExpiredTaskDetails(task)
                      : _showPatrolSummary(task),
                  tooltip: 'Lihat Detail',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                  iconSize: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTaskDialog(PatrolTask task) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TaskDetailDialog(
        task: task,
        onStart: () => _navigateToMap(task),
      ),
    );
  }

  void _navigateToMap(PatrolTask task) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          task: task,
          onStart: () {
            context.read<PatrolBloc>().add(StartPatrol(
                  task: task,
                  startTime: DateTime.now(),
                ));
          },
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours == 0 && minutes == 0) {
      return '0 Menit';
    }
    if (hours == 0) {
      return '${minutes} Menit';
    }
    if (minutes == 0) {
      return '${hours} Jam';
    }
    return '${hours} Jam ${minutes} Menit';
  }

  void _showPatrolSummary(PatrolTask task) {
    try {
      List<List<double>> convertedPath = [];

      if (task.routePath != null && task.routePath is Map) {
        final map = task.routePath as Map;
        final sortedEntries = map.entries.toList()
          ..sort((a, b) => (a.value['timestamp'] as String)
              .compareTo(b.value['timestamp'] as String));
        convertedPath = sortedEntries.map((entry) {
          final coordinates = entry.value['coordinates'] as List;
          return [
            (coordinates[0] as num).toDouble(),
            (coordinates[1] as num).toDouble(),
          ];
        }).toList();
      }

      if (convertedPath.isEmpty && task.status.toLowerCase() != 'expired') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No route data available')),
        );
        return;
      }

      _refreshTaskDataForSummary(task).then((updatedTask) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PatrolSummaryScreen(
              task: updatedTask ?? task,
              routePath: convertedPath,
              startTime:
                  updatedTask?.startTime ?? task.startTime ?? DateTime.now(),
              endTime: updatedTask?.endTime ?? task.endTime ?? DateTime.now(),
              distance: updatedTask?.distance ?? task.distance ?? 0,
              finalReportPhotoUrl:
                  updatedTask?.finalReportPhotoUrl ?? task.finalReportPhotoUrl,
              initialReportPhotoUrl: updatedTask?.initialReportPhotoUrl ??
                  task.initialReportPhotoUrl,
            ),
          ),
        );
      });
    } catch (e, stackTrace) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading patrol summary: $e')),
      );
    }
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    try {
      if (value is String) {
        if (value.contains('.')) {
          final parts = value.split('.');
          final mainPart = parts[0];
          final microPart = parts[1];
          final cleanMicroPart =
              microPart.length > 6 ? microPart.substring(0, 6) : microPart;
          return DateTime.parse('$mainPart.$cleanMicroPart');
        }
        return DateTime.parse(value);
      } else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
    } catch (e) {
      log('Error parsing datetime: $value, error: $e');
    }
    return null;
  }

  Future<PatrolTask?> _refreshTaskDataForSummary(
      PatrolTask originalTask) async {
    if (!mounted) return null;
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('tasks')
          .child(originalTask.taskId)
          .get();
      if (!mounted || !snapshot.exists) return null;

      final data = snapshot.value as Map<dynamic, dynamic>;
      final updatedTask = PatrolTask(
        taskId: originalTask.taskId,
        userId: data['userId']?.toString() ?? '',
        status: data['status']?.toString() ?? '',
        assignedStartTime: _parseDateTime(data['assignedStartTime']),
        assignedEndTime: _parseDateTime(data['assignedEndTime']),
        startTime: _parseDateTime(data['startTime']),
        endTime: _parseDateTime(data['endTime']),
        distance: data['distance'] != null
            ? (data['distance'] as num).toDouble()
            : null,
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        assignedRoute: data['assigned_route'] != null
            ? (data['assigned_route'] as List)
                .map((point) => (point as List)
                    .map((coord) => (coord as num).toDouble())
                    .toList())
                .toList()
            : null,
        routePath: data['route_path'] != null
            ? Map<String, dynamic>.from(data['route_path'] as Map)
            : null,
        clusterId: data['clusterId']?.toString() ?? '',
        mockLocationDetected: data['mockLocationDetected'] ?? false,
        mockLocationCount: data['mockLocationCount'] is num
            ? (data['mockLocationCount'] as num).toInt()
            : 0,
        initialReportPhotoUrl: data['initialReportPhotoUrl']?.toString(),
        initialReportNote: data['initialReportNote']?.toString(),
        initialReportTime: _parseDateTime(data['initialReportTime']),
        finalReportPhotoUrl: data['finalReportPhotoUrl']?.toString(),
        finalReportNote: data['finalReportNote']?.toString(),
        finalReportTime: _parseDateTime(data['finalReportTime']),
        timeliness: data['timeliness']?.toString(),
      );
      updatedTask.officerName = originalTask.officerName;
      updatedTask.officerPhotoUrl = originalTask.officerPhotoUrl;
      return updatedTask;
    } catch (e) {
      log('Error refreshing task data: $e');
      return null;
    }
  }

  void _showExpiredTaskDetails(PatrolTask task) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: kbpBlue900,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: dangerR300, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Patroli Tidak Dilaksanakan',
                      style: semiBoldTextStyle(size: 18, color: neutralWhite),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                    'Petugas',
                    task.officerName,
                    Icons.person,
                    iconColor: kbpBlue700,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: neutral300),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    'Jadwal Patroli',
                    task.assignedStartTime != null
                        ? '${formatDateFromString(task.assignedStartTime.toString())} ${formatTimeFromString(task.assignedStartTime.toString())}'
                        : 'Tidak tersedia',
                    Icons.event,
                    iconColor: kbpBlue700,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: neutral300),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    'Batas Waktu',
                    task.assignedEndTime != null
                        ? '${formatDateFromString(task.assignedEndTime.toString())} ${formatTimeFromString(task.assignedEndTime.toString())}'
                        : 'Tidak tersedia',
                    Icons.timer_off,
                    iconColor: kbpBlue700,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: neutral300),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    'Status',
                    'Tidak Dilaksanakan',
                    Icons.highlight_off,
                    valueColor: dangerR500,
                    iconColor: dangerR500,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: neutral300),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    'Waktu Kedaluwarsa',
                    task.expiredAt != null
                        ? '${formatDateFromString(task.expiredAt.toString())} ${formatTimeFromString(task.expiredAt.toString())}'
                        : 'Tidak tercatat',
                    Icons.update,
                    valueColor: dangerR500,
                    iconColor: dangerR500,
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: neutral200,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kbpBlue900,
                      foregroundColor: neutralWhite,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Tutup',
                      style: mediumTextStyle(color: Colors.white),
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

  Widget _buildInfoRow(String label, String value, IconData icon,
      {Color? valueColor, Color? iconColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor == dangerR500) ? dangerR100 : kbpBlue100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor ?? kbpBlue700),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: regularTextStyle(size: 13, color: neutral700),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style:
                    mediumTextStyle(size: 15, color: valueColor ?? kbpBlue900),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingPatrolsForOfficer() {
    return BlocBuilder<PatrolBloc, PatrolState>(
      builder: (context, state) {
        if (state is PatrolLoading) {
          return const SizedBox(
            height: 180,
            width: double.infinity,
            child: Center(
              child: CircularProgressIndicator(color: kbpBlue900),
            ),
          );
        }

        if (state is PatrolLoaded) {
          if (state.task != null &&
              (state.task!.status == 'active' ||
                  state.task!.status == 'ongoing' ||
                  state.task!.status == 'in_progress')) {
            return _buildTaskCard(state.task!);
          }
        }

        return _buildEmptyStateCard(
          icon: 'assets/state/noTask.svg',
          message: 'Belum ada tugas patroli\nyang dijadwalkan',
        );
      },
    );
  }

  Widget _buildTaskCard(PatrolTask task) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kbpBlue200, width: 1),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.directions_car,
                      color: kbpBlue900,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person,
                                size: 16, color: kbpBlue700),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                task.officerName,
                                style: regularTextStyle(
                                    size: 14, color: kbpBlue700),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.place,
                                size: 16, color: kbpBlue700),
                            const SizedBox(width: 4),
                            Text(
                              "${task.assignedRoute?.length ?? 0} Titik Patroli",
                              style:
                                  regularTextStyle(size: 14, color: kbpBlue700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(task.status,
                                    assignedStartTime: task.assignedStartTime),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getStatusText(task.status,
                                    assignedStartTime: task.assignedStartTime),
                                style: mediumTextStyle(
                                    size: 12, color: Colors.white),
                              ),
                            ),
                            if (task.timeliness != null)
                              Row(
                                children: [
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          _getTimelinessColor(task.timeliness),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _getTimelinessText(task.timeliness),
                                      style: mediumTextStyle(
                                          size: 12, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: kbpBlue100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.assignedStartTime != null
                                ? formatDateFromString(
                                    task.assignedStartTime.toString())
                                : 'Tidak tersedia',
                            style: mediumTextStyle(size: 12, color: kbpBlue900),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.assignedStartTime != null
                              ? formatTimeFromString(
                                  task.assignedStartTime.toString())
                              : 'Tidak tersedia',
                          style: semiBoldTextStyle(size: 14, color: kbpBlue900),
                        ),
                        const Spacer(),
                        Text(
                          task.assignedStartTime != null &&
                                  task.assignedEndTime != null
                              ? getDurasiPatroli(task.assignedStartTime!,
                                  startTime: task.assignedEndTime!)
                              : 'Durasi tidak tersedia',
                          style: regularTextStyle(size: 12, color: kbpBlue700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () => _showTaskDialog(task),
                icon: const Icon(Icons.map, size: 18),
                label: Text(
                  'Lihat Detail',
                  style: semiBoldTextStyle(size: 14, color: neutralWhite),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kbpBlue900,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatrolHistoryForOfficer() {
    return BlocBuilder<PatrolBloc, PatrolState>(
      builder: (context, state) {
        if (state is PatrolLoading) {
          return const SizedBox(
            height: 180,
            width: double.infinity,
            child: Center(
              child: CircularProgressIndicator(color: kbpBlue900),
            ),
          );
        }

        if (state is PatrolLoaded) {
          if (state.finishedTasks.isEmpty) {
            return _buildEmptyStateCard(
              icon: 'assets/nodata.svg',
              message: 'Belum ada riwayat patroli',
            );
          }

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: kbpBlue200, width: 1),
            ),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.finishedTasks.length > 5
                        ? 5
                        : state.finishedTasks.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: kbpBlue200),
                    itemBuilder: (context, index) {
                      final task = state.finishedTasks[index];
                      return _buildHistoryItem(task);
                    },
                  ),
                  if (state.finishedTasks.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PatrolHistoryListScreen(
                                tasksList: state.finishedTasks,
                                isClusterView: _currentUser?.role == 'patrol',
                              ),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Lihat Semua Riwayat',
                              style: mediumTextStyle(color: kbpBlue900),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward,
                                size: 16, color: kbpBlue900),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        if (state is PatrolError) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: dangerR100,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: dangerR500),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gagal memuat riwayat',
                          style: semiBoldTextStyle(color: dangerR300),
                        ),
                        Text(
                          state.message,
                          style: regularTextStyle(size: 12, color: dangerR500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
