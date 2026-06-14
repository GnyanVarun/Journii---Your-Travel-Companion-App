import 'dart:async'; // Import for Timeout
import 'dart:convert';
import 'dart:io'; // Import for SocketException
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/trips/ai_itinerary_model.dart';
import '../config/api_config.dart';

class AITravelService {
  // Increased timeout because AI generation takes time (10-30s)
  static const Duration _requestTimeout = Duration(seconds: 60);

  // --- OLD METHOD (Can be removed if you only use chat, but keeping for safety) ---
  Future<AIItineraryResponse> generateItinerary(String prompt) async {
    try {
      // FIX: Added [0] index to prevent evaluating the whole List as a string
      print('🚀 Sending request to: ${ApiConfig.baseUrls[0]}/generate');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrls[0]}/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return AIItineraryResponse.fromJson(decoded);
      } else {
        print('❌ Server Error: ${response.statusCode} - ${response.body}');
        throw Exception('Server error: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Could not connect to server. Check your IP address!');
    } on TimeoutException {
      throw Exception('AI took too long to respond. Please try again.');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  // --- 🆕 NEW METHOD: Supports Chat History with Supabase Fallback ---
  Future<AIItineraryResponse> generateItineraryWithHistory(
      List<Map<String, String>> history) async {

    Exception? lastError;

    // ---------------------------------------------------------
    // ATTEMPT 1: Loop through Primary Backends (Railway)
    // ---------------------------------------------------------
    for (final baseUrl in ApiConfig.baseUrls) {
      final url = Uri.parse('$baseUrl/generate');
      print("🌐 Trying backend: $url");

      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'history': history}),
        ).timeout(_requestTimeout);

        if (response.statusCode == 200) {
          print("✅ Success from: $baseUrl");
          print("📥 RAW SERVER RESPONSE: ${response.body}");

          final data = jsonDecode(response.body);
          return AIItineraryResponse.fromJson(data);
        } else {
          print("❌ Server Error from $baseUrl: ${response.statusCode}");
          lastError = Exception('Server error: ${response.statusCode}');
        }

      } catch (e) {
        print("❌ Backend failed: $baseUrl");
        print("❌ Error: $e");
        lastError = Exception('Failed backend: $baseUrl');
      }
    }

    // ---------------------------------------------------------
    // ATTEMPT 2: Fallback Engine (Supabase Edge Function)
    // ---------------------------------------------------------
    print("⚡ Railway backends exhausted or expired. Rerouting to Supabase Edge Function...");

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'gemini-engine/generate',
        body: {'history': history},
      );

      if (response.data != null) {
        print("✅ Success from Supabase Edge Function fallback!");

        // Supabase response.data arrives pre-parsed as a Map<String, dynamic>
        final Map<String, dynamic> data = response.data;
        return AIItineraryResponse.fromJson(data);
      } else {
        lastError = Exception("Supabase invoked successfully but returned null data.");
      }
    } on FunctionException catch (e) {
      print("🔥 Supabase Edge Function failed [${e.status}]: ${e.reasonPhrase}");
      print("🔥 Error Details: ${e.details}");
      // FIX: Correctly captured the specific Supabase error phrase here
      lastError = Exception("Supabase Function Error: ${e.reasonPhrase}");
    } catch (e) {
      print("🔥 Critical Error during Supabase Fallback: $e");
      // FIX: Changed e.reasonPhrase to a safe string representation of the exception
      lastError = Exception("Supabase Fallback Error: $e");
    }

    // If both completely collapse, throw the final gathered exception
    throw lastError ?? Exception("All backend systems failed.");
  }

  // 🧠 SMART INTEL FETCH (V4: Multi-Tier Failover + Cache Healing + Secure Backend)
  static Future<Map<String, dynamic>> fetchTripIntel(String destination) async {
    final cleanCity = destination.trim().toLowerCase();
    final supabase = Supabase.instance.client;
    Map<String, dynamic>? intelData;
    bool needToUpdateCache = false;

    // ---------------------------------------------------------
    // STAGE 1: 🕵️‍♂️ CHECK CACHE (Fast & Free)
    // ---------------------------------------------------------
    try {
      final cachedData = await supabase
          .from('city_intel')
          .select('data')
          .eq('city_name', cleanCity)
          .maybeSingle();

      if (cachedData != null) {
        final data = cachedData['data'] as Map<String, dynamic>;

        // 🛠️ SELF-HEALING CHECK (V3): We check for BOTH 'logistics' AND 'magic_moment'.
        final hasLogistics = data.containsKey('logistics') && (data['logistics'] as List).isNotEmpty;
        final hasMagic = data.containsKey('magic_moment');

        if (hasLogistics && hasMagic) {
          print("⚡ CACHE HIT: Loaded $cleanCity (V3 - All Features Ready).");
          return data;
        } else {
          print("♻️ OUTDATED DATA: Refreshing $cleanCity to add Magic Moment...");
          needToUpdateCache = true;
        }
      } else {
        print("🔍 CACHE MISS: No data found for $cleanCity. Running fallback pipelines...");
        needToUpdateCache = true;
      }
    } catch (dbError) {
      print("⚠️ Cache Check Failed: $dbError");
      needToUpdateCache = true;
    }

    // ---------------------------------------------------------
    // STAGE 2: Primary Backends Tier (Railway Container)
    // ---------------------------------------------------------
    for (final baseUrl in ApiConfig.baseUrls) {
      final url = Uri.parse('$baseUrl/intel');
      print("🌐 Trying primary backend intel route: $url");

      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'destination': cleanCity}),
        ).timeout(_requestTimeout);

        if (response.statusCode == 200) {
          print("✅ Success: Intel fetched via Railway from $baseUrl");
          intelData = jsonDecode(response.body) as Map<String, dynamic>;
          break; // Data successfully retrieved, break out of loop
        } else {
          print("❌ Server Error from Intel Backend $baseUrl: ${response.statusCode}");
        }
      } catch (e) {
        print("❌ Primary Intel Backend failed: $baseUrl, Error: $e");
      }
    }

    // ---------------------------------------------------------
    // STAGE 3: Secondary Backend Fallback Tier (Supabase Edge Function)
    // ---------------------------------------------------------
    if (intelData == null) {
      print("⚡ Railway options exhausted. Routing intel request to Supabase Edge Function...");
      try {
        final response = await supabase.functions.invoke(
          'gemini-engine/intel',
          body: {'destination': cleanCity},
        );

        if (response.data != null) {
          print("✅ Success: Intel fetched via Supabase Edge Function Fallback!");
          intelData = response.data as Map<String, dynamic>;
        }
      } on FunctionException catch (e) {
        print("🔥 Supabase Intel Function failed [${e.status}]: ${e.reasonPhrase}");
        print("🔥 Error Details: ${e.details}");
      } catch (e) {
        print("🔥 Critical Error during Supabase Intel Fallback: $e");
      }
    }

    // ---------------------------------------------------------
    // STAGE 4: Client Safety Net Tier (Original Direct Gemini Call)
    // ---------------------------------------------------------
    if (intelData == null) {
      print("🤖 ASKING GEMINI DIRECTLY (Safety Net Fallback) for $cleanCity...");
      try {
        final apiKey = dotenv.env['GEMINI_API_KEY'];
        if (apiKey == null || apiKey.isEmpty) throw Exception("GEMINI_API_KEY missing");

        // Using 2.0-flash for speed and JSON reliability
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey');

        // 🚀 PROMPT UPDATED: Requests 'magic_moment' object specifically
        final prompt = """
        ACT AS: A local travel expert and photographer.
        TASK: Provide exclusive survival & experience intel for: $destination.
        
        CRITICAL - GENERATE THESE 3 SECTIONS:
        
        1. "logistics": Exactly 3 items.
           - type="math": Pass vs Single Ticket comparison.
           - type="position": Best train car to sit in.
           - type="alert": Strike or delay warning.
           
        2. "magic_moment": The ONE singular best place and time to be for a photo/memory.
           - title: The Name of the Spot.
           - time: Best time (e.g. "Sunset @ 18:30" or "Early Morning").
           - desc: Specific advice (e.g. "Bring wine, sit on the lower steps").

        3. Standard arrays: "laws", "scams", "hacks".

        RETURN JSON ONLY. NO MARKDOWN. Structure:
        {
          "laws": [{"title": "Law", "desc": "Desc", "fine": "€XX"}],
          "logistics": [
            { "type": "math", "title": "Pass Strategy", "highlight": "Save €XX", "subtitle": "Pass Name", "detail": "Math" },
            { "type": "position", "title": "Metro Hack", "highlight": "Rear Car", "subtitle": "Fast Exit", "detail": "Why" },
            { "type": "alert", "title": "Advisory", "highlight": "Status", "subtitle": "Impact", "detail": "Info" }
          ],
          "magic_moment": {
            "title": "Piazzale Michelangelo",
            "time": "Sunset • 19:15",
            "desc": "Arrive 30 mins early. The best view is actually from the rose garden below."
          },
          "scams": [{"title": "Scam", "avoid"}],
          "hacks": ["Tip 1", "Tip 2"],
          "sos": "112"
        }
      """;

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            "contents": [{ "parts": [{ "text": prompt }] }]
          }),
        );

        if (response.statusCode != 200) {
          throw Exception("AI API Error: ${response.body}");
        }

        // 3. 🧹 CLEAN & PARSE JSON
        final data = jsonDecode(response.body);
        String rawText = data['candidates'][0]['content']['parts'][0]['text'];

        final startIndex = rawText.indexOf('{');
        final endIndex = rawText.lastIndexOf('}');

        if (startIndex == -1 || endIndex == -1) throw Exception("Invalid JSON");

        final cleanJsonString = rawText.substring(startIndex, endIndex + 1);
        intelData = jsonDecode(cleanJsonString) as Map<String, dynamic>;

      } catch (e) {
        print("⚠️ FATAL CLIENT-SIDE FALLBACK ERROR: $e");
        return {
          "laws": [],
          "logistics": [],
          "magic_moment": null,
          "scams": [],
          "hacks": ["Error loading intel: $e"],
          "sos": "112"
        };
      }
    }

    // ---------------------------------------------------------
    // STAGE 5: 💾 SYNCHRONIZE DATABASE CACHE (Fixed with Upsert)
    // ---------------------------------------------------------
    if (intelData != null && needToUpdateCache) {
      try {
        await supabase.from('city_intel').upsert({
          'city_name': cleanCity,
          'data': intelData
        });
        print("💾 UPGRADED CACHE for $cleanCity to V3.");
      } catch (saveError) {
        print("⚠️ Supabase Save Warning: $saveError");
      }
    }

    return intelData;
  }
}