import 'package:flutter/material.dart';
import 'package:livetrackingapp/presentation/component/customNavBar.dart';

import 'home_screen.dart';
import 'presentation/admin/admin_dashboard_screen.dart';
import 'presentation/auth/profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final String userRole; // Tambahkan parameter untuk role pengguna

  const MainNavigationScreen({
    Key? key,
    required this.userRole, // Role pengguna harus diberikan
  }) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    // Tentukan halaman berdasarkan role pengguna
    _pages = [
      const HomeScreen(),
      if (widget.userRole == 'Admin')
        const AdminDashboardScreen(), // Tampilkan hanya jika role adalah Admin
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: CustomNavBar(
        items: [
          const NavBarItem(
            activeIcon: Icons.home,
            inactiveIcon: Icons.home_outlined,
            label: 'Home',
          ),
          if (widget.userRole ==
              'Admin') // Tampilkan hanya jika role adalah Admin
            const NavBarItem(
              activeIcon: Icons.dashboard,
              inactiveIcon: Icons.dashboard_outlined,
              label: 'Admin',
            ),
          const NavBarItem(
            activeIcon: Icons.person,
            inactiveIcon: Icons.person_outline,
            label: 'Profile',
          ),
        ],
        initialIndex: _selectedIndex,
        onItemSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
