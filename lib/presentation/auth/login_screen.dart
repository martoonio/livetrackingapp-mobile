import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/main.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/route_repository.dart';
import '../../home_screen.dart';
import '../../map_screen.dart';
import '../routing/bloc/patrol_bloc.dart';
import 'bloc/auth_bloc.dart';
import 'complete_profile_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) async {
        print('Auth state changed: $state');

        if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        } else if (state is AuthAuthenticated) {
          print('User authenticated: ${state.user.email}');
          
          // Check if profile is incomplete
          // if (state.user.name.isEmpty || state.user.role.isEmpty) {
          //   // Show dialog to complete profile
          //   await showDialog(
          //     context: context,
          //     barrierDismissible: false,
          //     builder: (_) => CompleteProfileDialog(
          //       onSubmit: (name, role) async {
          //         try {
          //           await getIt<AuthRepository>().updateUserProfile(
          //             state.user.id,
          //             name,
          //             role,
          //           );
                    
          //           // Navigate to home screen after profile completion
          //           Navigator.of(context).pushReplacement(
          //             MaterialPageRoute(
          //               builder: (_) => BlocProvider(
          //                 create: (context) => PatrolBloc(
          //                   repository: getIt<RouteRepository>(),
          //                 )..add(LoadRouteData(userId: state.user.id)),
          //                 child: const HomeScreen(),
          //               ),
          //             ),
          //           );
          //         } catch (e) {
          //           ScaffoldMessenger.of(context).showSnackBar(
          //             SnackBar(content: Text('Failed to update profile: $e')),
          //           );
          //         }
          //       },
          //     ),
          //   );
          // } 
          // else {
            // Navigate directly to home screen if profile is complete
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => BlocProvider(
                  create: (context) => PatrolBloc(
                    repository: getIt<RouteRepository>(),
                  )..add(LoadRouteData(userId: state.user.id)),
                  child: const HomeScreen(),
                ),
              ),
            );
          // }
        }
      },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Live Tracking KBP',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 48),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
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
                        child: state is AuthLoading
                            ? const CircularProgressIndicator()
                            : const Text('Login'),
                      );
                    },
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
