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

  bool _isPasswordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
          showCustomSnackbar(
            context: context,
            title: 'Login Failed',
            subtitle: state.message,
            type: SnackbarType.danger,
          );
        }
      },
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  Text(
                    'Live Tracking KBP',
                    style: boldTextStyle(size: h4, color: kbpBlue900),
                  ),
                  const SizedBox(height: 48),
                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle:
                          regularTextStyle(size: paragrafLG, color: neutral700),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color:
                              kbpBlue900, // Warna border saat field tidak fokus
                          width: 2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: kbpBlue900, // Warna border saat field fokus
                          width: 2,
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.email,
                        color: kbpBlue900,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle:
                          regularTextStyle(size: paragrafLG, color: neutral700),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color:
                              kbpBlue900, // Warna border saat field tidak fokus
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color:
                              kbpBlue900, // Warna border saat field tidak fokus
                          width: 2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: kbpBlue900, // Warna border saat field fokus
                          width: 2,
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock,
                        color: kbpBlue900,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(!_isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off), //
                        color: kbpBlue900,
                        onPressed: () {
                          // Tindakan saat ikon mata ditekan
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                    ),
                    obscureText: !_isPasswordVisible,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  // Login Button
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      return ElevatedButton(
                        onPressed: state is AuthLoading
                            ? null
                            : () {
                                if (_formKey.currentState!.validate()) {
                                  context.read<AuthBloc>().add(
                                        LoginRequested(
                                          email: _emailController.text,
                                          password: _passwordController.text,
                                        ),
                                      );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kbpBlue900,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: state is AuthLoading
                            ? const CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              )
                            : Text(
                                'Login',
                                style: boldTextStyle(
                                    size: paragrafLG, color: neutralWhite),
                              ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Footer
                  TextButton(
                    onPressed: () {
                      // Tambahkan navigasi ke halaman lupa password jika ada
                    },
                    child: Text(
                      'Forgot Password?',
                      style:
                          regularTextStyle(size: paragrafLG, color: kbpBlue900),
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
}
