import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> setupNotificationChannels() async {
  // Default channel
  const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
    'default_channel_id',
    'Default Notifications',
    description: 'This channel uses the system default sound',
    importance: Importance.high,
    playSound: true,
  );

  // Custom sound channel
  const AndroidNotificationChannel customSoundChannel = AndroidNotificationChannel(
    'samsung_easteregg_channel',
    'My Custom Sound Channel',
    description: 'This channel plays a custom sound',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('mysound'),
    playSound: true,
  );

  // Custom sound channel
  const AndroidNotificationChannel basketFinishedSound = AndroidNotificationChannel(
    'basket_finished_channel_e',
    'My Custom Sound Channel',
    description: 'This channel plays a custom sound',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('basket_finished'),
    playSound: true,
  );

  const AndroidNotificationChannel noSoundChannel = AndroidNotificationChannel(
    'quiet_channel_id',
    'Quiet Channel',
    description: 'This channel plays no sound',
    importance: Importance.high,
    playSound: false,
  );

  // Register channels
  if (Platform.isAndroid) {
    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(defaultChannel);
      await androidImplementation.createNotificationChannel(customSoundChannel);
      await androidImplementation.createNotificationChannel(noSoundChannel);
      await androidImplementation.createNotificationChannel(basketFinishedSound);
    }
  }
}

Future<void> initializeNotifications() async {
  const AndroidInitializationSettings androidInitSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final DarwinInitializationSettings iosInitSettings = DarwinInitializationSettings();

  final InitializationSettings initSettings = InitializationSettings(
    android: androidInitSettings,
    iOS: iosInitSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(initSettings);
}

Future<void> sendNotification(String title, String body, List<String> tokens, [String? channelId]) async{
  channelId ??= "default_channel_id";
  if (tokens.isEmpty) return;

  final HttpsCallable callable =
  FirebaseFunctions.instance.httpsCallable(
      'sendNotification');
  await callable.call({
    'notificationTitle': title,
    'notificationBody': body,
    'userTokens': tokens,
    'channelId': channelId,
  });


}
