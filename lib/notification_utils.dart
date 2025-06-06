import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/admin_map_screen.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/report.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/firebase_options.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:livetrackingapp/main_nav_screen.dart';

import 'dart:developer';

import 'package:livetrackingapp/map_screen.dart';
import 'package:livetrackingapp/presentation/routing/bloc/patrol_bloc.dart';
import 'package:livetrackingapp/main.dart' show navigatorKey;

import 'presentation/admin/patrol_history_screen.dart';
import 'presentation/component/utils.dart';

FirebaseMessaging fMessaging = FirebaseMessaging.instance;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
const String channelId = 'livetracking';
const String channelName = 'Live Location KBP';
const String channelDescription = 'For Showing Current Location Notification';

Future<void> showForegroundNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidNotificationDetails =
      AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: channelDescription,
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
  );

  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidNotificationDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title,
    message.notification?.body,
    notificationDetails,
  );
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

// Tambahkan fungsi ini untuk menunggu context tersedia
Future<BuildContext?> _waitForContext(
    {int maxAttempts = 20, int delayMs = 200}) async {
  int attempts = 0;
  BuildContext? context;

  while (context == null && attempts < maxAttempts) {
    context = navigatorKey.currentContext;
    if (context != null) return context;

    attempts++;
    log('Waiting for context, attempt $attempts of $maxAttempts');
    await Future.delayed(Duration(milliseconds: delayMs));
  }

  return context; // null jika masih tidak tersedia setelah percobaan maksimum
}

// Modifikasi handleNotificationClick untuk menggunakan fungsi ini
void handleNotificationClick(
    RemoteMessage message, BuildContext? context) async {
  log('Handling notification click: ${message.data}');
  final data = message.data;
  final notificationType = data['type'];

  // Simpan pesan notifikasi untuk diproses nanti jika diperlukan
  _pendingNotification = message;

  // Coba gunakan context yang diberikan atau dari navigatorKey
  BuildContext? navigatorContext = context ?? navigatorKey.currentContext;

  // Jika context tidak tersedia, tunggu dengan sistem polling
  if (navigatorContext == null) {
    log('Context not available immediately, waiting...');
    navigatorContext = await _waitForContext();

    // Jika masih null setelah menunggu
    if (navigatorContext == null) {
      log('Context not available after maximum retry attempts');
      // Notification akan diproses oleh AppLifecycleListener
      return;
    }
  }

  // Proses notifikasi karena context tersedia
  log('Context available, processing notification');
  _processNotificationWithContext(notificationType, data, navigatorContext);
  _pendingNotification = null;
}

// Pisahkan logika processing notifikasi untuk lebih rapi
void _processNotificationWithContext(String? notificationType,
    Map<String, dynamic> data, BuildContext context) async {
  switch (notificationType) {
    case 'patrol_task':
      final taskId = data['task_id'];
      if (taskId != null) {
        try {
          final taskSnapshot =
              await FirebaseDatabase.instance.ref('tasks/$taskId').get();

          if (taskSnapshot.exists) {
            final taskData = taskSnapshot.value as Map<dynamic, dynamic>;

            // Konversi ke objek PatrolTask
            final task = PatrolTask(
              taskId: taskId,
              userId: taskData['userId']?.toString() ?? '',
              // vehicleId: taskData['vehicleId']?.toString() ?? '',
              status: taskData['status']?.toString() ?? '',
              assignedStartTime: _parseDateTime(taskData['assignedStartTime']),
              assignedEndTime: _parseDateTime(taskData['assignedEndTime']),
              startTime: _parseDateTime(taskData['startTime']),
              endTime: _parseDateTime(taskData['endTime']),
              distance: taskData['distance'] != null
                  ? (taskData['distance'] as num).toDouble()
                  : null,
              assignedRoute: taskData['assigned_route'] != null
                  ? (taskData['assigned_route'] as List)
                      .map((point) => (point as List)
                          .map((coord) => (coord as num).toDouble())
                          .toList())
                      .toList()
                  : null,
              routePath: taskData['route_path'] != null
                  ? Map<String, dynamic>.from(taskData['route_path'] as Map)
                  : null,
              clusterId: taskData['clusterId']?.toString() ?? '',
              createdAt:
                  _parseDateTime(taskData['createdAt']) ?? DateTime.now(),
            );

            // Navigasi ke MapScreen
            navigateToMapFromNotification(context, task);
          } else {
            log('Task not found: $taskId');
          }
        } catch (e) {
          log('Error fetching task data: $e');
        }
      }
      break;

    case 'missed_checkpoints':
      final taskId = data['task_id'];
      final officerId = data['officer_id'];
      final officerName = data['officer_name'];
      final clusterName = data['cluster_name'];

      // Parse lokasi titik yang terlewat
      List<LatLng> missedPoints = [];
      if (data['missed_checkpoints'] != null) {
        try {
          // Parse string JSON menjadi list
          final List<dynamic> checkpoints =
              json.decode(data['missed_checkpoints']);

          for (var checkpoint in checkpoints) {
            // Ekstrak latitude dan longitude
            final double lat = (checkpoint['latitude'] as num).toDouble();
            final double lng = (checkpoint['longitude'] as num).toDouble();
            missedPoints.add(LatLng(lat, lng));
          }
        } catch (e) {}
      }

      // Navigasi ke AdminMapScreen
      navigateToAdminMapForMissedCheckpoints(
          context, taskId, officerId, missedPoints);
      break;

    // --- FITUR BARU: PENANGANAN NOTIFIKASI MOCK LOCATION ---
    case 'mock_location_detection':
      final taskId = data['task_id'];
      final lat = double.tryParse(data['latitude'] ?? '');
      final lng = double.tryParse(data['longitude'] ?? '');
      final officerName = data['officer_name'];
      final clusterName = data['cluster_name'];

      if (taskId != null && lat != null && lng != null) {
        navigateToAdminMapForMockLocation(
            context, taskId, lat, lng, officerName, clusterName);
      } else {
        log('Invalid mock location data received: $data');
      }
      break;
    // --- AKHIR FITUR BARU ---

    // --- FITUR BARU: PENANGANAN NOTIFIKASI LAPORAN ---
    case 'new_report':
      final reportId = data['report_id'];
      final patrolTaskId = data['patrol_task_id'];
      final reportTitle = data['report_title'];
      final reportDescription = data['report_description'];
      final latitude = double.tryParse(data['latitude'] ?? '');
      final longitude = double.tryParse(data['longitude'] ?? '');
      final officerName = data['officer_name'];
      final clusterName = data['cluster_name'];
      final reportTimeStr = data['report_time'];
      final photoUrl = data['photo_url'];

      if (reportId != null && patrolTaskId != null) {
        navigateToReportDetail(
          context: context,
          reportId: reportId,
          patrolTaskId: patrolTaskId,
          reportTitle: reportTitle ?? 'Laporan Tanpa Judul',
          reportDescription: reportDescription ?? '',
          latitude: latitude ?? 0.0,
          longitude: longitude ?? 0.0,
          officerName: officerName ?? 'Petugas',
          clusterName: clusterName ?? 'Tatar',
          reportTimeStr: reportTimeStr,
          photoUrl: photoUrl,
        );
      } else {
        log('Invalid report notification data received: $data');
      }
      break;
    // --- AKHIR FITUR BARU ---

    default:
      log('Unknown notification type: $notificationType');
  }
}

// Simpan data notifikasi untuk diproses nanti
RemoteMessage? _pendingNotification;
void _saveNotificationDataForLaterProcessing(RemoteMessage message) {
  _pendingNotification = message;
}

// Fungsi untuk navigasi ke MapScreen
void navigateToMapFromNotification(BuildContext context, PatrolTask task) {
  try {
    // Tambahkan log untuk debugging
    log('Navigating to MapScreen with task: ${task.taskId}');

    // Cek apakah context.mounted untuk Flutter 3.x
    if (!context.mounted) {
      log('Context is not mounted, cannot navigate');
      return;
    }

    // Menggunakan try-catch untuk mengatasi error navigasi
    try {
      // Tutup semua dialog yang mungkin terbuka
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
    } catch (e) {
      log('Error popping routes: $e, continuing with navigation');
    }

    // Navigasi ke MapScreen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          task: task,
          onStart: () {
            context.read<PatrolBloc>().add(StartPatrol(
                  task: task,
                  startTime: DateTime.now(),
                ));
          },
        ),
      ),
    );

    log('Navigation to MapScreen successful');
  } catch (e) {
    log('Failed to navigate to MapScreen: $e');
  }
}

void navigateToAdminMapForMissedCheckpoints(BuildContext context, String taskId,
    String officerId, List<LatLng> missedPoints) async {
  try {
    // Tutup semua dialog yang mungkin terbuka
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);

    // Dapatkan detail task terlebih dahulu
    final taskSnapshot =
        await FirebaseDatabase.instance.ref('tasks').child(taskId).get();

    if (!taskSnapshot.exists) {
      log('Patrol task not found: $taskId');
      // Tampilkan pesan error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Detail patroli tidak ditemukan'),
          backgroundColor: dangerR300,
        ),
      );
      return;
    }

    // Konversi data ke PatrolTask
    final taskData = taskSnapshot.value as Map<dynamic, dynamic>;
    final task = PatrolTask(
      taskId: taskId,
      userId: taskData['userId']?.toString() ?? officerId,
      // vehicleId: taskData['vehicleId']?.toString() ?? '',
      status: taskData['status']?.toString() ?? '',
      assignedStartTime: _parseDateTime(taskData['assignedStartTime']),
      assignedEndTime: _parseDateTime(taskData['assignedEndTime']),
      startTime: _parseDateTime(taskData['startTime']),
      endTime: _parseDateTime(taskData['endTime']),
      distance: taskData['distance'] != null
          ? (taskData['distance'] as num).toDouble()
          : null,
      assignedRoute: taskData['assigned_route'] != null
          ? (taskData['assigned_route'] as List)
              .map((point) => (point as List)
                  .map((coord) => (coord as num).toDouble())
                  .toList())
              .toList()
          : null,
      routePath: taskData['route_path'] != null
          ? Map<String, dynamic>.from(taskData['route_path'] as Map)
          : null,
      clusterId: taskData['clusterId']?.toString() ?? '',
      createdAt: _parseDateTime(taskData['createdAt']) ?? DateTime.now(),
      mockLocationDetected: taskData['mockLocationDetected'] ?? false,
      mockLocationCount: taskData['mockLocationCount'] != null
          ? (taskData['mockLocationCount'] as num).toInt()
          : 0,
      initialReportPhotoUrl: taskData['initialReportPhotoUrl']?.toString(),
      initialReportNote: taskData['initialReportNote']?.toString(),
      initialReportTime: _parseDateTime(taskData['initialReportTime']),
      finalReportPhotoUrl: taskData['finalReportPhotoUrl']?.toString(),
      finalReportNote: taskData['finalReportNote']?.toString(),
      finalReportTime: _parseDateTime(taskData['finalReportTime']),
      timeliness: taskData['timeliness']?.toString(),
    );

    // Navigasi ke PatrolHistoryScreen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatrolHistoryScreen(
          task: task,
        ),
      ),
    );

    log('Navigation to PatrolHistoryScreen successful');
  } catch (e) {
    log('Failed to navigate to PatrolHistoryScreen: $e');
    // Tampilkan pesan error
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(
    //     content: Text('Gagal membuka detail patroli: $e'),
    //     backgroundColor: dangerR300,
    //   ),
    // );
  }
}

// --- FITUR BARU: NAVIGASI UNTUK MOCK LOCATION ---
void navigateToAdminMapForMockLocation(BuildContext context, String taskId,
    double lat, double lng, String? officerName, String? clusterName) async {
  try {
    log('Navigating to AdminMapScreen for mock location: Task $taskId, Lat $lat, Lng $lng');

    // Pastikan kita berada di MainNavigationScreen atau navigasi ke sana
    // Kemudian, panggil metode di MainNavigationScreen untuk mengganti tab dan highlight
    final mainNavState =
        navigatorKey.currentState as MainNavigationScreenState?;
    if (mainNavState != null) {
      // Panggil metode di MainNavigationScreen untuk berpindah tab dan highlight
      mainNavState.goToAdminMapAndHighlight(taskId, lat, lng);
    } else {
      // Jika MainNavigationScreen belum ada di tree (misal dari terminated state)
      // Kita perlu menavigasi ke sana dengan argumen awal
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (ctx) => MainNavigationScreen(
            userRole:
                'commandCenter', // Asumsi role commandCenter untuk notif ini
            initialTabIndex: 0, // AdminMapScreen adalah tab pertama
            highlightedTaskId: taskId,
            highlightedLat: lat,
            highlightedLng: lng,
          ),
        ),
        (route) => false, // Hapus semua rute sebelumnya
      );
    }

    log('Navigation to AdminMapScreen for mock location successful');
  } catch (e) {
    log('Failed to navigate to AdminMapScreen for mock location: $e');
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(
    //     content: Text('Gagal membuka peta admin: $e'),
    //     backgroundColor: dangerR300,
    //   ),
    // );
  }
}
// --- AKHIR FITUR BARU ---

// --- FITUR BARU: NAVIGASI KE DETAIL LAPORAN ---
void navigateToReportDetail({
  required BuildContext context,
  required String reportId,
  required String patrolTaskId,
  required String reportTitle,
  required String reportDescription,
  required double latitude,
  required double longitude,
  required String officerName,
  required String clusterName,
  String? reportTimeStr,
  String? photoUrl,
}) async {
  try {
    log('Navigating to report detail: Report $reportId, Task $patrolTaskId');

    // Tutup semua dialog yang mungkin terbuka
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);

    // Dapatkan detail task terlebih dahulu
    final taskSnapshot =
        await FirebaseDatabase.instance.ref('tasks').child(patrolTaskId).get();

    if (!taskSnapshot.exists) {
      log('Patrol task not found: $patrolTaskId');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Detail patroli tidak ditemukan'),
          backgroundColor: dangerR300,
        ),
      );
      return;
    }

    // Konversi data ke PatrolTask
    final taskData = taskSnapshot.value as Map<dynamic, dynamic>;
    final task = PatrolTask(
      taskId: patrolTaskId,
      userId: taskData['userId']?.toString() ?? '',
      status: taskData['status']?.toString() ?? '',
      assignedStartTime: _parseDateTime(taskData['assignedStartTime']),
      assignedEndTime: _parseDateTime(taskData['assignedEndTime']),
      startTime: _parseDateTime(taskData['startTime']),
      endTime: _parseDateTime(taskData['endTime']),
      distance: taskData['distance'] != null
          ? (taskData['distance'] as num).toDouble()
          : null,
      assignedRoute: taskData['assigned_route'] != null
          ? (taskData['assigned_route'] as List)
              .map((point) => (point as List)
                  .map((coord) => (coord as num).toDouble())
                  .toList())
              .toList()
          : null,
      routePath: taskData['route_path'] != null
          ? Map<String, dynamic>.from(taskData['route_path'] as Map)
          : null,
      clusterId: taskData['clusterId']?.toString() ?? '',
      createdAt: _parseDateTime(taskData['createdAt']) ?? DateTime.now(),
      mockLocationDetected: taskData['mockLocationDetected'] ?? false,
      mockLocationCount: taskData['mockLocationCount'] != null
          ? (taskData['mockLocationCount'] as num).toInt()
          : 0,
      initialReportPhotoUrl: taskData['initialReportPhotoUrl']?.toString(),
      initialReportNote: taskData['initialReportNote']?.toString(),
      initialReportTime: _parseDateTime(taskData['initialReportTime']),
      finalReportPhotoUrl: taskData['finalReportPhotoUrl']?.toString(),
      finalReportNote: taskData['finalReportNote']?.toString(),
      finalReportTime: _parseDateTime(taskData['finalReportTime']),
      timeliness: taskData['timeliness']?.toString(),
    );

    // Ambil detail report dari database
    final reportSnapshot =
        await FirebaseDatabase.instance.ref('reports').child(reportId).get();

    if (!reportSnapshot.exists) {
      log('Report not found: $reportId');
      // Buat objek report sementara dari data notifikasi
      final tempReport = Report(
        id: reportId,
        title: reportTitle,
        description: reportDescription,
        latitude: latitude,
        longitude: longitude,
        timestamp: reportTimeStr != null
            ? DateTime.tryParse(reportTimeStr) ?? DateTime.now()
            : DateTime.now(),
        taskId: patrolTaskId,
        userId: task.userId,
        photoUrl: photoUrl ?? '',
        officerName: officerName,
        clusterName: clusterName,
      );

      // Navigasi ke PatrolHistoryScreen dan show detail
      _navigateToPatrolHistoryWithReport(context, task, tempReport);
      return;
    }

    // Konversi data report
    final reportData = reportSnapshot.value as Map<dynamic, dynamic>;
    final report =
        Report.fromJson(reportId, Map<String, dynamic>.from(reportData));

    // Navigasi ke PatrolHistoryScreen dan show detail
    _navigateToPatrolHistoryWithReport(context, task, report);

    log('Navigation to report detail successful');
  } catch (e) {
    log('Failed to navigate to report detail: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Gagal membuka detail laporan: $e'),
        backgroundColor: dangerR300,
      ),
    );
  }
}

// Fungsi helper untuk navigasi ke PatrolHistoryScreen dengan laporan
void _navigateToPatrolHistoryWithReport(
    BuildContext context, PatrolTask task, Report report) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PatrolHistoryScreen(
        task: task,
      ),
    ),
  );
}
// --- AKHIR FITUR BARU ---

// Helper function untuk parse datetime
DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;

  try {
    if (value is String) {
      if (value.contains('.')) {
        final parts = value.split('.');
        final mainPart = parts[0];
        final microPart = parts[1];
        final cleanMicroPart =
            microPart.length > 6 ? microPart.substring(0, 6) : microPart;
        return DateTime.parse('$mainPart.$cleanMicroPart');
      }
      return DateTime.parse(value);
    } else if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
  } catch (e) {
    log('Error parsing datetime: $value, error: $e');
  }
  return null;
}

Future<void> _bringAppToForeground() async {
  if (Platform.isAndroid) {
    try {
      const platform = MethodChannel('com.example.livetrackingapp/foreground');
      await platform.invokeMethod('bringToForeground');
      log('Requested app to be brought to foreground');
    } catch (e) {
      log('Error bringing app to foreground: $e');
    }
  }
}

// Perbarui fungsi initNotification untuk menambahkan handler
Future<void> initNotification() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    channelId,
    channelName,
    description: channelDescription,
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  // Setup Notification Channel
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Request Notification Permission untuk iOS
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Konfigurasi Local Notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings());

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      final payload = response.payload;
      if (payload != null) {
        try {
          final data = json.decode(payload);
          final RemoteMessage message = RemoteMessage(
            data: Map<String, dynamic>.from(data),
          );
          handleNotificationClick(message, null);
        } catch (e) {
          log('Error processing notification payload: $e');
        }
      }
    },
  );

  // Handle Foreground Messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.notification != null) {
      // Tambahkan payload untuk notifikasi foreground
      final Map<String, dynamic> payload = message.data;
      final String payloadStr = json.encode(payload);

      flutterLocalNotificationsPlugin.show(
        message.hashCode,
        message.notification?.title,
        message.notification?.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: payloadStr,
      );
    }
  });

  // Handle Background Messages
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    // Coba bawa aplikasi ke foreground
    _bringAppToForeground();

    // Simpan notifikasi terlebih dahulu
    _pendingNotification = message;

    // Berikan waktu agar app sepenuhnya di foreground
    Future.delayed(Duration(milliseconds: 1500), () {
      final context = navigatorKey.currentContext;
      if (context != null) {
        handleNotificationClick(message, context);
      } else {
        log('Context not available after bringing to foreground, will retry when app is resumed');
      }
    });
  });

  // Cek apakah aplikasi dibuka dari notifikasi saat tertutup
  RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    log("App opened from terminated state via notification");
    // Simpan pesan untuk diproses setelah MaterialApp diinisialisasi
    Future.delayed(const Duration(seconds: 1), () {
      handleNotificationClick(initialMessage, null);
    });
  }
}

Future<void> getFirebaseMessagingToken(User user) async {
  try {
    // Request notification permission
    await fMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    String? fcmToken;

    if (Platform.isIOS) {
      // For iOS, get APNS token first
      String? apnsToken = await fMessaging.getAPNSToken();

      // Retry if APNS token is null
      if (apnsToken == null) {
        await Future<void>.delayed(const Duration(seconds: 3));
        apnsToken = await fMessaging.getAPNSToken();
      }

      // If APNS token is available, get FCM token
      if (apnsToken != null) {
        fcmToken = await fMessaging.getToken();
        log('iOS FCM Token: $fcmToken');
        log('APNS Token: $apnsToken');
      } else {
        log('Failed to get APNS token after retry');
      }
    } else {
      // For Android and other platforms
      fcmToken = await fMessaging.getToken();
      log('Android FCM Token: $fcmToken');
    }

    // Save FCM token to Realtime Database
    if (fcmToken != null) {
      user.pushToken = fcmToken; // Update user object
      final DatabaseReference userRef =
          FirebaseDatabase.instance.ref('users/${user.id}');
      await userRef.update({'push_token': fcmToken}); // Save to database
      log('Push token saved to Realtime Database: $fcmToken');
    }
  } catch (e) {
    log('Error getting messaging token: $e');
  }
}

Future<void> _saveMissedCheckpointNotification(
    String taskId,
    String officerId,
    String officerName,
    String clusterName,
    List<List<double>> missedCheckpoints) async {
  try {
    final database = FirebaseDatabase.instance.ref();
    final notificationData = {
      'type': 'missed_checkpoints',
      'taskId': taskId,
      'officerId': officerId,
      'officerName': officerName,
      'clusterName': clusterName,
      'missedCheckpoints': missedCheckpoints
          .map((checkpoint) => [checkpoint[0], checkpoint[1]])
          .toList(),
      'timestamp': ServerValue.timestamp,
      'read': false,
    };

    // Simpan ke node notifikasi global (untuk command center)
    await database
        .child('notifications/command_center')
        .push()
        .set(notificationData);
  } catch (e) {}
}

// --- FITUR BARU: FUNGSI PENGIRIMAN NOTIFIKASI MOCK LOCATION ---
Future<void> sendMockLocationNotificationToCommandCenter({
  required String patrolTaskId,
  required String officerId,
  required String officerName,
  required String clusterName,
  required double latitude,
  required double longitude,
}) async {
  try {
    log('Sending mock location notification to command center for task $patrolTaskId');

    // Ambil admin bearer token
    final bearerToken = await NotificationAccessToken.getToken;
    if (bearerToken == null) {
      throw Exception('Failed to get admin access token');
    }

    // Ambil semua user dengan role commandCenter
    final DatabaseReference usersRef = FirebaseDatabase.instance.ref('users');
    final Query commandCenterQuery =
        usersRef.orderByChild('role').equalTo('commandCenter');
    final DataSnapshot snapshot = await commandCenterQuery.get();

    if (!snapshot.exists) {
      log('No command center users found to send mock location notification');
      return;
    }

    final Map<dynamic, dynamic> usersData =
        snapshot.value as Map<dynamic, dynamic>;

    String title = 'Deteksi Lokasi Palsu!';
    String body =
        '$officerName ($clusterName) terdeteksi menggunakan lokasi palsu.';

    // Data untuk di-passing saat notifikasi diklik (semua harus string)
    Map<String, String> notificationData = {
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      'type': 'mock_location_detection',
      'task_id': patrolTaskId,
      'officer_id': officerId,
      'officer_name': officerName,
      'cluster_name': clusterName,
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Kirim ke setiap user command center
    int successCount = 0;
    for (var entry in usersData.entries) {
      final userData = entry.value as Map<dynamic, dynamic>;
      final String? pushToken = userData['push_token'] as String?;

      if (pushToken == null || pushToken.isEmpty) continue;

      try {
        final response = await http.post(
          Uri.parse(
              'https://fcm.googleapis.com/v1/projects/trackingsystem-kbp/messages:send'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $bearerToken',
          },
          body: jsonEncode({
            "message": {
              "token": pushToken,
              "notification": {
                "title": title,
                "body": body,
              },
              "data": notificationData, // Semua value sudah dalam bentuk string
            },
          }),
        );

        if (response.statusCode == 200) {
          successCount++;
          log('Successfully sent mock location notification to command center user: ${entry.key}');
        } else {
          log('FCM Error mock location for user ${entry.key}: ${response.body}');
        }
      } catch (e) {
        log('Error sending mock location notification to user ${entry.key}: $e');
      }
    }

    // Opsional: Simpan notifikasi ke database (jika ada kebutuhan untuk riwayat notifikasi di sisi admin)
    // await _saveMockLocationNotificationToDatabase(...);

    log('Sent mock location notification to $successCount command center users');
  } catch (e) {
    log('Error in sendMockLocationNotificationToCommandCenter: $e');
  }
}
// --- AKHIR FITUR BARU ---

/// Mengirim notifikasi push ke semua pengguna dengan role 'commandCenter'
Future<void> sendPushNotificationToCommandCenter({
  required String title,
  required String body,
  Map<String, dynamic>? data,
}) async {
  try {
    log('Sending notification to command center users: $title');

    // Ambil semua user dengan role commandCenter
    final DatabaseReference usersRef = FirebaseDatabase.instance.ref('users');
    final Query commandCenterQuery =
        usersRef.orderByChild('role').equalTo('commandCenter');
    final DataSnapshot snapshot = await commandCenterQuery.get();

    if (!snapshot.exists) {
      log('No command center users found');
      return;
    }

    // Ambil admin bearer token
    final bearerToken = await NotificationAccessToken.getToken;
    if (bearerToken == null) {
      throw Exception('Failed to get admin access token');
    }

    // Extract users data
    final Map<dynamic, dynamic> usersData =
        snapshot.value as Map<dynamic, dynamic>;
    int successCount = 0;
    int failCount = 0;

    // Kirim notifikasi ke setiap user
    for (var entry in usersData.entries) {
      final userData = entry.value as Map<dynamic, dynamic>;
      final String? pushToken = userData['push_token'] as String?;
      final String userId = entry.key as String;

      if (pushToken == null || pushToken.isEmpty) {
        log('Command center user $userId does not have a valid push token');
        failCount++;
        continue;
      }

      try {
        // Kirim notifikasi menggunakan Firebase Cloud Messaging
        final response = await http.post(
          Uri.parse(
              'https://fcm.googleapis.com/v1/projects/trackingsystem-kbp/messages:send'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $bearerToken',
          },
          body: jsonEncode({
            "message": {
              "token": pushToken,
              "notification": {
                "title": title,
                "body": body,
              },
              "data": data ??
                  {
                    "click_action": "FLUTTER_NOTIFICATION_CLICK",
                    "type": "command_center_notification",
                  },
            },
          }),
        );

        if (response.statusCode == 200) {
          log('Notification sent successfully to command center user: $userId');
          successCount++;
        } else {
          log('FCM Error for user $userId: ${response.body}');
          failCount++;
        }
      } catch (e) {
        log('Error sending notification to user $userId: $e');
        failCount++;
      }
    }

    log('Command center notification summary - Success: $successCount, Failed: $failCount');
  } catch (e) {
    log('Error sending notification to command center: $e');
  }
}

// Update fungsi sendMissedCheckpointsNotification untuk mengambil radius dari cluster
Future<void> sendMissedCheckpointsNotification({
  required String patrolTaskId,
  required String officerName,
  required String clusterName,
  required String officerId,
  required List<List<double>> missedCheckpoints,
  required double customRadius,
}) async {
  try {
    // PERBAIKAN: Ambil clusterId dari task untuk mendapatkan radius yang tepat
    String clusterId = '';
    double radiusUsed = customRadius; // Default fallback

    try {
      final taskSnapshot = await FirebaseDatabase.instance
          .ref('tasks')
          .child(patrolTaskId)
          .get();

      if (taskSnapshot.exists) {
        final taskData = taskSnapshot.value as Map<dynamic, dynamic>;
        clusterId = taskData['clusterId']?.toString() ?? '';

        // Ambil radius validasi dari cluster
        if (clusterId.isNotEmpty) {
          final clusterSnapshot =
              await FirebaseDatabase.instance.ref('users/$clusterId').get();

          if (clusterSnapshot.exists) {
            final clusterData = clusterSnapshot.value as Map<dynamic, dynamic>;

            // Gunakan checkpoint_validation_radius dari cluster
            radiusUsed = clusterData['checkpoint_validation_radius'] != null
                ? (clusterData['checkpoint_validation_radius'] as num)
                    .toDouble()
                : 50.0;

            log('Using cluster validation radius: ${radiusUsed}m for cluster $clusterId');
          }
        }
      }
    } catch (e) {
      log('Error fetching cluster radius: $e, using default 50m');
    }

    // Panggil fungsi yang sudah ada dengan radius yang tepat
    await sendMissedCheckpointsNotificationWithRadius(
      patrolTaskId: patrolTaskId,
      officerName: officerName,
      clusterName: clusterName,
      officerId: officerId,
      clusterId: clusterId,
      missedCheckpoints: missedCheckpoints,
      customRadius: radiusUsed,
    );
  } catch (e) {
    log('Error in sendMissedCheckpointsNotification: $e');
  }
}

// Update fungsi sendMissedCheckpointsNotificationWithRadius
Future<void> sendMissedCheckpointsNotificationWithRadius({
  required String patrolTaskId,
  required String officerName,
  required String clusterName,
  required String officerId,
  required String clusterId,
  required List<List<double>> missedCheckpoints,
  double? customRadius,
}) async {
  try {
    // PERBAIKAN: Ambil radius validasi cluster yang tepat
    double radiusUsed = customRadius ?? 50.0; // Default fallback

    if (customRadius == null && clusterId.isNotEmpty) {
      try {
        final clusterSnapshot =
            await FirebaseDatabase.instance.ref('users/$clusterId').get();

        if (clusterSnapshot.exists) {
          final clusterData = clusterSnapshot.value as Map<dynamic, dynamic>;

          // Gunakan checkpoint_validation_radius dari cluster
          radiusUsed = clusterData['checkpoint_validation_radius'] != null
              ? (clusterData['checkpoint_validation_radius'] as num).toDouble()
              : 50.0;

          log('Fetched cluster validation radius: ${radiusUsed}m for cluster $clusterId');
        }
      } catch (e) {
        log('Error fetching cluster radius in notification: $e');
      }
    }

    // PERBAIKAN: Cek dan ambil data lengkap dari database Firebase
    String displayOfficerName = officerName;
    String displayClusterName = clusterName;

    // Selalu fetch data untuk memastikan akurasi, tidak hanya jika format default
    try {
      // Ambil data langsung dari task di Firebase
      final taskSnapshot = await FirebaseDatabase.instance
          .ref('tasks')
          .child(patrolTaskId)
          .get();

      if (taskSnapshot.exists) {
        final taskData = taskSnapshot.value as Map<dynamic, dynamic>;

        // Gunakan officerName dan clusterName dari task jika tersedia
        if (taskData['officerName'] != null) {
          displayOfficerName = taskData['officerName'].toString();
        }

        if (taskData['clusterName'] != null) {
          displayClusterName = taskData['clusterName'].toString();
        }

        // Jika masih tidak ada, coba ambil dari user data
        if ((displayOfficerName.trim().isEmpty ||
                displayOfficerName == "Unknown Officer") &&
            taskData['userId'] != null) {
          final officerId = taskData['userId'].toString();
          final clusterId = taskData['clusterId']?.toString() ?? '';

          if (clusterId.isNotEmpty) {
            try {
              final officersSnapshot = await FirebaseDatabase.instance
                  .ref('users')
                  .child(clusterId)
                  .child('officers')
                  .get();

              if (officersSnapshot.exists) {
                final officersData =
                    officersSnapshot.value as Map<dynamic, dynamic>;

                // Cari officer berdasarkan ID
                officersData.forEach((key, value) {
                  if (value is Map && value['id'] == officerId) {
                    displayOfficerName =
                        value['name']?.toString() ?? "Unknown Officer";
                  }
                });
              }
            } catch (e) {}
          }
        }

        // Jika cluster name masih kosong atau default
        if ((displayClusterName.trim().isEmpty ||
                displayClusterName == "No Tatar") &&
            taskData['clusterId'] != null) {
          final clusterId = taskData['clusterId'].toString();

          try {
            final clusterSnapshot = await FirebaseDatabase.instance
                .ref('users')
                .child(clusterId)
                .get();

            if (clusterSnapshot.exists) {
              final clusterData =
                  clusterSnapshot.value as Map<dynamic, dynamic>;
              if (clusterData['name'] != null) {
                displayClusterName = clusterData['name'].toString();
              }
            }
          } catch (e) {}
        }
      }
    } catch (e) {
      // Fallback to defaults if fetching fails
    }

    // Fallback values jika masih kosong
    if (displayOfficerName.trim().isEmpty ||
        displayOfficerName == "Unknown Officer") {
      displayOfficerName = "Petugas";
    }

    if (displayClusterName.trim().isEmpty || displayClusterName == "No Tatar") {
      displayClusterName = "Tatar";
    }

    // Ambil admin bearer token
    final bearerToken = await NotificationAccessToken.getToken;
    if (bearerToken == null) {
      throw Exception('Failed to get admin access token');
    }

    // Ambil semua user dengan role commandCenter
    final DatabaseReference usersRef = FirebaseDatabase.instance.ref('users');
    final Query commandCenterQuery =
        usersRef.orderByChild('role').equalTo('commandCenter');
    final DataSnapshot snapshot = await commandCenterQuery.get();

    if (!snapshot.exists) {
      return;
    }

    final Map<dynamic, dynamic> usersData =
        snapshot.value as Map<dynamic, dynamic>;
    int totalMissed = missedCheckpoints.length;
    String title = 'Titik Patroli Terlewat';
    String body =
        '$displayOfficerName dari $displayClusterName melewatkan $totalMissed titik patroli (radius ${radiusUsed.toInt()}m)';

    // Konversi koordinat ke string untuk FCM payload
    // FCM data hanya menerima string sebagai value
    String missedCheckpointsJson = jsonEncode(missedCheckpoints
        .map((checkpoint) =>
            {'latitude': checkpoint[0], 'longitude': checkpoint[1]})
        .toList());

    // Data untuk di-passing saat notifikasi diklik (semua harus string)
    Map<String, String> notificationData = {
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      'type': 'missed_checkpoints',
      'task_id': patrolTaskId,
      'officer_id': officerId,
      'officer_name': displayOfficerName,
      'cluster_name': displayClusterName,
      'missed_checkpoints': missedCheckpointsJson,
      'total_missed': totalMissed.toString(),
      'validation_radius':
          radiusUsed.toString(), // Radius yang digunakan dari cluster
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Kirim ke semua user command center
    int successCount = 0;

    for (var entry in usersData.entries) {
      final userData = entry.value as Map<dynamic, dynamic>;
      final String? pushToken = userData['push_token'] as String?;

      if (pushToken == null || pushToken.isEmpty) continue;

      try {
        final response = await http.post(
          Uri.parse(
              'https://fcm.googleapis.com/v1/projects/trackingsystem-kbp/messages:send'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $bearerToken',
          },
          body: jsonEncode({
            "message": {
              "token": pushToken,
              "notification": {
                "title": title,
                "body": body,
              },
              "data": notificationData, // Semua value sudah dalam bentuk string
            },
          }),
        );

        if (response.statusCode == 200) {
          successCount++;
        } else {}
      } catch (e) {}
    }

    // Simpan notifikasi ke database
    await _saveMissedCheckpointNotification(
        patrolTaskId, officerId, officerName, clusterName, missedCheckpoints);

    log('Sent missed checkpoints notification to $successCount command center users using ${radiusUsed}m radius');
  } catch (e) {
    log('Error in sendMissedCheckpointsNotificationWithRadius: $e');
  }
}

Future<void> sendPushNotificationToOfficer({
  required String officerId,
  required String title,
  required String body,
  required String patrolTime,
  String? taskId,
}) async {
  try {
    // Ambil push token petugas dari Realtime Database
    final DatabaseReference officerRef =
        FirebaseDatabase.instance.ref('users/$officerId');
    final DataSnapshot snapshot = await officerRef.get();

    if (!snapshot.exists) {
      throw Exception('Officer not found');
    }

    final officerData = Map<String, dynamic>.from(snapshot.value as Map);
    String? officerPushToken = officerData['push_token'];

    if (officerPushToken == null || officerPushToken.isEmpty) {
      log('Officer does not have a valid push token');
      return;
    }

    // Ambil admin bearer token
    final bearerToken = await NotificationAccessToken.getToken;
    if (bearerToken == null) {
      throw Exception('Failed to get admin access token');
    }

    // Kirim notifikasi menggunakan Firebase Cloud Messaging
    final response = await http.post(
      Uri.parse(
          'https://fcm.googleapis.com/v1/projects/trackingsystem-kbp/messages:send'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $bearerToken',
      },
      body: jsonEncode({
        "message": {
          "token": officerPushToken,
          "notification": {
            "title": title,
            "body": "$body\nJam Patroli: $patrolTime",
          },
          "data": {
            "click_action": "FLUTTER_NOTIFICATION_CLICK",
            "type": "patrol_task",
            "task_id": taskId,
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      log('FCM Error: ${response.body}');
      throw Exception('Failed to send notification: ${response.body}');
    }

    log('Notification sent successfully to officer: $officerId');
  } catch (e) {
    log('Error sending notification: $e');
  }
}

class NotificationAccessToken {
  static String? _token;

  //to generate token only once for an app run
  static Future<String?> get getToken async =>
      _token ?? await _getAccessToken();

  // to get admin bearer token
  static Future<String?> _getAccessToken() async {
    try {
      const fMessagingScope =
          'https://www.googleapis.com/auth/firebase.messaging';

      final jsonString = await rootBundle
          .loadString('assets/credential/trackingsystem-kbp-09105242eb36.json');
      final serviceAccount = json.decode(jsonString);

      final client = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(serviceAccount),
        [fMessagingScope],
      );

      _token = client.credentials.accessToken.data;
      return _token;
    } catch (e) {
      log('error notifnya gan $e');
      return null;
    }
  }
}

// --- FITUR BARU: HANDLER PENGINGAT CHARGE HP ---
Future<bool> sendLowBatteryChargeReminderNotification({
  required String officerId,
  required String officerName,
  required String clusterName,
  required int batteryLevel,
  required String batteryState,
}) async {
  try {
    log('Sending low battery charge reminder to officer: $officerId (Battery: $batteryLevel%)');

    // Ambil push token petugas dari Realtime Database
    final DatabaseReference officerRef =
        FirebaseDatabase.instance.ref('users/$officerId');
    final DataSnapshot snapshot = await officerRef.get();

    if (!snapshot.exists) {
      log('Officer not found: $officerId');
      return false;
    }

    final officerData = Map<String, dynamic>.from(snapshot.value as Map);
    String? officerPushToken = officerData['push_token'];

    if (officerPushToken == null || officerPushToken.isEmpty) {
      log('Officer $officerId does not have a valid push token');
      return false;
    }

    // Ambil admin bearer token
    final bearerToken = await NotificationAccessToken.getToken;
    if (bearerToken == null) {
      log('Failed to get admin access token');
      return false;
    }

    // Buat pesan notifikasi berdasarkan level battery dan state
    final notificationContent = _buildLowBatteryNotificationContent(
      batteryLevel: batteryLevel,
      batteryState: batteryState,
      officerName: officerName,
    );

    // Data untuk di-passing saat notifikasi diklik
    Map<String, String> notificationData = {
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      'type': 'low_battery_reminder',
      'officer_id': officerId,
      'officer_name': officerName,
      'cluster_name': clusterName,
      'battery_level': batteryLevel.toString(),
      'battery_state': batteryState,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // PERBAIKAN: Struktur JSON FCM yang benar
    final fcmPayload = {
      "message": {
        "token": officerPushToken,
        "notification": {
          "title": notificationContent['title'],
          "body": notificationContent['body'],
        },
        "data": notificationData,
        "android": {
          "priority":
              "high", // Priority di level android, bukan android.notification
          "notification": {
            "channel_id": "battery_reminder",
            "default_sound": true,
            "default_vibrate_timings": true,
            "notification_priority":
                "PRIORITY_HIGH", // Gunakan notification_priority
            "icon": "@mipmap/ic_launcher",
            "color": "#FF8F00", // Warning color untuk battery
          }
        },
        "apns": {
          "headers": {
            "apns-priority": "10", // High priority untuk iOS
          },
          "payload": {
            "aps": {
              "alert": {
                "title": notificationContent['title'],
                "body": notificationContent['body'],
              },
              "sound": "default",
              "badge": 1,
              "category": "BATTERY_REMINDER",
            }
          }
        }
      },
    };

    // Kirim notifikasi menggunakan Firebase Cloud Messaging
    final response = await http.post(
      Uri.parse(
          'https://fcm.googleapis.com/v1/projects/trackingsystem-kbp/messages:send'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $bearerToken',
      },
      body: jsonEncode(fcmPayload),
    );

    if (response.statusCode == 200) {
      log('Low battery charge reminder sent successfully to officer: $officerId');

      // Simpan log notifikasi ke database
      // await _saveLowBatteryNotificationLog(
      //   officerId: officerId,
      //   officerName: officerName,
      //   clusterName: clusterName,
      //   batteryLevel: batteryLevel,
      //   batteryState: batteryState,
      // );

      return true;
    } else {
      log('FCM Error for low battery reminder: ${response.body}');
      return false;
    }
  } catch (e) {
    log('Error sending low battery charge reminder: $e');
    return false;
  }
}

// TAMBAHAN: Helper function untuk membuat konten notifikasi berdasarkan kondisi battery
Map<String, String> _buildLowBatteryNotificationContent({
  required int batteryLevel,
  required String batteryState,
  required String officerName,
}) {
  String title;
  String body;

  // Sesuaikan pesan berdasarkan level dan state battery
  if (batteryLevel <= 15) {
    title = '🔋 Battery Kritis!';
    if (batteryState.toLowerCase() == 'charging') {
      body =
          'Hi $officerName, battery HP Anda tinggal $batteryLevel% dan sedang charging. Pastikan tetap terhubung dengan charger hingga mencapai minimal 50%.';
    } else {
      body =
          'Hi $officerName, battery HP Anda sangat rendah ($batteryLevel%)! Segera charge untuk memastikan sistem tracking tetap aktif selama patroli.';
    }
  } else if (batteryLevel <= 25) {
    title = '⚠️ Battery Rendah';
    if (batteryState.toLowerCase() == 'charging') {
      body =
          'Hi $officerName, battery HP Anda $batteryLevel% dan sedang charging. Biarkan charging hingga minimal 70% sebelum patroli.';
    } else {
      body =
          'Hi $officerName, battery HP Anda tinggal $batteryLevel%. Disarankan untuk charge sebelum memulai patroli berikutnya.';
    }
  } else {
    title = '🔋 Pengingat Charge';
    if (batteryState.toLowerCase() == 'charging') {
      body =
          'Hi $officerName, battery HP Anda $batteryLevel% dan sedang charging. Lanjutkan charging untuk performa optimal.';
    } else {
      body =
          'Hi $officerName, battery HP Anda $batteryLevel%. Sebaiknya charge sekarang untuk memastikan HP siap untuk tugas berikutnya.';
    }
  }

  return {
    'title': title,
    'body': body,
  };
}

// TAMBAHAN: Simpan log notifikasi battery ke database
Future<void> _saveLowBatteryNotificationLog({
  required String officerId,
  required String officerName,
  required String clusterName,
  required int batteryLevel,
  required String batteryState,
}) async {
  try {
    final database = FirebaseDatabase.instance.ref();
    final notificationLogData = {
      'type': 'low_battery_reminder',
      'officerId': officerId,
      'officerName': officerName,
      'clusterName': clusterName,
      'batteryLevel': batteryLevel,
      'batteryState': batteryState,
      'timestamp': ServerValue.timestamp,
      'sentAt': DateTime.now().toIso8601String(),
    };

    // Simpan ke node logs untuk tracking
    await database
        .child('notification_logs/battery_reminders')
        .push()
        .set(notificationLogData);

    // Update last notification time di user profile
    await database.child('users/$officerId').update({
      'lastBatteryNotificationSent': DateTime.now().toIso8601String(),
    });

    log('Low battery notification log saved successfully');
  } catch (e) {
    log('Error saving low battery notification log: $e');
  }
}

// TAMBAHAN: Fungsi untuk mengecek apakah boleh mengirim notifikasi battery lagi
Future<bool> canSendBatteryNotification(String officerId) async {
  try {
    final userRef = FirebaseDatabase.instance.ref('users/$officerId');
    final snapshot = await userRef.get();

    if (!snapshot.exists) return true;

    final userData = Map<String, dynamic>.from(snapshot.value as Map);
    final lastNotificationStr =
        userData['lastBatteryNotificationSent'] as String?;

    if (lastNotificationStr == null) return true;

    final lastNotification = DateTime.parse(lastNotificationStr);
    final now = DateTime.now();
    final difference = now.difference(lastNotification);

    // Hanya boleh kirim notifikasi battery lagi setelah 30 menit
    return difference.inMinutes >= 30;
  } catch (e) {
    log('Error checking battery notification cooldown: $e');
    return true; // Default allow jika ada error
  }
}

// TAMBAHAN: Fungsi untuk mengirim notifikasi battery otomatis (untuk background service)
Future<void> sendAutomaticLowBatteryNotification({
  required String officerId,
  required String officerName,
  required String clusterName,
  required int batteryLevel,
  required String batteryState,
}) async {
  try {
    // Cek apakah boleh kirim notifikasi (cooldown check)
    final canSend = await canSendBatteryNotification(officerId);
    if (!canSend) {
      log('Battery notification for $officerId is on cooldown, skipping');
      return;
    }

    // Hanya kirim otomatis jika battery <= 20% dan tidak sedang charging
    if (batteryLevel <= 20 && batteryState.toLowerCase() != 'charging') {
      await sendLowBatteryChargeReminderNotification(
        officerId: officerId,
        officerName: officerName,
        clusterName: clusterName,
        batteryLevel: batteryLevel,
        batteryState: batteryState,
      );

      log('Automatic low battery notification sent to $officerId');
    }
  } catch (e) {
    log('Error in automatic low battery notification: $e');
  }
}

// --- FITUR BARU: FUNGSI PENGIRIMAN NOTIFIKASI LAPORAN ---
Future<void> sendReportNotificationToCommandCenter({
  required String reportId,
  required String reportTitle,
  required String reportDescription,
  required String patrolTaskId,
  required String officerId,
  required String officerName,
  required String clusterName,
  required double latitude,
  required double longitude,
  required DateTime reportTime,
  String? photoUrl,
}) async {
  try {
    log('Sending report notification to command center for report $reportId');

    // Ambil admin bearer token
    final bearerToken = await NotificationAccessToken.getToken;
    if (bearerToken == null) {
      throw Exception('Failed to get admin access token');
    }

    // Ambil semua user dengan role commandCenter
    final DatabaseReference usersRef = FirebaseDatabase.instance.ref('users');
    final Query commandCenterQuery =
        usersRef.orderByChild('role').equalTo('commandCenter');
    final DataSnapshot snapshot = await commandCenterQuery.get();

    if (!snapshot.exists) {
      log('No command center users found to send report notification');
      return;
    }

    final Map<dynamic, dynamic> usersData =
        snapshot.value as Map<dynamic, dynamic>;

    // Format waktu laporan
    final timeFormatter = DateFormat('HH:mm', 'id_ID');
    final dateFormatter = DateFormat('dd MMM yyyy', 'id_ID');
    final reportTimeStr = timeFormatter.format(reportTime);
    final reportDateStr = dateFormatter.format(reportTime);

    String title = 'Laporan Baru Diterima';
    String body = '$officerName ($clusterName) mengirim laporan: $reportTitle';

    // Data untuk di-passing saat notifikasi diklik (semua harus string)
    Map<String, String> notificationData = {
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      'type': 'new_report',
      'report_id': reportId,
      'report_title': reportTitle,
      'report_description': reportDescription,
      'patrol_task_id': patrolTaskId,
      'officer_id': officerId,
      'officer_name': officerName,
      'cluster_name': clusterName,
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'report_time': reportTime.toIso8601String(),
      'report_time_formatted': '$reportDateStr $reportTimeStr',
      'photo_url': photoUrl ?? '',
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Kirim ke setiap user command center
    int successCount = 0;
    for (var entry in usersData.entries) {
      final userData = entry.value as Map<dynamic, dynamic>;
      final String? pushToken = userData['push_token'] as String?;

      if (pushToken == null || pushToken.isEmpty) continue;

      try {
        final response = await http.post(
          Uri.parse(
              'https://fcm.googleapis.com/v1/projects/trackingsystem-kbp/messages:send'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $bearerToken',
          },
          body: jsonEncode({
            "message": {
              "token": pushToken,
              "notification": {
                "title": title,
                "body": body,
              },
              "data": notificationData, // Semua value sudah dalam bentuk string
            },
          }),
        );

        if (response.statusCode == 200) {
          successCount++;
          log('Successfully sent report notification to command center user: ${entry.key}');
        } else {
          log('FCM Error report notification for user ${entry.key}: ${response.body}');
        }
      } catch (e) {
        log('Error sending report notification to user ${entry.key}: $e');
      }
    }

    // Simpan notifikasi ke database untuk riwayat
    await _saveReportNotificationToDatabase(
      reportId: reportId,
      reportTitle: reportTitle,
      reportDescription: reportDescription,
      patrolTaskId: patrolTaskId,
      officerId: officerId,
      officerName: officerName,
      clusterName: clusterName,
      latitude: latitude,
      longitude: longitude,
      reportTime: reportTime,
      photoUrl: photoUrl,
    );

    log('Sent report notification to $successCount command center users');
  } catch (e) {
    log('Error in sendReportNotificationToCommandCenter: $e');
  }
}

// Fungsi untuk menyimpan notifikasi laporan ke database
Future<void> _saveReportNotificationToDatabase({
  required String reportId,
  required String reportTitle,
  required String reportDescription,
  required String patrolTaskId,
  required String officerId,
  required String officerName,
  required String clusterName,
  required double latitude,
  required double longitude,
  required DateTime reportTime,
  String? photoUrl,
}) async {
  try {
    final database = FirebaseDatabase.instance.ref();
    final notificationData = {
      'type': 'new_report',
      'reportId': reportId,
      'reportTitle': reportTitle,
      'reportDescription': reportDescription,
      'patrolTaskId': patrolTaskId,
      'officerId': officerId,
      'officerName': officerName,
      'clusterName': clusterName,
      'latitude': latitude,
      'longitude': longitude,
      'reportTime': reportTime.toIso8601String(),
      'photoUrl': photoUrl,
      'timestamp': ServerValue.timestamp,
      'read': false,
    };

    // Simpan ke node notifikasi global (untuk command center)
    await database
        .child('notifications/command_center')
        .push()
        .set(notificationData);

    log('Report notification saved to database successfully');
  } catch (e) {
    log('Error saving report notification to database: $e');
  }
}
