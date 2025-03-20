import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:livetrackingapp/firebase_options.dart';
import 'package:livetrackingapp/home_screen.dart';
import 'package:livetrackingapp/presentation/auth/login_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livetrackingapp/data/repositories/route_repositoryImpl.dart';
import 'data/repositories/auth_repositoryImpl.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/route_repository.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';

final getIt = GetIt.instance;

void setupLocator() {
  // Remove MapboxService registration

  // Register RouteRepository implementation
  getIt.registerLazySingleton<RouteRepository>(
    () => RouteRepositoryImpl(),
  );

  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      firebaseAuth: FirebaseAuth.instance,
    ),
  );
}

Future<void> initializeApp() async {
  // Initialize Firebase with platform-specific options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Wait for auth state to be determined
  await Future.delayed(const Duration(seconds: 1));

  if (FirebaseAuth.instance.currentUser != null) {
    try {
      // Enable persistence only after authentication
      FirebaseDatabase.instance.setPersistenceEnabled(true);
      print(
          'Database persistence enabled for user: ${FirebaseAuth.instance.currentUser?.uid}');
    } catch (e) {
      print('Error enabling persistence: $e');
    }
  }

  // Request permissions based on platform
  if (Platform.isIOS) {
    await Permission.location.request();
  } else if (Platform.isAndroid) {
    await Permission.notification.request();
    await Permission.location.request();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeApp();
  setupLocator();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(
            repository: getIt<AuthRepository>(),
          )..add(CheckAuthStatus()),
        ),
        // Remove duplicate PatrolBloc provider
        BlocProvider<PatrolBloc>(
          create: (context) {
            final bloc = PatrolBloc(
              repository: getIt<RouteRepository>(),
            );
            bloc.emit(PatrolLoading());
            return bloc;
          },
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          print('Current auth state: $state'); // Debug print
          return MaterialApp(
            title: 'Live Tracking App',
            theme: ThemeData(
              scaffoldBackgroundColor: Colors.white,
              primarySwatch: Colors.green,
              fontFamily: 'Plus Jakarta Sans',
            ),
            home: (state is AuthAuthenticated)
                ? const HomeScreen()
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}
