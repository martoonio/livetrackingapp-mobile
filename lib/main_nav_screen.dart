import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/presentation/admin/admin_dashboard_screen.dart';
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';
import 'package:livetrackingapp/presentation/auth/profile_screen.dart';
import '../../home_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is! AuthAuthenticated) {
          return const Center(child: CircularProgressIndicator());
        }

        final isAdmin = state.user.role == 'Admin';
        final pages = [
          const HomeScreen(),
          if (isAdmin) const AdminDashboardScreen(),
          const ProfileScreen(),
        ];

        return Scaffold(
          body: IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Patrol',
              ),
              if (isAdmin)
                const NavigationDestination(
                  icon: Icon(Icons.admin_panel_settings_outlined),
                  selectedIcon: Icon(Icons.admin_panel_settings),
                  label: 'Admin',
                ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}