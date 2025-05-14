import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/firebase_options.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'dart:developer';

FirebaseMessaging fMessaging = FirebaseMessaging.instance;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
const String channelId = 'livetracking';
const String channelName = 'Live Location KBP';
const String channelDescription = 'For Showing Current Location Notification';

Future<void> showForegroundNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidNotificationDetails =
      AndroidNotificationDetails(
    'damaresa', // ID Channel harus sama
    'Damaresa Property',
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
      print('Notification payload: ${response.payload}');
      // Lakukan sesuatu berdasarkan payload notifikasi, jika diperlukan
    },
  );

  // Handle Foreground Messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("Message received in foreground: ${message.notification?.title}");

    if (message.notification != null) {
      showForegroundNotification(message);
    }
  });

  // Handle Background Messages
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Handle Messages Saat Aplikasi Dibuka dari Notifikasi
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print("Notification clicked: ${message.notification?.title}");
    // Arahkan ke halaman tertentu jika diperlukan
  });
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

Future<void> sendPushNotificationToOfficer({
  required String officerId,
  required String title,
  required String body,
  required String patrolTime,
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
