import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/main_nav_screen.dart';
import 'package:livetrackingapp/presentation/auth/profile_setup_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'bloc/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  bool _isPasswordVisible = false;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthNeedsProfile) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ProfileSetupScreen(email: state.email),
            ),
          );
        } else if (state is AuthAuthenticated) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MainNavigationScreen(userRole: state.user.role),
            ),
          );
        } else if (state is AuthError) {
          String title = 'Login Gagal';
          IconData iconData = Icons.error_outline;
          Color iconColor = dangerR500;

          switch (state.code) {
            case 'user-not-found':
              title = 'Email Tidak Terdaftar';
              break;
            case 'wrong-password':
              title = 'Password Salah';
              FocusScope.of(context).requestFocus(_passwordFocusNode);
              break;
            case 'invalid-email':
              title = 'Format Email Tidak Valid';
              break;
            case 'user-disabled':
              title = 'Akun Dinonaktifkan';
              break;
            case 'too-many-requests':
              title = 'Terlalu Banyak Percobaan';
              iconData = Icons.timer_outlined;
              iconColor = warningY500;
              break;
            case 'network-error':
              title = 'Gangguan Koneksi';
              iconData = Icons.wifi_off_outlined;
              iconColor = warningY500;
              break;
          }

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(iconData, color: iconColor, size: 24),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      title,
                      style: semiBoldTextStyle(size: 18, color: neutral900),
                    ),
                  ),
                ],
              ),
              content: Text(
                state.message,
                style: regularTextStyle(size: 14, color: neutral700),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Tutup',
                    style: mediumTextStyle(size: 14, color: neutral700),
                  ),
                ),
              ],
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: neutral200,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Logo and App Name
                      Container(
                        margin: const EdgeInsets.only(bottom: 32),
                        child: Column(
                          children: [
                            // Logo
                            Container(
                              width: 100,
                              height: 100,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/logo/logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.location_on,
                                    size: 48,
                                    color: kbpBlue900,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            // App name
                            Text(
                              'Live Tracking KBP',
                              style: boldTextStyle(size: 28, color: kbpBlue900),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sistem Pemantauan Patroli',
                              style:
                                  regularTextStyle(size: 16, color: kbpBlue700),
                            ),
                          ],
                        ),
                      ),

                      // Login card
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: kbpBlue200, width: 1),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Login header
                              Text(
                                'Masuk ke Akun',
                                style: semiBoldTextStyle(
                                    size: 20, color: kbpBlue900),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Masukkan informasi login Anda',
                                style: regularTextStyle(
                                    size: 14, color: neutral700),
                              ),
                              const SizedBox(height: 24),

                              // Email Field
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Email',
                                    style: mediumTextStyle(
                                        size: 14, color: kbpBlue900),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: InputDecoration(
                                      hintText: 'Masukkan email Anda',
                                      hintStyle: regularTextStyle(
                                          size: 14, color: neutral500),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: neutral300, width: 1),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: neutral300, width: 1),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: kbpBlue700, width: 1.5),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: dangerR500, width: 1),
                                      ),
                                      prefixIcon: Icon(
                                        Icons.email_outlined,
                                        color: kbpBlue700,
                                        size: 20,
                                      ),
                                    ),
                                    style: regularTextStyle(
                                        size: 16, color: neutral900),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Email tidak boleh kosong';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Password Field
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Password',
                                    style: mediumTextStyle(
                                        size: 14, color: kbpBlue900),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _passwordController,
                                    focusNode: _passwordFocusNode,
                                    obscureText: !_isPasswordVisible,
                                    decoration: InputDecoration(
                                      hintText: 'Masukkan password Anda',
                                      hintStyle: regularTextStyle(
                                          size: 14, color: neutral500),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: neutral300, width: 1),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: neutral300, width: 1),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: kbpBlue700, width: 1.5),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: dangerR500, width: 1),
                                      ),
                                      prefixIcon: Icon(
                                        Icons.lock_outline,
                                        color: kbpBlue700,
                                        size: 20,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          !_isPasswordVisible
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 20,
                                        ),
                                        color: kbpBlue700,
                                        onPressed: () {
                                          setState(() {
                                            _isPasswordVisible =
                                                !_isPasswordVisible;
                                          });
                                        },
                                      ),
                                    ),
                                    style: regularTextStyle(
                                        size: 16, color: neutral900),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Password tidak boleh kosong';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),

                              // Remember me & Forgot Password
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16.0),
                                child: TextButton(
                                  onPressed: () {
                                    // Navigate to forgot password
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: kbpBlue900,
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Lupa Password?',
                                    style: mediumTextStyle(
                                        size: 14, color: kbpBlue900),
                                  ),
                                ),
                              ),

                              // Error Message
                              BlocBuilder<AuthBloc, AuthState>(
                                builder: (context, state) {
                                  if (state is AuthError) {
                                    return Container(
                                      margin:
                                          EdgeInsets.only(top: 16, bottom: 8),
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: dangerR50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: dangerR200),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            _getErrorIcon(state.code),
                                            color: dangerR500,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _getErrorMessage(state.code),
                                              style: regularTextStyle(
                                                  size: 13, color: dangerR300),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return SizedBox.shrink();
                                },
                              ),

                              // Login Button
                              BlocBuilder<AuthBloc, AuthState>(
                                builder: (context, state) {
                                  return SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: state is AuthLoading
                                          ? null
                                          : () {
                                              if (_formKey.currentState!
                                                  .validate()) {
                                                context.read<AuthBloc>().add(
                                                      LoginRequested(
                                                        email: _emailController
                                                            .text,
                                                        password:
                                                            _passwordController
                                                                .text,
                                                      ),
                                                    );
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kbpBlue900,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: kbpBlue200,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: state is AuthLoading
                                          ? SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(
                                              'Masuk',
                                              style: semiBoldTextStyle(
                                                  size: 16,
                                                  color: Colors.white),
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Footer
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Belum punya akun? ',
                                  style: regularTextStyle(
                                      size: 14, color: neutral700),
                                ),
                                TextButton(
                                  onPressed: () {
                                    // Navigate to register screen
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: kbpBlue900,
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Hubungi admin',
                                    style: semiBoldTextStyle(
                                        size: 14, color: kbpBlue900),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '© 2024 KBP Live Tracking',
                              style:
                                  regularTextStyle(size: 12, color: neutral500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getErrorIcon(String code) {
    switch (code) {
      case 'user-not-found':
        return Icons.person_off_outlined;
      case 'wrong-password':
        return Icons.lock_open;
      case 'invalid-email':
        return Icons.alternate_email;
      case 'user-disabled':
        return Icons.person_off;
      case 'too-many-requests':
        return Icons.timer_outlined;
      case 'network-error':
        return Icons.wifi_off_outlined;
      default:
        return Icons.error_outline;
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Email tidak terdaftar. Hubungi admin untuk mendaftar.';
      case 'wrong-password':
        return 'Password yang Anda masukkan salah. Silakan coba lagi.';
      case 'invalid-email':
        return 'Format email tidak valid. Harap periksa kembali.';
      case 'user-disabled':
        return 'Akun Anda dinonaktifkan. Hubungi admin.';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan gagal. Coba lagi nanti.';
      case 'network-error':
        return 'Gagal terhubung ke server. Periksa koneksi internet Anda.';
      default:
        return 'Terjadi kesalahan saat login. Silakan coba lagi.';
    }
  }
}
