import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

// ✅ NEW IMPORT: Bring in the global navigatorKey and themeProvider from main.dart
import 'main.dart';

// 1. IMPORT YOUR SCREENS & PROVIDER
import 'auth/auth_screen.dart';
import 'auth/auth_provider.dart';
import 'splash/splash_screen.dart'; // 🟢 NEW IMPORT: Bring in your new animated splash screen

// The Main Page (Container for Tabs)
import '../home/main_page.dart';

class JourniiApp extends ConsumerWidget {
  const JourniiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 🟢 1. WATCH THE THEME STATE LIVE
    final themeMode = ref.watch(themeProvider);

    // Note: userAsync can remain here if needed elsewhere, but it's no longer binding the home screen switch.
    final userAsync = ref.watch(userProvider);

    return MaterialApp(
      // ✅ ADDED THIS LINE: Attach the global key for Deep Linking
      navigatorKey: navigatorKey,

      title: 'Journii',
      debugShowCheckedModeBanner: false,

      // 🟢 2. APPLY THE THEME MODE
      themeMode: themeMode,

      // 🟢 3. LIGHT THEME DEFINITION
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4), // Deep Purple
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF9F9FB), // Standard Journii Light Bg
        useMaterial3: true,
        textTheme: GoogleFonts.outfitTextTheme(),
      ),

      // 🟢 4. DARK THEME DEFINITION (Required for dark mode to work)
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4), // Deep Purple
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F13), // Standard Journii Dark Bg
        useMaterial3: true,
        // Ensures Outfit font uses white text in dark mode
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ),

      // 🟢 UPDATED: The app now instantly boots into the custom animated splash screen
      home: const SplashScreen(),
    );
  }
}