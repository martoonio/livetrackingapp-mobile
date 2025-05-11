import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/presentation/component/intExtension.dart';
import '../auth/bloc/auth_bloc.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is! AuthAuthenticated) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = state.user;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () {
                  context.read<AuthBloc>().add(LogoutRequested());
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const CircleAvatar(
                radius: 50,
                child: Icon(Icons.person, size: 50),
              ),
              16.height,
              Card(
                child: ListTile(
                  title: Text(user.name),
                  subtitle: const Text('Name'),
                  leading: const Icon(Icons.person_outline),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text(user.email),
                  subtitle: const Text('Email'),
                  leading: const Icon(Icons.email_outlined),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text(user.role),
                  subtitle: const Text('Role'),
                  leading: const Icon(Icons.work_outline),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
