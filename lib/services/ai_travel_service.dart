import 'dart:async'; // Import for Timeout
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/trips/ai_itinerary_model.dart';

class AITravelService {
      // Increased timeout because AI generation takes time (10-30s)
      //static const Duration _requestTimeout = Duration(minutes: 5);

      // Converts the Supabase Edge Function response into the Map expected
      // by AIItineraryResponse.fromJson().
      Map<String, dynamic> _decodeFunctionResponse(dynamic responseData) {
            if (responseData is Map<String, dynamic>) {
                  return responseData;
            }

            if (responseData is Map) {
                  return Map<String, dynamic>.from(responseData);
            }

            if (responseData is String) {
                  final decoded = jsonDecode(responseData);
                  if (decoded is Map) {
                        return Map<String, dynamic>.from(decoded);
                  }
            }

            throw const FormatException(
                  'Supabase Edge Function returned an invalid JSON response.',
            );
      }

      // Shared NVIDIA -> Gemini Edge Function routing for itinerary generation.
      Future<AIItineraryResponse> _generateItineraryUsingSupabase(
          List<Map<String, String>> history,
          ) async {
            Exception? lastError;

            const functionNames = <String>[
                  'nvidia-engine/generate',
                  'gemini-engine/generate',
            ];

            for (final functionName in functionNames) {
                  final isNvidia = functionName == 'nvidia-engine/generate';

                  if (isNvidia) {
                        print('🚀 Sending itinerary request to NVIDIA Supabase Edge Function...');
                  } else {
                        print('⚡ NVIDIA unavailable. Routing itinerary request to Gemini Edge Function...');
                  }

                  try {
                        final response = await Supabase.instance.client.functions.invoke(
                              functionName,
                              body: {'history': history},
                        );

                        if (response.data == null) {
                              throw Exception(
                                    '$functionName invoked successfully but returned null data.',
                              );
                        }

                        final Map<String, dynamic> data =
                        _decodeFunctionResponse(response.data);

                        // Treat an explicit unsuccessful response as a failed provider call
                        // so the next configured Edge Function can be attempted.
                        if (data['success'] == false) {
                              throw Exception(
                                    data['error']?.toString() ??
                                        '$functionName returned an unsuccessful response.',
                              );
                        }

                        print('✅ Success from Supabase Edge Function: $functionName');
                        print('📥 RAW SERVER RESPONSE: ${response.data}');

                        return AIItineraryResponse.fromJson(data);
                  } on FunctionException catch (e) {
                        print(
                              '🔥 Supabase Edge Function failed [$functionName] '
                                  '[${e.status}]: ${e.reasonPhrase}',
                        );
                        print('🔥 Error Details: ${e.details}');
                        lastError = Exception(
                              '$functionName failed: ${e.reasonPhrase}',
                        );
                  } on TimeoutException catch (e) {
                        print('⏱️ Supabase Edge Function timed out [$functionName]: $e');
                        lastError = Exception('$functionName timed out: $e');
                  } catch (e) {
                        print('❌ Supabase Edge Function failed [$functionName]: $e');
                        lastError = Exception('$functionName failed: $e');
                  }
            }

            // If both NVIDIA and Gemini Edge Functions fail, throw the final error.
            throw lastError ?? Exception('All itinerary backend systems failed.');
      }

      // --- OLD METHOD (Kept for compatibility with existing callers) ---
      // The NVIDIA backend expects conversation history, so the single prompt
      // is wrapped in the same history format used by generateItineraryWithHistory().
      Future<AIItineraryResponse> generateItinerary(String prompt) async {
            final history = <Map<String, String>>[
                  {'role': 'user', 'text': prompt},
            ];

            return _generateItineraryUsingSupabase(history);
      }

      // --- NEW METHOD: Supports Chat History with NVIDIA -> Gemini Supabase Fallback ---
      Future<AIItineraryResponse> generateItineraryWithHistory(
          List<Map<String, String>> history,
          ) async {
            return _generateItineraryUsingSupabase(history);
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
            // INTEL PROMPT: Shared by NVIDIA (primary) and Gemini (fallback)
            // ---------------------------------------------------------
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

            // ---------------------------------------------------------
            // STAGE 2: Primary Intel Provider (Direct NVIDIA NIM API)
            // ---------------------------------------------------------
            try {
                  print("🚀 Sending trip intel request directly to NVIDIA NIM for $cleanCity...");

                  final nvidiaApiKey = dotenv.env['NVIDIA_API_KEY'];
                  if (nvidiaApiKey == null || nvidiaApiKey.isEmpty) {
                        throw Exception("NVIDIA_API_KEY missing from the app environment.");
                  }

                  final nvidiaUrl = Uri.parse(
                        'https://integrate.api.nvidia.com/v1/chat/completions',
                  );

                  final response = await http.post(
                        nvidiaUrl,
                        headers: {
                              'Content-Type': 'application/json',
                              'Authorization': 'Bearer $nvidiaApiKey',
                        },
                        body: jsonEncode({
                              'model': 'nvidia/nemotron-3.5-lightning-30b-a3b',
                              'messages': [
                                    {
                                          'role': 'user',
                                          'content': prompt,
                                    },
                              ],
                              'temperature': 0.3,
                              'max_tokens': 4096,
                              'stream': false,
                              'chat_template_kwargs': {
                                    'enable_thinking': false,
                              },
                              'response_format': {
                                    'type': 'json_object',
                              },
                        }),
                  ).timeout(const Duration(seconds: 110));

                  if (response.statusCode != 200) {
                        throw Exception(
                              'NVIDIA API Error [${response.statusCode}]: ${response.body}',
                        );
                  }

                  final responseData = jsonDecode(response.body);
                  final choices = responseData['choices'];
                  if (choices is! List || choices.isEmpty) {
                        throw const FormatException('NVIDIA returned no completion choices.');
                  }

                  final rawContent = choices[0]?['message']?['content'];
                  final rawText = rawContent is String ? rawContent : '';
                  if (rawText.trim().isEmpty) {
                        throw const FormatException('NVIDIA returned an empty Intel response.');
                  }

                  final startIndex = rawText.indexOf('{');
                  final endIndex = rawText.lastIndexOf('}');
                  if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
                        throw const FormatException('NVIDIA returned invalid Intel JSON.');
                  }

                  final cleanJsonString = rawText.substring(startIndex, endIndex + 1);
                  final parsedIntel = jsonDecode(cleanJsonString);
                  if (parsedIntel is! Map) {
                        throw const FormatException('NVIDIA Intel response is not a JSON object.');
                  }

                  intelData = Map<String, dynamic>.from(parsedIntel);
                  print("✅ Trip Intel successfully generated by NVIDIA NIM for $cleanCity.");
            } on TimeoutException catch (e) {
                  print("⏱️ NVIDIA Intel request timed out: $e");
                  intelData = null;
            } catch (e) {
                  print("⚠️ NVIDIA Intel request failed: $e");
                  intelData = null;
            }

            // ---------------------------------------------------------
            // STAGE 3: Fallback Provider (Direct Gemini API)
            // ---------------------------------------------------------
            if (intelData == null) {
                  print("⚡ NVIDIA unavailable. Routing trip intel directly to Gemini for $cleanCity...");
                  try {
                        final apiKey = dotenv.env['GEMINI_API_KEY'];
                        if (apiKey == null || apiKey.isEmpty) {
                              throw Exception("GEMINI_API_KEY missing");
                        }

                        // Using Gemini 2.5 Flash for the existing JSON response mechanism.
                        final url = Uri.parse(
                              'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
                        );

                        final response = await http.post(
                              url,
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({
                                    "contents": [
                                          {
                                                "parts": [
                                                      {"text": prompt}
                                                ]
                                          }
                                    ]
                              }),
                        );

                        if (response.statusCode != 200) {
                              throw Exception("AI API Error: ${response.body}");
                        }

                        // Clean and parse the JSON returned by Gemini.
                        final data = jsonDecode(response.body);
                        final rawText = data['candidates'][0]['content']['parts'][0]['text'] as String;

                        final startIndex = rawText.indexOf('{');
                        final endIndex = rawText.lastIndexOf('}');
                        if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
                              throw const FormatException("Gemini returned invalid Intel JSON.");
                        }

                        final cleanJsonString = rawText.substring(startIndex, endIndex + 1);
                        final parsedIntel = jsonDecode(cleanJsonString);
                        if (parsedIntel is! Map) {
                              throw const FormatException("Gemini Intel response is not a JSON object.");
                        }

                        intelData = Map<String, dynamic>.from(parsedIntel);
                        print("✅ Trip Intel successfully generated by direct Gemini API for $cleanCity.");
                  } catch (e) {
                        print("⚠️ FATAL CLIENT-SIDE INTEL GENERATION ERROR: $e");
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
            // STAGE 4: 💾 SYNCHRONIZE DATABASE CACHE (Fixed with Upsert)
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