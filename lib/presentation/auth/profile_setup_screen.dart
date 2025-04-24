import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/home_screen.dart';
import 'package:livetrackingapp/main_nav_screen.dart';
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';

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

  static const _availableRoles = ['Officer', 'Head', 'Admin', 'Command Center'];

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          // Navigate to home screen when profile is complete
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const MainNavigationScreen(),
            ),
          );
        } else if (state is AuthError) {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Complete Your Profile'),
          automaticallyImplyLeading: false, // Prevent back navigation
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome ${widget.email}!',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                  onSaved: (value) => _name = value ?? '',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  value: _role,
                  items: _availableRoles.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _role = value ?? 'Officer';
                    });
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitForm,
                  child: const Text('Complete Setup'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submitForm() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

      context.read<AuthBloc>().add(
            CompleteProfile(
              name: _name,
              role: _role,
            ),
          );
      log('Profile setup completed: Name: $_name, Role: $_role');
    }
  }
}
