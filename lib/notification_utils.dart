import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/firebase_options.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'dart:developer';

import 'package:livetrackingapp/map_screen.dart';
import 'package:livetrackingapp/presentation/routing/bloc/patrol_bloc.dart';
import 'package:livetrackingapp/main.dart' show navigatorKey;

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

// Tambahkan fungsi ini ke notification_utils.dart

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
