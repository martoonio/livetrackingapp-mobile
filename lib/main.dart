import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:livetrackingapp/data/repositories/report_repositoryImpl.dart';
import 'package:livetrackingapp/domain/repositories/report_repository.dart';
import 'package:livetrackingapp/domain/usecases/report_usecase.dart';
import 'package:livetrackingapp/firebase_options.dart';
import 'package:livetrackingapp/main_nav_screen.dart';
import 'package:livetrackingapp/notification_utils.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/auth/login_screen.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livetrackingapp/data/repositories/route_repositoryImpl.dart';
import 'data/repositories/auth_repositoryImpl.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/route_repository.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';
import 'presentation/component/utils.dart';

final getIt = GetIt.instance;
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

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
  getIt.registerLazySingleton<ReportRepository>(
    () => ReportRepositoryImpl(
      firebaseStorage: FirebaseStorage.instance,
      databaseReference: FirebaseDatabase.instance.ref(),
    ),
  );

  getIt.registerLazySingleton<CreateReportUseCase>(
    () => CreateReportUseCase(getIt<ReportRepository>()),
  );
}

Future<void> requestLocationPermission() async {
  final status = await Permission.location.request();
  if (status.isGranted) {
    print('Location permission granted');
  } else if (status.isDenied) {
    print('Location permission denied');
  } else if (status.isPermanentlyDenied) {
    print('Location permission permanently denied');
    await openAppSettings(); // Buka pengaturan aplikasi jika izin ditolak permanen
  }
}

Future<void> requestNotificationPermission() async {
  final status = await Permission.notification.request();
  if (status.isGranted) {
    print('Notification permission granted');
  } else if (status.isDenied) {
    print('Notification permission denied');
  } else if (status.isPermanentlyDenied) {
    print('Notification permission permanently denied');
    await openAppSettings(); // Buka pengaturan aplikasi jika izin ditolak permanen
  }
}

Future<void> initializeApp() async {
  // Initialize Firebase with platform-specific options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Wait for auth state to be determined
  await Future.delayed(const Duration(seconds: 1));

  await initializeDateFormatting('id_ID', null);

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

  await requestLocationPermission();
  await requestNotificationPermission();
}

Future<String?> getUserRole() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null; // Pengguna belum login
    }

    // Referensi ke path pengguna di Realtime Database
    final userRef = FirebaseDatabase.instance.ref('users/${user.uid}');
    final snapshot = await userRef.get();

    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      return data['role'] as String?; // Ambil nilai role
    } else {
      print('User data not found in database');
      return null;
    }
  } catch (e) {
    print('Error fetching user role: $e');
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeApp();
  await initNotification();
  setupLocator();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final String? userRole;
  const MyApp({super.key, this.userRole});

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
        BlocProvider<AdminBloc>(
          create: (context) => AdminBloc(
            repository: getIt<RouteRepository>(),
          )..add(LoadAllTasks()),
          lazy: false, // Initialize immediately
        ),
        BlocProvider<AdminBloc>(
          create: (context) => AdminBloc(
            repository: getIt<RouteRepository>(),
          )..add(LoadOfficersAndVehicles()),
          lazy: false,
        ),
        BlocProvider<AdminBloc>(
          create: (context) => AdminBloc(
            repository: RouteRepositoryImpl(),
          )..add(LoadAllTasks()),
          lazy: false,
        ),
        BlocProvider<ReportBloc>(
          create: (context) => ReportBloc(
            getIt<CreateReportUseCase>(),
          ),
          lazy: false,
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          print('Current auth state: $state'); // Debug print
          return MaterialApp(
            title: 'Live Tracking App',
            theme: ThemeData(
              scaffoldBackgroundColor: neutralWhite,
              primaryColor: successG300,
              colorScheme:
                  ColorScheme.fromSwatch().copyWith(primary: successG300),
              fontFamily: 'Plus Jakarta Sans',
            ),
            home: (state is AuthAuthenticated)
                ? MainNavigationScreen(userRole: userRole ?? 'User')
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}
