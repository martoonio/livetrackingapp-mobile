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
import 'package:livetrackingapp/presentation/report/bloc/report_bloc.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_event.dart';
import 'package:livetrackingapp/presentation/survey/bloc/survey_bloc.dart';
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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

late Box offlineReportsBox;

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
      databaseReference: FirebaseDatabase.instance.ref(),
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
    print('Location permission granted');
  } else if (status.isDenied) {
    print('Location permission denied');
  } else if (status.isPermanentlyDenied) {
    print('Location permission permanently denied');
    await openAppSettings();
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
    await openAppSettings();
  }
}

Future<void> initializeApp() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Future.delayed(const Duration(seconds: 1));

  await initializeDateFormatting('id_ID', null);

  await Hive.initFlutter();
  offlineReportsBox = await Hive.openBox('offline_reports');
  print('Initialized Hive box for offline reports');

  if (FirebaseAuth.instance.currentUser != null) {
    try {
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
      return null;
    }

    final userRef = FirebaseDatabase.instance.ref('users/${user.uid}');
    final snapshot = await userRef.get();

    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      return data['role'] as String?;
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
      setState(() {
      });

      _processNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log('App lifecycle state changed: $state');
    log('Context available: ${navigatorKey.currentContext != null}');

    if (state == AppLifecycleState.resumed) {
      log('App resumed, checking for pending notifications');

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
      });
    }
  }

  // Method untuk sinkronisasi laporan offline
  void _syncOfflineReports(BuildContext? context) {
    if (context != null) {
      try {
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

  void _processNotifications() async {
    await Future.delayed(const Duration(milliseconds: 1000));

    if (widget.initialMessage != null) {
      print(
          'Processing initial message: ${widget.initialMessage?.notification?.title}');
      _processNotificationMessage(widget.initialMessage!);
    }

    if (_pendingNotification != null) {
      print(
          'Processing pending notification: ${_pendingNotification?.notification?.title}');
      _processNotificationMessage(_pendingNotification!);
      _pendingNotification = null;
    }
  }

  void _processNotificationMessage(RemoteMessage message) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (navigatorKey.currentContext != null) {
        handleNotificationClick(message, navigatorKey.currentContext);
      } else {
        print('Navigator context still null, saving notification for later');
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
          print('Current auth state: $state');
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
