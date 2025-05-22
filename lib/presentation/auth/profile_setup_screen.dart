import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/main_nav_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'bloc/auth_bloc.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String email;

  const ProfileSetupScreen({
    Key? key,
    required this.email,
  }) : super(key: key);

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _role = 'Officer'; // Default role

  static const _availableRoles = ['Officer', 'Command Center'];
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        setState(() {
          _isSubmitting = state is AuthLoading;
        });

        if (state is AuthAuthenticated) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MainNavigationScreen(userRole: state.user.role),
            ),
          );
        } else if (state is AuthError) {
          showCustomSnackbar(
            context: context,
            title: 'Pengaturan Profil Gagal',
            subtitle: state.message,
            type: SnackbarType.danger,
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            'Lengkapi Profil Anda',
            style: semiBoldTextStyle(color: Colors.white),
          ),
          backgroundColor: kbpBlue900,
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false, // Prevent back navigation
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Welcome text
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: kbpBlue50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selamat Datang!',
                          style: boldTextStyle(size: 18, color: kbpBlue900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Satu langkah lagi untuk mengaktifkan akun Anda',
                          style: regularTextStyle(size: 14, color: neutral600),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.email,
                                size: 16, color: kbpBlue700),
                            const SizedBox(width: 8),
                            Text(
                              widget.email,
                              style:
                                  mediumTextStyle(size: 14, color: kbpBlue700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Nama lengkap field
                  Text(
                    'Nama Lengkap',
                    style: mediumTextStyle(size: 14),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: InputDecoration(
                      hintText: 'Masukkan nama lengkap Anda',
                      prefixIcon: const Icon(Icons.person, color: kbpBlue900),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: neutral300, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: neutral300, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: kbpBlue900, width: 2),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: dangerR500, width: 1),
                      ),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Nama lengkap tidak boleh kosong';
                      }
                      return null;
                    },
                    onSaved: (value) => _name = value ?? '',
                  ),

                  const SizedBox(height: 16),

                  // Role field
                  Text(
                    'Peran',
                    style: mediumTextStyle(size: 14),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.badge, color: kbpBlue900),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: neutral300, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: neutral300, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: kbpBlue900, width: 2),
                      ),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                    value: _role,
                    items: _availableRoles.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(
                          role,
                          style: regularTextStyle(),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _role = value ?? 'Officer';
                      });
                    },
                  ),

                  const SizedBox(height: 32),

                  // Submit button
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kbpBlue900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      disabledBackgroundColor: kbpBlue300,
                    ),
                    child: _isSubmitting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Memproses...',
                                style: mediumTextStyle(color: Colors.white),
                              ),
                            ],
                          )
                        : Text(
                            'Selesaikan Pengaturan',
                            style: mediumTextStyle(color: Colors.white),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getRoleTranslation(String role) {
    switch (role) {
      case 'Officer':
        return 'patrol';
      // case 'Head':
      //   return 'Kepala Tim';
      // case 'Admin':
      //   return 'Administrator';
      case 'Command Center':
        return 'commandCenter';
      default:
        return role;
    }
  }

  void _submitForm() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

      context.read<AuthBloc>().add(
            CompleteProfile(
              name: _name,
              role: _getRoleTranslation(_role),
            ),
          );
    }
  }
}
