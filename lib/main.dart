import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:livetrackingapp/firebase_options.dart';
import 'package:livetrackingapp/home_screen.dart';
import 'package:livetrackingapp/map_screen.dart';
import 'package:livetrackingapp/presentation/auth/login_screen.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livetrackingapp/data/repositories/route_repositoryImpl.dart';
import 'package:livetrackingapp/data/source/mapbox_service.dart';
import 'data/repositories/auth_repositoryImpl.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/route_repository.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';

final getIt = GetIt.instance;

void setupLocator() {
  // Register MapboxService for route calculations
  getIt.registerLazySingleton(() => MapboxService());

  // Register RouteRepository implementation
  getIt.registerLazySingleton<RouteRepository>(
    () => RouteRepositoryImpl(
      mapboxService: getIt(),
    ),
  );

  // Register AuthRepository implementation
  // getIt.registerLazySingleton<AuthRepository>(
  //   () => AuthRepositoryImpl(),
  // );

  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      firebaseAuth: FirebaseAuth.instance,
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase first
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  try {
    print('Enabling database persistence...');
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    print('Database persistence enabled');
  } catch (e) {
    print('Error enabling persistence: $e');
  }

  // Setup dependency injection
  setupLocator();

  // Load environment variables
  await dotenv.load(fileName: '.env');
  MapboxOptions.setAccessToken(dotenv.env['MAPBOX_TOKEN']!);

  // Request necessary permissions
  if (Platform.isAndroid) {
    await Permission.notification.request();
    await Permission.location.request();
  }

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
        BlocProvider<PatrolBloc>(
          create: (context) => PatrolBloc(
            repository: getIt<RouteRepository>(),
          ),
        ),
        BlocProvider<PatrolBloc>(
          create: (context) {
            final bloc = PatrolBloc(
              repository: getIt<RouteRepository>(),
            );
            // Initialize with loading state
            bloc.emit(PatrolLoading());
            return bloc;
          },
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          return MaterialApp(
            title: 'Live Tracking App',
            theme: ThemeData(
                scaffoldBackgroundColor: Colors.white,
                primarySwatch: Colors.green,
                fontFamily: 'Plus Jakarta Sans'),
            home: (state is AuthAuthenticated)
                ? const HomeScreen()
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}
