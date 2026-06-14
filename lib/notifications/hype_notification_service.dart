import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzData; // 🟢 IMPORT TIMEZONE DATA
import 'package:hive/hive.dart';

import '../features/trips/trip_model.dart';

class HypeNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // --------------------------------------------------
  // 1. UI INITIALIZATION (When app starts)
  // --------------------------------------------------
  static Future<void> init() async {
    if (Platform.isWindows) return;

    // 🟢 INITIALIZE TIMEZONES BEFORE ANYTHING ELSE
    tzData.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings darwinSettings =
    DarwinInitializationSettings(requestAlertPermission: true);

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(initSettings);

    if (Platform.isAndroid) {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
      // Android 12+ requires asking for Exact Alarms permission
      await androidImplementation?.requestExactAlarmsPermission();

      final canSchedule =
      await androidImplementation?.canScheduleExactNotifications();

      print("🔔 Exact Alarm Permission: $canSchedule");
    }
  }

  // --------------------------------------------------
  // 2. THE ALARMMANAGER SCHEDULER
  // --------------------------------------------------
  static Future<void> scheduleTripNotifications({
    required int tripId,
    required String destination,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (Platform.isWindows) return;

    // 🛡️ AUTO-CANCEL: Always clear existing alarms for this trip first.
    await cancelTripNotifications(tripId);

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'hype_channel',
        'Trip Hype Alerts',
        channelDescription: 'Anticipation and packing reminders',
        importance: Importance.max,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
        fullScreenIntent: false, // 🚨 Wakes up the screen if asleep
      ),
      iOS: DarwinNotificationDetails(),
    );

    final now = DateTime.now();

    // --- ALERT 1: PRE-TRIP (12:00 PM the day before start) ---
    DateTime preTripTime = DateTime(
        startDate.year,
        startDate.month,
        startDate.day - 1,
        12, 0, 0
    );

    if (preTripTime.isAfter(now)) {
      final preTripTz = tz.TZDateTime.from(preTripTime, tz.local);

      print("🚀 Attempting to breach Android AlarmManager...");

      try {
        await _notificationsPlugin.zonedSchedule(
          tripId,
          'Passport? Check. Bags? Packed.',
          'Tomorrow, we fly to $destination! 🌍',
          preTripTz,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
        print("✅ SUCCESS! ⏰ Pre-trip alert locked in!");
      } catch (e) {
        print("🚨 FATAL ALARM ERROR: $e");
      }

    } else {
      print("⚠️ Pre-trip alert skipped!");
    }

    // --- ALERT 2: POST-TRIP (12:00 PM the day after end date) ---
    DateTime postTripTime = DateTime(
        endDate.year,
        endDate.month,
        endDate.day + 1,
        12, 0, 0
    );

    if (postTripTime.isAfter(now)) {
      final postTripTz = tz.TZDateTime.from(postTripTime, tz.local);

      try {
        await _notificationsPlugin.zonedSchedule(
          tripId + 100000,
          'Welcome back! 🏡',
          'Hope you had an amazing time in $destination! Time to unpack... or just leave your suitcase in the corner for a week.',
          postTripTz,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
        print("⏰ Post-trip alert locked in for $destination at: $postTripTime");
      } catch (e) {
        print("🚨 FATAL ALARM ERROR POST-TRIP: $e");
      }
    } else {
      print("⚠️ Post-trip alert skipped! The target time has already passed.");
    }

    final pending =
    await _notificationsPlugin.pendingNotificationRequests();

    print("📬 Pending Notifications: ${pending.length}");

    for (final p in pending) {
      print("📌 ID=${p.id} | Title=${p.title}");
    }
  }

  // --------------------------------------------------
  // 3. CANCEL IF TRIP IS DELETED OR EDITED
  // --------------------------------------------------
  static Future<void> cancelTripNotifications(int tripId) async {
    if (Platform.isWindows) return;

    await _notificationsPlugin.cancel(tripId);
    await _notificationsPlugin.cancel(tripId + 100000);
    print("🔕 Cancelled any existing exact alarms for trip $tripId");
  }

  // --------------------------------------------------
  // 4. THE MASTER KILL SWITCH (For Sign Out / Deletion)
  // --------------------------------------------------
  static Future<void> cancelAll() async {
    if (Platform.isWindows) return;

    await _notificationsPlugin.cancelAll();
    print("🔕 System Wipe: All notifications completely cleared.");
  }

  // --------------------------------------------------
  // 5. FOREGROUND EXECUTION (For Map Geodrops)
  // --------------------------------------------------
  static Future<void> showImmediateLocationAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'location_channel',
        'Nearby Discovery Alerts',
        channelDescription: 'Alerts when you are near a saved drop or hidden gem',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notificationsPlugin.show(id, title, body, details);
  }

  // --------------------------------------------------
  // 🔄 THE STATE RECONCILIATION ENGINE (Resyncs everything)
  // --------------------------------------------------
  static Future<void> syncAllAlarms() async {
    if (Platform.isWindows) return;

    print("🔄 SYNC ENGINE START: Rebuilding time table...");

    // 1. Wipe the slate clean to destroy any ghost alarms from old app versions
    await cancelAll();

    try {
      final tripBox = Hive.box<Trip>('trips');
      final allTrips = tripBox.values.toList();
      final now = DateTime.now();

      print("🕵️ DETECTIVE MODE: Hive contains ${allTrips.length} trips:");
      for (var t in allTrips) {
        print(" -> Trip: ${t.title} | Start: ${t.startDate} | End: ${t.endDate}");
      }

      // 3. Loop through the database
      for (var trip in allTrips) {
        // Skip this trip if essential dates are missing
        if (trip.startDate == null || trip.endDate == null) continue;

        // 🟢 CAPPED 32-BIT POSITIVE ID
        final int baseAlarmId = (trip.id.hashCode.abs()) % 1000000;

        // --- POST-TRIP ALARM ---
        DateTime postTripTime = DateTime(
            trip.endDate!.year,
            trip.endDate!.month,
            trip.endDate!.day + 1,
            12, 0, 0
        );

        // If the post-trip notification is still in the future,
        // schedule both notifications for this trip.
        if (postTripTime.isAfter(now)) {
          await scheduleTripNotifications(
            tripId: baseAlarmId,
            destination: trip.title ?? "your destination",
            startDate: trip.startDate!,
            endDate: trip.endDate!,
          );
        }
      }
      print("✅ SYNC ENGINE COMPLETE: Time table is fully restored!");
    } catch (e) {
      print("🚨 SYNC ENGINE ERROR: Could not rebuild alarms: $e");
    }
  }
}