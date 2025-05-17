import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import '../auth/bloc/auth_bloc.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is! AuthAuthenticated) {
          return const Scaffold(
            backgroundColor: neutral200,
            body: Center(
              child: CircularProgressIndicator(color: kbpBlue900),
            ),
          );
        }

        final user = state.user;

        // Get first letter of name for avatar
        final String initials = user.name.isNotEmpty
            ? user.name
                .split(' ')
                .map((e) => e.isNotEmpty ? e[0] : '')
                .join('')
                .toUpperCase()
            : 'U';

        return Scaffold(
          backgroundColor: neutral200,
          appBar: AppBar(
            title: Text(
              'Profil Saya',
              style: semiBoldTextStyle(size: 18, color: kbpBlue900),
            ),
            backgroundColor: Colors.white,
            elevation: 0.5,
            automaticallyImplyLeading: false,
            centerTitle: true,
            iconTheme: const IconThemeData(color: neutralWhite),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // Profile header with avatar
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x0D000000),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Avatar
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: kbpBlue100,
                            shape: BoxShape.circle,
                            border: Border.all(color: kbpBlue300, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: boldTextStyle(size: 36, color: kbpBlue900),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Name
                        Text(
                          user.name,
                          style: semiBoldTextStyle(size: 20, color: kbpBlue900),
                        ),

                        // Role with badge
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: kbpBlue50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kbpBlue200),
                          ),
                          child: Text(
                            _getRoleDisplay(user.role),
                            style: mediumTextStyle(size: 14, color: kbpBlue800),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Profile info
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section title
                        Row(
                          children: [
                            const Icon(Icons.info_outline,
                                color: kbpBlue900, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Informasi Akun',
                              style: semiBoldTextStyle(
                                  size: 18, color: kbpBlue900),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Account info card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: kbpBlue200, width: 1),
                          ),
                          child: Column(
                            children: [
                              // Email
                              _buildInfoItem(
                                icon: Icons.email_outlined,
                                title: 'Email',
                                value: user.email,
                                showDivider: true,
                              ),

                              // Role
                              _buildInfoItem(
                                icon: Icons.work_outline,
                                title: 'Role',
                                value: _getRoleDisplay(user.role),
                                showDivider: false,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // App info
                        Row(
                          children: [
                            const Icon(Icons.phone_android,
                                color: kbpBlue900, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Informasi Aplikasi',
                              style: semiBoldTextStyle(
                                  size: 18, color: kbpBlue900),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Version card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: kbpBlue200, width: 1),
                          ),
                          child: _buildInfoItem(
                            icon: Icons.info_outline,
                            title: 'Versi Aplikasi',
                            value: '1.0.0',
                            showDivider: false,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Logout button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => _showLogoutDialog(context),
                            icon: const Icon(Icons.logout),
                            label: Text(
                              'Keluar',
                              style: semiBoldTextStyle(
                                  size: 16, color: neutralWhite),
                            ),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: dangerR500,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
    required bool showDivider,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kbpBlue50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: kbpBlue900, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: regularTextStyle(size: 14, color: kbpBlue700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: semiBoldTextStyle(size: 16, color: kbpBlue900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, color: kbpBlue200),
      ],
    );
  }

  String _getRoleDisplay(String role) {
    switch (role.toLowerCase()) {
      case 'patrol':
        return 'Petugas Patroli';
      case 'commandcenter':
      case 'command_center':
        return 'Command Center';
      case 'admin':
        return 'Administrator';
      default:
        return role;
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Text(
          'Konfirmasi Keluar',
          style: semiBoldTextStyle(size: 18, color: kbpBlue900),
        ),
        content: Text(
          'Apakah Anda yakin ingin keluar dari aplikasi?',
          style: regularTextStyle(size: 16, color: neutral900),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Batal',
              style: mediumTextStyle(color: kbpBlue900),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<AuthBloc>().add(LogoutRequested());
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => const LoginScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerR500,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(
              'Keluar',
              style: semiBoldTextStyle(size: 14, color: neutralWhite),
            ),
          ),
        ],
      ),
    );
  }
}
