import 'dart:developer';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:livetrackingapp/data/repositories/report_repositoryImpl.dart';
import 'package:livetrackingapp/data/repositories/survey_repositoryImpl.dart';
import 'package:livetrackingapp/data/source/firebase_survey_datasource.dart';
import 'package:livetrackingapp/domain/repositories/report_repository.dart';
import 'package:livetrackingapp/domain/repositories/survey_repository.dart';
import 'package:livetrackingapp/domain/usecases/report_usecase.dart';
import 'package:livetrackingapp/domain/usecases/survey_usecase.dart';
import 'package:livetrackingapp/firebase_options.dart';
import 'package:livetrackingapp/main_nav_screen.dart';
import 'package:livetrackingapp/notification_utils.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/auth/login_screen.dart';
import 'package:livetrackingapp/presentation/patrol/services/local_patrol_service.dart';
import 'package:livetrackingapp/presentation/patrol/services/sync_service.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_bloc.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_event.dart';
import 'package:livetrackingapp/presentation/survey/bloc/survey_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livetrackingapp/data/repositories/route_repositoryImpl.dart';
// NEW IMPORT: Battery monitoring
import 'package:battery_plus/battery_plus.dart';
import 'data/repositories/auth_repositoryImpl.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/route_repository.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/patrol/services/local_patrol_data.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';
import 'presentation/component/utils.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
export 'package:livetrackingapp/main.dart' show navigatorKey;

final getIt = GetIt.instance;
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

StreamSubscription<dynamic>? _connectivitySubscription;

late Box offlineReportsBox;

// UPDATE: Battery service dengan Firestore integration
class BatteryService {
  static final Battery _battery = Battery();
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Timer? _batteryTimer;
  static StreamSubscription<BatteryState>? _batteryStateSubscription;
  static bool _isInitialized = false;

  static Future<void> initializeBatteryMonitoring() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Prevent multiple initialization
    if (_isInitialized) {
      log('Battery monitoring already initialized');
      return;
    }

    try {
      // Test if battery plugin is available
      await _battery.batteryLevel;

      // Update battery level immediately
      await _updateBatteryLevel();

      // Set up periodic battery level updates (every 5 minutes)
      _batteryTimer?.cancel();
      _batteryTimer = Timer.periodic(
        const Duration(minutes: 5),
        (timer) => _updateBatteryLevel(),
      );

      // Listen to battery state changes (charging/discharging)
      _batteryStateSubscription?.cancel();
      _batteryStateSubscription = _battery.onBatteryStateChanged.listen(
        (BatteryState state) {
          _updateBatteryState(state);
        },
        onError: (error) {
          log('Error in battery state subscription: $error');
        },
      );

      _isInitialized = true;
      log('Battery monitoring initialized successfully');
    } catch (e) {
      log('Error initializing battery monitoring: $e');
      // Don't throw error, just log it
      _isInitialized = false;
    }
  }

  static Future<void> _updateBatteryLevel() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Use try-catch for each battery operation
      int? batteryLevel;
      BatteryState? batteryState;

      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (e) {
        log('Error getting battery level: $e');
        batteryLevel = null;
      }

      try {
        batteryState = await _battery.batteryState;
      } catch (e) {
        log('Error getting battery state: $e');
        batteryState = null;
      }

      // Get user's info from Firestore
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final userRole = userData['role'] as String?;

        // Prepare update data
        final updateData = <String, dynamic>{
          'last_battery_update': FieldValue.serverTimestamp(),
          'is_online': true,
        };

        // Only add battery data if available
        if (batteryLevel != null) {
          updateData['battery_level'] = batteryLevel;
        }
        if (batteryState != null) {
          updateData['battery_state'] = batteryState.toString().split('.').last;
        }

        // Update user's battery info
        await _firestore.collection('users').doc(user.uid).update(updateData);

        // If user is patrol officer in a cluster, also update cluster's officers data
        if (userRole == 'patrol') {
          final clusterId = userData['clusterId'] as String?;
          if (clusterId != null) {
            // Get cluster document to update officer info
            final clusterDoc =
                await _firestore.collection('users').doc(clusterId).get();

            if (clusterDoc.exists) {
              final clusterData = clusterDoc.data()!;
              final officers = List<Map<String, dynamic>>.from(
                  clusterData['officers'] ?? []);

              // Find and update this officer's data
              final officerIndex =
                  officers.indexWhere((officer) => officer['id'] == user.uid);
              if (officerIndex != -1) {
                officers[officerIndex] = {
                  ...officers[officerIndex],
                  ...updateData,
                };

                await _firestore.collection('users').doc(clusterId).update({
                  'officers': officers,
                  'updated_at': FieldValue.serverTimestamp(),
                });
              }
            }
          }
        }

        log('Battery updated: ${batteryLevel ?? "unknown"}% - ${batteryState?.toString() ?? "unknown"}');
      }
    } catch (e) {
      log('Error updating battery level: $e');
    }
  }

  static Future<void> _updateBatteryState(BatteryState state) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final userRole = userData['role'] as String?;

        final updateData = {
          'battery_state': state.toString().split('.').last,
          'last_battery_update': FieldValue.serverTimestamp(),
        };

        // Update user's battery state
        await _firestore.collection('users').doc(user.uid).update(updateData);

        // If patrol user, also update cluster
        if (userRole == 'patrol') {
          final clusterId = userData['clusterId'] as String?;
          if (clusterId != null) {
            final clusterDoc =
                await _firestore.collection('users').doc(clusterId).get();

            if (clusterDoc.exists) {
              final clusterData = clusterDoc.data()!;
              final officers = List<Map<String, dynamic>>.from(
                  clusterData['officers'] ?? []);

              final officerIndex =
                  officers.indexWhere((officer) => officer['id'] == user.uid);
              if (officerIndex != -1) {
                officers[officerIndex] = {
                  ...officers[officerIndex],
                  ...updateData,
                };

                await _firestore.collection('users').doc(clusterId).update({
                  'officers': officers,
                  'updated_at': FieldValue.serverTimestamp(),
                });
              }
            }
          }
        }
      }
    } catch (e) {
      log('Error updating battery state: $e');
    }
  }

  static void dispose() {
    try {
      _batteryTimer?.cancel();
      _batteryTimer = null;

      _batteryStateSubscription?.cancel();
      _batteryStateSubscription = null;

      _isInitialized = false;
      log('Battery monitoring disposed');
    } catch (e) {
      log('Error disposing battery monitoring: $e');
    }
  }
}

void setupLocator() {
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
      firestore: FirebaseFirestore.instance, // Changed from databaseReference
      offlineReportsBox: offlineReportsBox,
    ),
  );

  getIt.registerLazySingleton<CreateReportUseCase>(
    () => CreateReportUseCase(getIt<ReportRepository>()),
  );

  getIt.registerLazySingleton<SyncOfflineReportsUseCase>(
    () => SyncOfflineReportsUseCase(getIt<ReportRepository>()),
  );

  getIt.registerLazySingleton<GetOfflineReportsUseCase>(
    () => GetOfflineReportsUseCase(getIt<ReportRepository>()),
  );

  getIt.registerLazySingleton<FirebaseSurveyDataSource>(
    () => FirebaseSurveyDataSource(),
  );

  getIt.registerLazySingleton<SurveyRepository>(
    () => SurveyRepositoryImpl(dataSource: getIt<FirebaseSurveyDataSource>()),
  );

  getIt.registerLazySingleton<GetActiveSurveysUseCase>(
    () => GetActiveSurveysUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<GetSurveyDetailsUseCase>(
    () => GetSurveyDetailsUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<SubmitSurveyResponseUseCase>(
    () => SubmitSurveyResponseUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<GetUserSurveyResponseUseCase>(
    () => GetUserSurveyResponseUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<GetAllSurveysUseCase>(
    () => GetAllSurveysUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<CreateSurveyUseCase>(
    () => CreateSurveyUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<UpdateSurveyUseCase>(
    () => UpdateSurveyUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<DeleteSurveyUseCase>(
    () => DeleteSurveyUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<GetSurveyResponsesUseCase>(
    () => GetSurveyResponsesUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<GetSurveyResponsesSummaryUseCase>(
    () => GetSurveyResponsesSummaryUseCase(getIt<SurveyRepository>()),
  );
  getIt.registerLazySingleton<UpdateSurveyStatusUseCase>(
    () => UpdateSurveyStatusUseCase(getIt<SurveyRepository>()),
  );
}

Future<void> requestLocationPermission() async {
  final status = await Permission.location.request();
  if (status.isGranted) {
    log('Location permission granted');
  } else if (status.isDenied) {
    log('Location permission denied');
  } else if (status.isPermanentlyDenied) {
    await openAppSettings();
  }
}

Future<void> requestNotificationPermission() async {
  final status = await Permission.notification.request();
  if (status.isGranted) {
    log('Notification permission granted');
  } else if (status.isDenied) {
    log('Notification permission denied');
  } else if (status.isPermanentlyDenied) {
    await openAppSettings();
  }
}

Future<void> initializeApp() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Future.delayed(const Duration(seconds: 1));

  await initializeDateFormatting('id_ID', null);

  await Hive.initFlutter();

  try {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(LocalPatrolDataAdapter());
      print('✅ LocalPatrolDataAdapter registered');
    } else {
      print('✅ LocalPatrolDataAdapter already registered');
    }
  } catch (e) {
    print('❌ Error registering Hive adapter: $e');
  }

  // Initialize local patrol service with retry
  bool serviceInitialized = false;
  int retryCount = 0;

  while (!serviceInitialized && retryCount < 3) {
    try {
      await LocalPatrolService.init();
      serviceInitialized = true;
      print('✅ LocalPatrolService initialized successfully');
    } catch (e) {
      retryCount++;
      print('❌ LocalPatrolService init attempt $retryCount failed: $e');

      if (retryCount < 3) {
        await Future.delayed(Duration(seconds: 1));
      } else {
        print('⚠️ LocalPatrolService failed to initialize after 3 attempts');
        // Continue without local patrol service - app should still work
      }
    }
  }

  // Initialize offline reports box
  try {
    offlineReportsBox = await Hive.openBox('offline_reports');
    print('✅ Offline reports box opened');
  } catch (e) {
    print('❌ Error opening offline reports box: $e');
    // Try with a backup name
    try {
      offlineReportsBox = await Hive.openBox('offline_reports_backup');
      print('✅ Offline reports backup box opened');
    } catch (backupError) {
      print('❌ Failed to open backup box: $backupError');
      throw Exception('Failed to initialize offline storage');
    }
  }

  // Enable Firestore offline persistence if user is authenticated
  if (FirebaseAuth.instance.currentUser != null) {
    try {
      // Enable offline persistence for Firestore
      await FirebaseFirestore.instance
          .enablePersistence(const PersistenceSettings(synchronizeTabs: true));
      log('✅ Firestore offline persistence enabled');
    } catch (e) {
      log('⚠️ Firestore persistence already enabled or failed: $e');
    }
  }

  await requestLocationPermission();
  await requestNotificationPermission();

  // Initialize battery monitoring with delay to ensure all plugins are ready
  Future.delayed(const Duration(seconds: 3), () {
    BatteryService.initializeBatteryMonitoring();
  });
}

Timer? _periodicSyncTimer;

void _startPeriodicSync() {
  _periodicSyncTimer = Timer.periodic(Duration(minutes: 2), (timer) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity != ConnectivityResult.none) {
        final stats = LocalPatrolService.getStatistics();
        if (stats['unsynced']! > 0) {
          print('🔄 Periodic sync: ${stats['unsynced']} unsynced patrols');
          await SyncService.syncUnsyncedPatrols();

          // Log results
          final newStats = LocalPatrolService.getStatistics();
          print(
              '📊 Post-periodic sync: ${newStats['unsynced']} unsynced patrols remaining');
        }
      }
    } catch (e) {
      print('❌ Periodic sync error: $e');
    }
  });
}

Future<String?> getUserRole() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    // Use Firestore instead of Realtime Database
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists) {
      final data = userDoc.data()!;
      return data['role'] as String?;
    } else {
      return null;
    }
  } catch (e) {
    log('Error getting user role: $e');
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeApp();
  await initNotification();
  setupLocator();

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
  RemoteMessage? _pendingNotification;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {});

      _processNotifications();
    });

    // Listen to auth state changes to manage battery monitoring
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        // User signed in, start battery monitoring with delay
        Future.delayed(const Duration(seconds: 2), () {
          BatteryService.initializeBatteryMonitoring();
        });
      } else {
        // User signed out, stop battery monitoring
        BatteryService.dispose();
      }
    });

    _initConnectivityListener();

    _performInitialSync();
    _startPeriodicSync();
  }

  Future<void> _performInitialSync() async {
    await Future.delayed(Duration(seconds: 2)); // Wait for app to stabilize

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity != ConnectivityResult.none) {
      final stats = LocalPatrolService.getStatistics();
      if (stats['unsynced']! > 0) {
        print('📱 Found ${stats['unsynced']} unsynced patrols on app start');
        SyncService.syncUnsyncedPatrols();
      }
    }
  }

  ConnectivityResult _previousConnectivity = ConnectivityResult.none;

  void _handleConnectivityChange(ConnectivityResult result) {
    // If we just got back online
    if (_previousConnectivity == ConnectivityResult.none &&
        result != ConnectivityResult.none) {
      print('🌐 Internet connection restored');
      SyncService.onConnectivityRestored();
    }

    _previousConnectivity = result;
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        Future.delayed(Duration(seconds: 2), () {
          SyncService.onConnectivityRestored();
        });
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Clean up battery monitoring
    BatteryService.dispose();
    // Cancel connectivity subscription
    _connectivitySubscription?.cancel();
    // Cancel periodic sync timer
    _periodicSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log('App lifecycle state changed: $state');

    if (state == AppLifecycleState.resumed) {
      log('App resumed, checking for pending notifications');
      Future.delayed(Duration(seconds: 1), () async {
        try {
          final connectivity = await Connectivity().checkConnectivity();
          if (connectivity != ConnectivityResult.none) {
            print('📱 App resumed, performing immediate sync...');
            await SyncService.syncUnsyncedPatrols();
          }
        } catch (e) {
          print('❌ Resume sync error: $e');
        }
      });

      // Restart battery monitoring when app resumes with delay
      Future.delayed(const Duration(seconds: 1), () {
        BatteryService.initializeBatteryMonitoring();
      });

      Future.delayed(const Duration(milliseconds: 1000), () {
        final context = navigatorKey.currentContext;
        log('Context after resume delay: ${context != null ? "available" : "still null"}');

        if (_pendingNotification != null && context != null) {
          log('Processing pending notification after app resumed');
          handleNotificationClick(_pendingNotification!, context);
          _pendingNotification = null;
        } else if (_pendingNotification != null) {
          log('Still no context after resume, scheduling another retry');

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

        _syncOfflineReports(context);
        if (state == AppLifecycleState.resumed) {
          print('📱 App resumed, checking for sync');
          _performInitialSync();
        }
      });
    } else if (state == AppLifecycleState.paused) {
      log('App paused, battery monitoring continues in background');
      Future.delayed(Duration(milliseconds: 500), () async {
        try {
          final connectivity = await Connectivity().checkConnectivity();
          if (connectivity != ConnectivityResult.none) {
            print('📱 App pausing, performing final sync...');
            await SyncService.syncUnsyncedPatrols();
          }
        } catch (e) {
          print('❌ Pause sync error: $e');
        }
      });
    } else if (state == AppLifecycleState.detached) {
      // App is being terminated, dispose battery monitoring
      BatteryService.dispose();
    }
  }

  // Method untuk sinkronisasi laporan offline
  void _syncOfflineReports(BuildContext? context) {
    if (context != null) {
      try {
        getIt<GetOfflineReportsUseCase>().call().then((reports) {
          if (reports.isNotEmpty) {
            context.read<ReportBloc>().add(SyncOfflineReportsEvent());
          }
        });
      } catch (e) {
        log('Error syncing offline reports: $e');
      }
    }
  }

  void _processNotifications() async {
    await Future.delayed(const Duration(milliseconds: 1000));

    if (widget.initialMessage != null) {
      _processNotificationMessage(widget.initialMessage!);
    }

    if (_pendingNotification != null) {
      _processNotificationMessage(_pendingNotification!);
      _pendingNotification = null;
    }
  }

  void _processNotificationMessage(RemoteMessage message) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (navigatorKey.currentContext != null) {
        handleNotificationClick(message, navigatorKey.currentContext);
      } else {
        _pendingNotification = message;

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
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(
            repository: getIt<AuthRepository>(),
          )..add(CheckAuthStatus()),
        ),
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
          create: (context) {
            final bloc = AdminBloc(
              repository: getIt<RouteRepository>(),
            );
            bloc.add(const LoadAllClusters());
            bloc.add(const LoadAllTasks());
            bloc.add(const LoadOfficersAndVehicles());
            return bloc;
          },
          lazy: false,
        ),
        BlocProvider<ReportBloc>(
          create: (context) => ReportBloc(
            createReportUseCase: getIt<CreateReportUseCase>(),
            syncOfflineReportsUseCase: getIt<SyncOfflineReportsUseCase>(),
            getOfflineReportsUseCase: getIt<GetOfflineReportsUseCase>(),
          ),
        ),
        BlocProvider<SurveyBloc>(
          create: (context) => SurveyBloc(
            getActiveSurveysUseCase: getIt<GetActiveSurveysUseCase>(),
            getSurveyDetailsUseCase: getIt<GetSurveyDetailsUseCase>(),
            submitSurveyResponseUseCase: getIt<SubmitSurveyResponseUseCase>(),
            getAllSurveysUseCase: getIt<GetAllSurveysUseCase>(),
            createSurveyUseCase: getIt<CreateSurveyUseCase>(),
            updateSurveyUseCase: getIt<UpdateSurveyUseCase>(),
            deleteSurveyUseCase: getIt<DeleteSurveyUseCase>(),
            getSurveyResponsesUseCase: getIt<GetSurveyResponsesUseCase>(),
            getSurveyResponsesSummaryUseCase:
                getIt<GetSurveyResponsesSummaryUseCase>(),
            updateSurveyStatusUseCase: getIt<UpdateSurveyStatusUseCase>(),
            getUserSurveyResponseUseCase: getIt<GetUserSurveyResponseUseCase>(),
          ),
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Live Tracking App',
            theme: ThemeData(
              scaffoldBackgroundColor: neutralWhite,
              primaryColor: kbpBlue900,
              colorScheme:
                  ColorScheme.fromSwatch().copyWith(primary: kbpBlue900),
              fontFamily: 'Plus Jakarta Sans',
            ),
            home: (state is AuthAuthenticated)
                ? MainNavigationScreen(userRole: widget.userRole ?? 'patrol')
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}
