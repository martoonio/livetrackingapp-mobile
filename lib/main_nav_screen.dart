import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/admin_map_screen.dart';
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';
import 'package:livetrackingapp/presentation/component/customNavBar.dart';
import 'package:livetrackingapp/presentation/survey/survey_list_screen.dart';

import 'home_screen.dart';
import 'presentation/admin/admin_dashboard_screen.dart';
import 'presentation/auth/profile_screen.dart';
import 'presentation/cluster/manage_screen_cluster.dart';

class MainNavigationScreen extends StatefulWidget {
  final String userRole;
  // --- FITUR BARU: PARAMETER UNTUK HIGHLIGHT DARI NOTIFIKASI ---
  final int initialTabIndex;
  final String? highlightedTaskId;
  final double? highlightedLat;
  final double? highlightedLng;

  const MainNavigationScreen({
    Key? key,
    required this.userRole,
    this.initialTabIndex = 0,
    this.highlightedTaskId,
    this.highlightedLat,
    this.highlightedLng,
  }) : super(key: key);
  // --- AKHIR FITUR BARU ---

  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  int _previousIndex = 0;
  late final List<Widget> _pages;
  late final PageController _pageController;

  // Key untuk memaksa rebuild screens saat perlu
  final Map<int, GlobalKey> _pageKeys = {};

  // --- FITUR BARU: GLOBAL KEY UNTUK ADMIN MAP SCREEN ---
  // Gunakan GlobalKey untuk mengakses state AdminMapScreen
  final GlobalKey<AdminMapScreenState> _adminMapScreenKey = GlobalKey<AdminMapScreenState>();
  // --- AKHIR FITUR BARU ---

  @override
  void initState() {
    super.initState();

    // --- FITUR BARU: SET INITIAL INDEX DARI PARAMETER ---
    _selectedIndex = widget.initialTabIndex;
    // --- AKHIR FITUR BARU ---

    // Inisialisasi pages dengan GlobalKey unik
    if (widget.userRole == 'commandCenter') {
      // Admin user gets AdminMapScreen as the home page
      _pages = [
        // --- FITUR BARU: GUNAKAN GLOBAL KEY DAN PASS HIGHLIGHTED DATA ---
        AdminMapScreen(
          key: _adminMapScreenKey, // Gunakan global key di sini
          highlightedTaskId: widget.highlightedTaskId,
          highlightedLat: widget.highlightedLat,
          highlightedLng: widget.highlightedLng,
        ),
        // --- AKHIR FITUR BARU ---
        AdminDashboardScreen(key: _getKeyForIndex(1)),
        ManageClustersScreen(key: _getKeyForIndex(2)),
        // Tambahkan Survey List Screen disini
        SurveyListScreen(
          key: _getKeyForIndex(3),
          userId: getCurrentUserId(), // Implementasikan metode ini untuk mendapatkan user ID
          userName: getCurrentUserName(), // Implementasikan metode ini untuk mendapatkan user name
        ),
        ProfileScreen(key: _getKeyForIndex(4)),
      ];
    } else {
      // Normal users get HomeScreen and now also SurveyListScreen
      _pages = [
        HomeScreen(key: _getKeyForIndex(0)),
        // Tambahkan Survey List Screen untuk user biasa
        SurveyListScreen(
          key: _getKeyForIndex(1),
          userId: getCurrentUserId(),
          userName: getCurrentUserName(),
        ),
        ProfileScreen(key: _getKeyForIndex(2)),
      ];
    }

    // Inisialisasi PageController
    _pageController = PageController(initialPage: _selectedIndex);
  }

  // Mendapatkan user ID dari AuthBloc
  String getCurrentUserId() {
    // Implementasi aktual: mendapatkan user ID dari AuthBloc
    // Contoh implementasi sederhana:
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      return authState.user.id;
    }
    return '';
  }

  // Mendapatkan nama user dari AuthBloc
  String getCurrentUserName() {
    // Implementasi aktual: mendapatkan user name dari AuthBloc
    // Contoh implementasi sederhana:
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      return authState.user.name;
    }
    return '';
  }

  // Mendapatkan atau membuat key untuk index tertentu
  GlobalKey _getKeyForIndex(int index) {
    if (!_pageKeys.containsKey(index)) {
      _pageKeys[index] = GlobalKey();
    }
    return _pageKeys[index]!;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --- FITUR BARU: METODE PUBLIK UNTUK NAVIGASI DAN HIGHLIGHT ---
  void goToAdminMapAndHighlight(String taskId, double lat, double lng) {
    // Pastikan kita berada di mode commandCenter dan tab AdminMapScreen
    if (widget.userRole == 'commandCenter') {
      // Pindah ke tab AdminMapScreen (indeks 0)
      _pageController.jumpToPage(0);
      setState(() {
        _selectedIndex = 0;
      });

      // Panggil metode highlight di AdminMapScreenState
      _adminMapScreenKey.currentState?.highlightLocation(taskId, lat, lng);
    }
  }
  // --- AKHIR FITUR BARU ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: _pages,
        onPageChanged: (index) {
          setState(() {
            _previousIndex = _selectedIndex;
            _selectedIndex = index;
          });
        },
      ),
      bottomNavigationBar: CustomNavBar(
        items: widget.userRole == 'commandCenter'
            ? [
                const NavBarItem(
                  activeIcon: Icons.home,
                  inactiveIcon: Icons.home_outlined,
                  label: 'Home',
                ),
                const NavBarItem(
                  activeIcon: Icons.task,
                  inactiveIcon: Icons.task_outlined,
                  label: 'Penugasan',
                ),
                const NavBarItem(
                  activeIcon: Icons.location_city,
                  inactiveIcon: Icons.location_city_outlined,
                  label: 'Tatar',
                ),
                // Tambahkan NavBarItem untuk Survey
                const NavBarItem(
                  activeIcon: Icons.assessment,
                  inactiveIcon: Icons.assessment_outlined,
                  label: 'Survey',
                ),
                const NavBarItem(
                  activeIcon: Icons.person,
                  inactiveIcon: Icons.person_outline,
                  label: 'Profil',
                ),
              ]
            : [
                const NavBarItem(
                  activeIcon: Icons.home,
                  inactiveIcon: Icons.home_outlined,
                  label: 'Home',
                ),
                // Tambahkan NavBarItem untuk Survey (user biasa)
                const NavBarItem(
                  activeIcon: Icons.assessment,
                  inactiveIcon: Icons.assessment_outlined,
                  label: 'Survey',
                ),
                const NavBarItem(
                  activeIcon: Icons.person,
                  inactiveIcon: Icons.person_outline,
                  label: 'Profil',
                ),
              ],
        initialIndex: _selectedIndex,
        onItemSelected: (index) {
          // Jika tab yang sama diklik lagi, refresh halaman
          if (_selectedIndex == index) {
            _refreshCurrentPage(index);
          } else {
            // Animasi ke halaman yang diklik
            _pageController.jumpToPage(index);
          }
        },
      ),
    );
  }

  // Method untuk refresh halaman saat ini
  void _refreshCurrentPage(int index) {
    setState(() {
      // Ganti key untuk memaksa rebuild
      _pageKeys[index] = GlobalKey();

      // Rebuild halaman dengan key baru
      if (widget.userRole == 'commandCenter') {
        switch (index) {
          case 0:
            // --- FITUR BARU: PASTIKAN ADMINMAPSCREEN MENGGUNAKAN GLOBAL KEY ---
            _pages[0] = AdminMapScreen(key: _adminMapScreenKey);
            // --- AKHIR FITUR BARU ---
            break;
          case 1:
            _pages[1] = AdminDashboardScreen(key: _pageKeys[index]);
            break;
          case 2:
            _pages[2] = ManageClustersScreen(key: _pageKeys[index]);
            break;
          case 3:
            // Refresh SurveyListScreen
            _pages[3] = SurveyListScreen(
              key: _pageKeys[index],
              userId: getCurrentUserId(),
              userName: getCurrentUserName(),
            );
            break;
          case 4:
            _pages[4] = ProfileScreen(key: _pageKeys[index]);
            break;
        }
      } else {
        switch (index) {
          case 0:
            _pages[0] = HomeScreen(key: _pageKeys[index]);
            break;
          case 1:
            // Refresh SurveyListScreen untuk user biasa
            _pages[1] = SurveyListScreen(
              key: _pageKeys[index],
              userId: getCurrentUserId(),
              userName: getCurrentUserName(),
            );
            break;
          case 2:
            _pages[2] = ProfileScreen(key: _pageKeys[index]);
            break;
        }
      }
    });
  }
}
