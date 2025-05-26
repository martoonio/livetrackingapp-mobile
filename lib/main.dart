import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:livetrackingapp/data/repositories/report_repositoryImpl.dart';
import 'package:livetrackingapp/data/repositories/survey_repositoryImpl.dart';
import 'package:livetrackingapp/domain/repositories/report_repository.dart';
import 'package:livetrackingapp/domain/repositories/survey_repository.dart';
import 'package:livetrackingapp/domain/usecases/report_usecase.dart';
import 'package:livetrackingapp/firebase_options.dart';
import 'package:livetrackingapp/main_nav_screen.dart';
import 'package:livetrackingapp/notification_utils.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/auth/login_screen.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_bloc.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_event.dart';
import 'package:livetrackingapp/presentation/survey/survey_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livetrackingapp/data/repositories/route_repositoryImpl.dart';
import 'data/repositories/auth_repositoryImpl.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/route_repository.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';
import 'presentation/component/utils.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
export 'package:livetrackingapp/main.dart' show navigatorKey;

final getIt = GetIt.instance;
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// Navigator key global untuk navigasi dari mana saja
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Box untuk menyimpan data offline
late Box offlineReportsBox;

void setupLocator() {
  // Register repositories
  getIt.registerLazySingleton<RouteRepository>(
    () => RouteRepositoryImpl(),
  );

  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      firebaseAuth: FirebaseAuth.instance,
    ),
  );

  // Register report repository dengan Hive storage
  getIt.registerLazySingleton<ReportRepository>(
    () => ReportRepositoryImpl(
      firebaseStorage: FirebaseStorage.instance,
      databaseReference: FirebaseDatabase.instance.ref(),
      offlineReportsBox: offlineReportsBox,
    ),
  );

  // Register report use cases
  getIt.registerLazySingleton<CreateReportUseCase>(
    () => CreateReportUseCase(getIt<ReportRepository>()),
  );

  getIt.registerLazySingleton<SyncOfflineReportsUseCase>(
    () => SyncOfflineReportsUseCase(getIt<ReportRepository>()),
  );

  getIt.registerLazySingleton<GetOfflineReportsUseCase>(
    () => GetOfflineReportsUseCase(getIt<ReportRepository>()),
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
  // Initialize Firebase dengan platform-specific options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Wait for auth state to be determined
  await Future.delayed(const Duration(seconds: 1));

  await initializeDateFormatting('id_ID', null);

  // Initialize Hive dan box untuk offline reports
  await Hive.initFlutter();
  offlineReportsBox = await Hive.openBox('offline_reports');
  print('Initialized Hive box for offline reports');

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

  // Cek apakah aplikasi dibuka dari notifikasi saat tertutup
  RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();

  runApp(MyApp(initialMessage: initialMessage));
}

class MyApp extends StatefulWidget {
  final String? userRole;
  final RemoteMessage? initialMessage;

  const MyApp({super.key, this.userRole, this.initialMessage});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isAppReady = false;
  RemoteMessage? _pendingNotification;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Tandai aplikasi siap setelah render pertama
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isAppReady = true;
      });

      // Proses notifikasi tertunda setelah app siap
      _processNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Tambahkan log untuk membantu debug
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log('App lifecycle state changed: $state');
    log('Context available: ${navigatorKey.currentContext != null}');

    if (state == AppLifecycleState.resumed) {
      log('App resumed, checking for pending notifications');

      // Beri waktu lebih lama untuk context tersedia
      Future.delayed(const Duration(milliseconds: 1000), () {
        final context = navigatorKey.currentContext;
        log('Context after resume delay: ${context != null ? "available" : "still null"}');

        if (_pendingNotification != null && context != null) {
          log('Processing pending notification after app resumed');
          handleNotificationClick(_pendingNotification!, context);
          _pendingNotification = null;
        } else if (_pendingNotification != null) {
          log('Still no context after resume, scheduling another retry');

          // Retry dengan interval lebih lama
          Future.delayed(const Duration(milliseconds: 2000), () {
            final retryContext = navigatorKey.currentContext;
            if (_pendingNotification != null && retryContext != null) {
              log('Context available after second retry');
              handleNotificationClick(_pendingNotification!, retryContext);
              _pendingNotification = null;
            } else {
              log('Failed to get context after multiple retries');
            }
          });
        }

        // Sinkronisasi laporan offline saat aplikasi kembali aktif
        _syncOfflineReports(context);
      });
    }
  }

  // Method untuk sinkronisasi laporan offline
  void _syncOfflineReports(BuildContext? context) {
    if (context != null) {
      try {
        // Periksa apakah ada laporan offline yang perlu disinkronkan
        getIt<GetOfflineReportsUseCase>().call().then((reports) {
          if (reports.isNotEmpty) {
            print('Found ${reports.length} offline reports to sync');
            context.read<ReportBloc>().add(SyncOfflineReportsEvent());
          }
        });
      } catch (e) {
        print('Error checking offline reports: $e');
      }
    }
  }

  // Proses notifikasi tertunda dan initialMessage
  void _processNotifications() async {
    // Beri waktu tambahan untuk memastikan MaterialApp selesai diinisialisasi
    await Future.delayed(const Duration(milliseconds: 1000));

    // Proses initialMessage jika ada
    if (widget.initialMessage != null) {
      print(
          'Processing initial message: ${widget.initialMessage?.notification?.title}');
      _processNotificationMessage(widget.initialMessage!);
    }

    // Proses notifikasi tertunda jika ada
    if (_pendingNotification != null) {
      print(
          'Processing pending notification: ${_pendingNotification?.notification?.title}');
      _processNotificationMessage(_pendingNotification!);
      _pendingNotification = null;
    }
  }

  // Helper untuk memproses pesan notifikasi
  void _processNotificationMessage(RemoteMessage message) {
    // Tunggu sedikit untuk memastikan navigatorKey.currentContext tersedia
    Future.delayed(const Duration(milliseconds: 500), () {
      if (navigatorKey.currentContext != null) {
        handleNotificationClick(message, navigatorKey.currentContext);
      } else {
        print('Navigator context still null, saving notification for later');
        _pendingNotification = message;

        // Retry setelah delay tambahan jika masih null
        Future.delayed(const Duration(seconds: 1), () {
          if (navigatorKey.currentContext != null &&
              _pendingNotification != null) {
            handleNotificationClick(
                _pendingNotification!, navigatorKey.currentContext);
            _pendingNotification = null;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // AuthBloc - untuk otentikasi
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(
            repository: getIt<AuthRepository>(),
          )..add(CheckAuthStatus()),
        ),

        // PatrolBloc - untuk fitur patroli
        BlocProvider<PatrolBloc>(
          create: (context) {
            final bloc = PatrolBloc(
              repository: getIt<RouteRepository>(),
            );
            bloc.emit(PatrolLoading());
            return bloc;
          },
        ),

        // AdminBloc - untuk fitur admin (satu instance saja)
        BlocProvider<AdminBloc>(
          create: (context) {
            final bloc = AdminBloc(
              repository: getIt<RouteRepository>(),
            );
            // Load semua data yang diperlukan
            bloc.add(LoadAllClusters());
            bloc.add(LoadAllTasks());
            bloc.add(LoadOfficersAndVehicles());
            return bloc;
          },
          lazy: false, // Initialize immediately
        ),

        // ReportBloc - untuk fitur pelaporan dengan dukungan offline
        BlocProvider<ReportBloc>(
          create: (context) => ReportBloc(
            createReportUseCase: getIt<CreateReportUseCase>(),
            syncOfflineReportsUseCase: getIt<SyncOfflineReportsUseCase>(),
            getOfflineReportsUseCase: getIt<GetOfflineReportsUseCase>(),
          ),
        ),
        BlocProvider<SurveyBloc>(
          create: (context) => SurveyBloc(
            repository:
                getIt<SurveyRepository>(), 
          ),
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          print('Current auth state: $state'); // Debug print
          return MaterialApp(
            navigatorKey: navigatorKey, // Tambahkan navigator key di sini
            title: 'Live Tracking App',
            theme: ThemeData(
              scaffoldBackgroundColor: neutralWhite,
              primaryColor: kbpBlue900,
              colorScheme:
                  ColorScheme.fromSwatch().copyWith(primary: kbpBlue900),
              fontFamily: 'Plus Jakarta Sans',
            ),
            home: (state is AuthAuthenticated)
                ? MainNavigationScreen(userRole: widget.userRole ?? 'User')
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}
