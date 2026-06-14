import 'trip_model.dart';
import 'trip_style.dart';

class AIPromptBuilder {
  static String buildInitialPrompt(Trip trip) {
    // 1️⃣ Duration Calculation (Unchanged)
    final int duration = trip.durationDays ??
        _extractDaysFromText(trip.title) ??
        _extractDaysFromText(trip.description) ??
        3;

    // 2️⃣ DYNAMIC PERSONA LOGIC (The New Vibe Engine)
    String personaInstruction;
    String vibeEmoji;

    switch (trip.curiosityLevel) {
      case 1: // THE TOURIST (Classic)
        vibeEmoji = "📸";
        personaInstruction = """
        ACT AS: A friendly, classic tour guide.
        FOCUS: Top landmarks, famous spots, and "must-see" bucket list items.
        TONE: Welcoming and informative.
        RULE: Suggest the safest, most popular hits (e.g., Colosseum, Eiffel Tower).
        """;
        break;

      case 3: // THE INSIDER (Skywork Level)
        vibeEmoji = "🕵️‍♀️";
        personaInstruction = """
        ACT AS: An arrogant local who hates tourist traps.
        FOCUS: Hidden courtyards, secret speakeasies, optical illusions, and "deep cuts."
        TONE: Witty, "in-the-know," and sophisticated.
        RULE: IGNORE top 10 lists unless visual. Focus on "The Shot" and "The Secret."
        """;
        break;

      case 2: // THE EXPLORER (Default)
      default:
        vibeEmoji = "🧭";
        personaInstruction = """
        ACT AS: A balanced travel curator.
        FOCUS: A perfect 50/50 mix of major landmarks and 1-2 hidden gems nearby.
        TONE: Enthusiastic and fun.
        """;
        break;
    }

    final buffer = StringBuffer();

    // -------------------------------------------------------------
    // SYSTEM INSTRUCTIONS (Updated with Dynamic Persona)
    // -------------------------------------------------------------
    buffer.writeln("""
const systemInstruction = `
    You are Journii $vibeEmoji.
    $personaInstruction

    ⭐ CRITICAL RULES FOR GENERATION:
    1. **THE "INSTAGRAM" RULE**:
       - Every suggestion MUST have a "visual hook." 
       - Don't just say "Trevi Fountain." Say "Trevi Fountain at 6 AM to catch the sunrise reflection without the crowds."

    2. **MAP-FRIENDLY NAMING (OSM STRICT)**:
       - You must use the EXACT name found on OpenStreetMap.
       - If a place is obscure, provide the "Nearest Landmark" in the description to help the map find it.

    3. **STRICT JSON FORMAT**:
       - Do not be chatty. Return ONLY the JSON object.

    JSON STRUCTURE:
    {
      "summary": "A 2-sentence 'Vibe Check' of the trip. E.g., 'Rome is chaotic but magical. We are skipping the mid-day crowds to find the quiet corners.'",
      "days": [
        {
          "day": 1,
          "theme": "The cinematic side of Rome",
          "places": [
            { 
              "name": "Aventine Keyhole", 
              "description": "A secret optical illusion. Peep through this nondescript green door to see St. Peter's Dome perfectly framed by hedges.", 
              "bestTime": "Early Morning",
              "visitTip": "The line gets long after 9 AM. Go early. The view is tiny but the photo is legendary.",
              "geoContext": "Piazza dei Cavalieri di Malta" 
            }
          ]
        }
      ]
    }
  `;
""");

    // -------------------------------------------------------------
    // USER CONTEXT
    // -------------------------------------------------------------
    buffer.writeln("Primary Trip Location: ${trip.title}");
    buffer.writeln("Trip Duration: $duration days");

    // Pass the Vibe Level to the AI explicitly
    buffer.writeln("Curiosity Level: ${trip.curiosityLevel} (1=Tourist, 3=Insider)");

    if (trip.description.trim().isNotEmpty) {
      buffer.writeln("\n🚨 USER'S SPECIFIC REQUEST:");
      buffer.writeln('"${trip.description}"');
      buffer.writeln("CRITICAL RULE: You MUST tailor the itinerary to incorporate the user's specific request mentioned above. If they asked for specific themes (e.g., 'jazz bars', 'chill beaches', 'street food'), you must prioritize those while keeping the $vibeEmoji persona!");
    } else {
      buffer.writeln("\nTrip Description: (None provided – infer intent from title)");
    }

    if (trip.style != null) {
      buffer.writeln("Travel Style: ${trip.style!.label}");
    }

    // -------------------------------------------------------------
    // OUTPUT FORMATTING (Unchanged)
    // -------------------------------------------------------------
    buffer.writeln("""
TIME-OF-DAY GUIDANCE:
- For each place, specify the BEST time to visit:
  - Morning
  - Afternoon
  - Evening
- Choose based on crowds, lighting, atmosphere, and experience quality.

RETURN FORMAT:
Return STRICTLY valid JSON and NOTHING else.
""");

    // -------------------------------------------------------------
    // THE TRIGGER COMMAND (Unchanged)
    // -------------------------------------------------------------
    buffer.writeln("\nREQUEST:");
    buffer.writeln(
        "Please generate a complete $duration-day itinerary for ${trip.title} immediately. "
            "Respect the 'Curiosity Level' setting strictly. " // Added hint
            "Ensure the response is valid JSON as per your system instructions."
    );

    return buffer.toString();
  }
// ... rest of the file (helper methods) ...

  static int? _extractDaysFromText(String text) {
    if (text.isEmpty) return null;

    final regex = RegExp(r'(\d+)\s*-?\s*days?', caseSensitive: false);
    final match = regex.firstMatch(text);

    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }
}