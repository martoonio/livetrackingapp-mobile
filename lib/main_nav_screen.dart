import 'package:flutter/material.dart';
import 'package:livetrackingapp/admin_map_screen.dart';
import 'package:livetrackingapp/presentation/component/customNavBar.dart';
import 'package:livetrackingapp/presentation/survey/screens/manage_survey_screen.dart';
import 'package:livetrackingapp/presentation/survey/screens/survey_list_screen.dart';

import 'home_screen.dart';
import 'presentation/admin/admin_dashboard_screen.dart';
import 'presentation/auth/profile_screen.dart';
import 'presentation/cluster/manage_screen_cluster.dart';

class MainNavigationScreen extends StatefulWidget {
  final String userRole;
  final int initialTabIndex;
  final String? highlightedTaskId;
  final double? highlightedLat;
  final double? highlightedLng;

  const MainNavigationScreen({
    super.key,
    required this.userRole,
    this.initialTabIndex = 0,
    this.highlightedTaskId,
    this.highlightedLat,
    this.highlightedLng,
  });

  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  // ignore: unused_field
  int _previousIndex = 0;
  late final List<Widget> _pages;
  late final PageController _pageController;

  final Map<int, GlobalKey> _pageKeys = {};
  final GlobalKey<AdminMapScreenState> _adminMapScreenKey =
      GlobalKey<AdminMapScreenState>();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;

    // Inisialisasi pages dengan GlobalKey unik
    if (widget.userRole == 'commandCenter') {
      _pages = [
        AdminMapScreen( //
          key: _adminMapScreenKey,
          highlightedTaskId: widget.highlightedTaskId,
          highlightedLat: widget.highlightedLat,
          highlightedLng: widget.highlightedLng,
        ),
        AdminDashboardScreen(key: _getKeyForIndex(1)), //
        ManageClustersScreen(key: _getKeyForIndex(2)), //
        // Halaman Survei untuk CommandCenter
        ManageSurveysScreen(key: _getKeyForIndex(3)), // [INFO: Kerangka kode ManageSurveysScreen telah diberikan sebelumnya]
        ProfileScreen(key: _getKeyForIndex(4)), //
      ];
    } else { // Untuk role 'patrol' atau role lainnya
      _pages = [
        HomeScreen(key: _getKeyForIndex(0)), //
        // Halaman Survei untuk Patrol
        SurveyListScreen(key: _getKeyForIndex(1)), // [INFO: Kerangka kode SurveyListScreen telah diberikan sebelumnya]
        ProfileScreen(key: _getKeyForIndex(2)), //
      ];
    }

    _pageController = PageController(initialPage: _selectedIndex);
  }

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

  void goToAdminMapAndHighlight(String taskId, double lat, double lng) {
    if (widget.userRole == 'commandCenter') {
      _pageController.jumpToPage(0);
      setState(() {
        _selectedIndex = 0;
      });
      _adminMapScreenKey.currentState?.highlightLocation(taskId, lat, lng);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<NavBarItem> navBarItems = [];
    if (widget.userRole == 'commandCenter') {
      navBarItems = [
        const NavBarItem(
          activeIcon: Icons.map, // Ganti ikon Home menjadi Map untuk Admin
          inactiveIcon: Icons.map_outlined,
          label: 'Peta', // Label diubah menjadi Peta
        ),
        const NavBarItem(
          activeIcon: Icons.task_alt, // Ikon yang lebih relevan untuk Task/Dashboard
          inactiveIcon: Icons.task_alt_outlined,
          label: 'Tugas', // Label diubah menjadi Tugas
        ),
        const NavBarItem(
          activeIcon: Icons.location_city,
          inactiveIcon: Icons.location_city_outlined,
          label: 'Tatar',
        ),
        const NavBarItem( // Item Navigasi Survei
          activeIcon: Icons.poll,
          inactiveIcon: Icons.poll_outlined,
          label: 'Survei',
        ),
        const NavBarItem(
          activeIcon: Icons.person,
          inactiveIcon: Icons.person_outline,
          label: 'Profil',
        ),
      ];
    } else { // Untuk role 'patrol'
      navBarItems = [
        const NavBarItem(
          activeIcon: Icons.home,
          inactiveIcon: Icons.home_outlined,
          label: 'Home',
        ),
        const NavBarItem( // Item Navigasi Survei
          activeIcon: Icons.poll,
          inactiveIcon: Icons.poll_outlined,
          label: 'Survei',
        ),
        const NavBarItem(
          activeIcon: Icons.person,
          inactiveIcon: Icons.person_outline,
          label: 'Profil',
        ),
      ];
    }

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
      bottomNavigationBar: CustomNavBar( //
        items: navBarItems,
        initialIndex: _selectedIndex,
        onItemSelected: (index) {
          if (_selectedIndex == index) {
            _refreshCurrentPage(index);
          } else {
            _pageController.jumpToPage(index);
          }
        },
      ),
    );
  }

  void _refreshCurrentPage(int index) {
    setState(() {
      _pageKeys[index] = GlobalKey();

      if (widget.userRole == 'commandCenter') {
        switch (index) {
          case 0:
            _pages[0] = AdminMapScreen(key: _adminMapScreenKey); //
            break;
          case 1:
            _pages[1] = AdminDashboardScreen(key: _pageKeys[index]); //
            break;
          case 2:
            _pages[2] = ManageClustersScreen(key: _pageKeys[index]); //
            break;
          case 3: // Index baru untuk Survei (ManageSurveysScreen)
            _pages[3] = ManageSurveysScreen(key: _pageKeys[index]); // [INFO: Kerangka kode ManageSurveysScreen telah diberikan sebelumnya]
            break;
          case 4: // Index untuk Profile menjadi 4
            _pages[4] = ProfileScreen(key: _pageKeys[index]); //
            break;
        }
      } else { // Untuk role 'patrol'
        switch (index) {
          case 0:
            _pages[0] = HomeScreen(key: _pageKeys[index]); //
            break;
          case 1: // Index baru untuk Survei (SurveyListScreen)
            _pages[1] = SurveyListScreen(key: _pageKeys[index]); // [INFO: Kerangka kode SurveyListScreen telah diberikan sebelumnya]
            break;
          case 2: // Index untuk Profile menjadi 2
            _pages[2] = ProfileScreen(key: _pageKeys[index]); //
            break;
        }
      }
    });
  }
}