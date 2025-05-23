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
import 'package:livetrackingapp/admin_map_screen.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
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
  print("Handling a background message: ${message.messageId}");
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
        } catch (e) {
          print('Error parsing missed checkpoints: $e');
        }
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
  print('User granted permission: ${settings.authorizationStatus}');

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
    print("Message received in foreground: ${message.notification?.title}");

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
    print(
        "Notification clicked while app in background: ${message.notification?.title}");

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
  } catch (e) {
    print('Error saving missed checkpoint notification to database: $e');
  }
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

// Fungsi perbaikan untuk mengirim notifikasi missed checkpoints

Future<void> sendMissedCheckpointsNotification({
  required String patrolTaskId,
  required String officerName,
  required String clusterName,
  required String officerId,
  required List<List<double>> missedCheckpoints,
}) async {
  try {
    // PERBAIKAN: Cek dan ambil data lengkap dari database Firebase
    String displayOfficerName = officerName;
    String displayClusterName = clusterName;

    print('Original officer name: $officerName');
    print('Original cluster name: $clusterName');

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
          print('Using task officerName from DB: $displayOfficerName');
        }

        if (taskData['clusterName'] != null) {
          displayClusterName = taskData['clusterName'].toString();
          print('Using task clusterName from DB: $displayClusterName');
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
                    print(
                        'Found officer name in officers collection: $displayOfficerName');
                  }
                });
              }
            } catch (e) {
              print('Error finding officer in users/$clusterId/officers: $e');
            }
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
                print(
                    'Using cluster name from users collection: $displayClusterName');
              }
            }
          } catch (e) {
            print('Error finding cluster name: $e');
          }
        }
      }
    } catch (e) {
      print('Error fetching detailed data for notification: $e');
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

    print('Final officer name for notification: $displayOfficerName');
    print('Final cluster name for notification: $displayClusterName');

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
      print('No command center users found');
      return;
    }

    final Map<dynamic, dynamic> usersData =
        snapshot.value as Map<dynamic, dynamic>;
    int totalMissed = missedCheckpoints.length;
    String title = 'Titik Patroli Terlewat';
    String body =
        '$displayOfficerName dari $displayClusterName melewatkan $totalMissed titik patroli';

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
      'missed_checkpoints':
          missedCheckpointsJson, // Koordinat dalam bentuk string JSON
      'total_missed': totalMissed.toString(),
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
          print('Successfully sent notification to command center user');
        } else {
          print('FCM Error checkpoints: ${response.body}');
        }
      } catch (e) {
        print('Error sending missed checkpoint notification: $e');
      }
    }

    // Simpan notifikasi ke database
    await _saveMissedCheckpointNotification(
        patrolTaskId, officerId, officerName, clusterName, missedCheckpoints);

    print(
        'Sent missed checkpoint notification to $successCount command center users');
  } catch (e) {
    print('Error in sendMissedCheckpointsNotification: $e');
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
