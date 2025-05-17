import 'package:flutter/material.dart';
import 'package:livetrackingapp/presentation/component/customNavBar.dart';

import 'home_screen.dart';
import 'presentation/admin/admin_dashboard_screen.dart';
import 'presentation/auth/profile_screen.dart';
import 'presentation/cluster/manage_screen_cluster.dart';

class MainNavigationScreen extends StatefulWidget {
  final String userRole;

  const MainNavigationScreen({
    Key? key,
    required this.userRole,
  }) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  int _previousIndex = 0;
  late final List<Widget> _pages;
  late final PageController _pageController;

  // Key untuk memaksa rebuild screens saat perlu
  final Map<int, GlobalKey> _pageKeys = {};

  @override
  void initState() {
    super.initState();

    // Inisialisasi pages dengan GlobalKey unik
    _pages = [
      HomeScreen(key: _getKeyForIndex(0)),
    ];

    if (widget.userRole == 'commandCenter') {
      _pages.add(AdminDashboardScreen(key: _getKeyForIndex(1)));
      _pages.add(ManageClustersScreen(key: _getKeyForIndex(2)));
    }

    _pages.add(ProfileScreen(key: _getKeyForIndex(_pages.length)));

    // Inisialisasi PageController
    _pageController = PageController(initialPage: _selectedIndex);
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
        items: [
          const NavBarItem(
            activeIcon: Icons.home,
            inactiveIcon: Icons.home_outlined,
            label: 'Home',
          ),
          if (widget.userRole == 'commandCenter')
            const NavBarItem(
              activeIcon: Icons.dashboard,
              inactiveIcon: Icons.dashboard_outlined,
              label: 'Admin',
            ),
          if (widget.userRole == 'commandCenter')
            const NavBarItem(
              activeIcon: Icons.location_city,
              inactiveIcon: Icons.location_city_outlined,
              label: 'Clusters',
            ),
          const NavBarItem(
            activeIcon: Icons.person,
            inactiveIcon: Icons.person_outline,
            label: 'Profile',
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
      if (index == 0) {
        _pages[0] = HomeScreen(key: _pageKeys[index]);
      } else if (widget.userRole == 'commandCenter') {
        if (index == 1) {
          _pages[1] = AdminDashboardScreen(key: _pageKeys[index]);
        } else if (index == 2) {
          _pages[2] = ManageClustersScreen(key: _pageKeys[index]);
        } else {
          _pages[_pages.length - 1] = ProfileScreen(key: _pageKeys[index]);
        }
      } else {
        _pages[_pages.length - 1] = ProfileScreen(key: _pageKeys[index]);
      }
    });
  }
}
