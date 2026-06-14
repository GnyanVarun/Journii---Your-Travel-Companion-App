import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
//import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'package:timezone/data/latest_all.dart' as tzData;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'services/supabase_service.dart';
import 'app.dart';
import 'features/trips/ai_itinerary_model.dart';
import 'features/trips/trip_model.dart';
import 'features/trips/trip_style.dart';
import 'features/trips/place_idea_model.dart';
import 'features/trips/itinerary_item_model.dart';
import 'features/trips/chat_message_model.dart';
import 'notifications/hype_notification_service.dart';
import 'auth/update_password_screen.dart';
import 'auth/auth_screen.dart'; // 🟢 ADDED: Import for sign-out routing

// -------------------------------------------------------------------
// 🟢 GLOBAL THEME PROVIDER
// -------------------------------------------------------------------
class ThemeNotifier extends StateNotifier<ThemeMode> {
  final SupabaseClient _supabase = Supabase.instance.client;

  ThemeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkLocal = prefs.getBool('is_dark_mode');
    if (isDarkLocal != null) {
      state = isDarkLocal ? ThemeMode.dark : ThemeMode.light;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase
          .from('profiles')
          .select('is_dark_mode')
          .eq('id', user.id)
          .single();

      final isDark = response['is_dark_mode'] as bool? ?? false;
      state = isDark ? ThemeMode.dark : ThemeMode.light;
      await prefs.setBool('is_dark_mode', isDark);
    } catch (e) {
      debugPrint("Theme fetch error: $e");
    }
  }

  Future<void> toggleTheme(bool isDark) async {
    state = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', isDark);

    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        await _supabase.from('profiles').update({'is_dark_mode': isDark}).eq('id', user.id);
      } catch (e) {
        debugPrint("Theme sync error: $e");
      }
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _configureLocalTimeZone() async {
  tzData.initializeTimeZones();
  final String timeZoneName = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timeZoneName));
}

// ===================================================================
// 🟢 NEW: BACKGROUND BOOT SEQUENCE
// We moved the heavy database and network tasks here so they don't block the UI!
// ===================================================================
Future<void> initializeHeavySystems() async {
  await _configureLocalTimeZone();
  await HypeNotificationService.init();

  final appSupportDir = await getApplicationSupportDirectory();
  Hive.init(appSupportDir.path);

  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(TripAdapter());
  if (!Hive.isAdapterRegistered(TripStyleAdapter().typeId)) Hive.registerAdapter(TripStyleAdapter());
  if (!Hive.isAdapterRegistered(PlaceIdeaAdapter().typeId)) Hive.registerAdapter(PlaceIdeaAdapter());
  if (!Hive.isAdapterRegistered(ItineraryItemAdapter().typeId)) Hive.registerAdapter(ItineraryItemAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(ItineraryStatusAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(VisitTimeAdapter());
  if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(ChatMessageAdapter());
  if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(ChatRoleAdapter());
  if (!Hive.isAdapterRegistered(22)) Hive.registerAdapter(AIPlaceAdapter());

  // Using Future.wait to open all boxes simultaneously for maximum speed
  await Future.wait([
    Hive.openBox<Trip>('trips'),
    Hive.openBox<PlaceIdea>('place_ideas'),
    Hive.openBox<ItineraryItem>('itinerary'),
    Hive.openBox<List>('chat_history'),
  ]);

  await HypeNotificationService.syncAllAlarms();
  print("✅ Heavy Systems & Notifications synced successfully.");
}

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  //FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 🟢 BARE MINIMUM TO START THE UI
  // We only load the env and initialize the Supabase client so ThemeNotifier doesn't crash.
  await dotenv.load(fileName: "assets/place_placeholders/.env");
  await SupabaseService.initialize();

  // 🟢 BOOT THE UI INSTANTLY
  runApp(
    const ProviderScope(
      child: DynamicEdgeToEdgeWrapper(),
    ),
  );

  SupabaseService.client.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    if (event == AuthChangeEvent.passwordRecovery) {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const UpdatePasswordScreen()));
    }

    // 🟢 ADDED: Global Sign Out Routing
    if (event == AuthChangeEvent.signedOut) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
            (route) => false,
      );
    }
  });
}

class DynamicEdgeToEdgeWrapper extends ConsumerWidget {
  const DynamicEdgeToEdgeWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.system
        ? WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
        : themeMode == ThemeMode.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: const JourniiApp(),
    );
  }
}