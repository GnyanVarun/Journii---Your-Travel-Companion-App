import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import fetch from "node-fetch";

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;
const API_KEY = process.env.GEMINI_API_KEY;

if (!API_KEY) {
  console.error("❌ GEMINI_API_KEY missing in .env");
  process.exit(1);
}

// Using the flash model for speed
const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

app.get("/", (_req, res) => {
  res.send("🚀 Gemini backend running (Itinerary + Serendipity Engine)");
});

/* ---------------------------------------------------
   HELPER: Gemini Caller (Now supports History!)
--------------------------------------------------- */
async function callGeminiWithHistory(history) {
  console.log("📤 Sending history to Gemini...");

  // 1. Convert Flutter history to Gemini format
  const contents = history.map((msg) => ({
    role: msg.role === 'ai' ? 'model' : 'user',
    parts: [{ text: msg.text }]
  }));

  // 2. The "Brain" (System Instruction)
  const systemInstruction = `
    You are Journii, a travel assistant powered by strict data logic.
    Your goal is to generate valid, geocodable travel itineraries.

    ⭐ CRITICAL OUTPUT RULE (ALWAYS JSON):
    - You MUST ALWAYS return valid JSON.
    - NEVER return plain text.
    - If the user is just chatting, put your reply in the "summary" field and return an empty "days" array.

    ⭐ STRICT GPS-COMPATIBLE NAMING RULES (CRITICAL):
    The "name" field MUST be compatible with a GPS search engine (like OpenStreetMap).

    ❌ BAD NAMES (DO NOT USE):
    - "Dinner at Paradise Biryani"
    - "Laad Bazaar (Choodi Bazaar)"
    - "Mozamjahi Market" (Phonetic/Colloquial)

    ✅ GOOD NAMES (USE THESE ONLY):
    - "Paradise Biryani"
    - "Laad Bazaar"
    - "Moazzam Jahi Market" (Official Map Spelling)

    ⭐ PLANNING RULES:
    1. **NO REPETITION**: You MUST NOT schedule the same place on multiple days.
    2. **LOGICAL FLOW**: Group nearby places together.
    3. **COMPLETE ITINERARY**: Generate a plan for every single day requested.

    JSON STRUCTURE (Strictly follow this):
    {
      "summary": "Short, exciting summary of the trip.",
      "days": [
        {
          "day": 1,
          "places": [
            {
              "name": "Official Map Name",
              "description": "Why visit?",
              "bestTime": "Morning | Afternoon | Evening",
              "visitTip": "Pro-tip for this place."
            }
          ]
        }
      ]
    }
  `;

  // 3. Inject Instruction
  if (contents.length > 0) {
    contents[0].parts[0].text = systemInstruction + "\n\nUSER SAYS:\n" + contents[0].parts[0].text;
  } else {
    contents.push({ role: 'user', parts: [{ text: systemInstruction }] });
  }

  try {
    const response = await fetch(`${GEMINI_URL}?key=${API_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: contents,
        generationConfig: {
          temperature: 0.3,
          responseMimeType: "application/json",
        },
      }),
    });

    if (!response.ok) {
        const errorText = await response.text();
        console.error(`❌ Gemini API Error [${response.status}]:`, errorText);
        return null;
    }

    const data = await response.json();
    return data?.candidates?.[0]?.content?.parts?.[0]?.text ?? null;

  } catch (error) {
    console.error("❌ Network Exception in callGemini:", error);
    return null;
  }
}

/* ---------------------------------------------------
   ROUTE 1: POST /generate (Itinerary Generator)
--------------------------------------------------- */
app.post("/generate", async (req, res) => {
  try {
    console.log("\n⭐ /generate endpoint HIT");

    const { history } = req.body;

    if (!history || !Array.isArray(history)) {
      return res.status(400).json({ success: false, error: "History array required" });
    }

    const rawText = await callGeminiWithHistory(history);

    if (!rawText) {
      return res.json({
        summary: "I'm having trouble connecting to the travel brain right now. 🧠💤",
        places: [],
      });
    }

    // 🧹 JSON CLEANER
    let parsed;
    try {
      const firstBrace = rawText.indexOf('{');
      const lastBrace = rawText.lastIndexOf('}');

      if (firstBrace !== -1 && lastBrace !== -1) {
        const jsonString = rawText.substring(firstBrace, lastBrace + 1);
        parsed = JSON.parse(jsonString);
      } else {
        return res.json({ summary: rawText, places: [] });
      }
    } catch (e) {
      console.error("❌ Failed to parse Gemini JSON.", rawText);
      return res.status(500).json({ success: false, error: "Invalid JSON from Gemini" });
    }

    // Normalize Data
    const places = [];
    const seenNames = new Set();

    if (parsed.days && Array.isArray(parsed.days)) {
      parsed.days.forEach((dayObj) => {
        const dayNumber = dayObj.day ?? 1;
        if (Array.isArray(dayObj.places)) {
          dayObj.places.forEach((p) => {
            const rawName = p.name ?? "";
            const cleanName = rawName.trim().toLowerCase();

            if (cleanName && !seenNames.has(cleanName)) {
              seenNames.add(cleanName);
              places.push({
                name: p.name,
                description: p.description ?? "",
                day: dayNumber,
                bestTime: p.bestTime ?? "Morning",
                visitTip: p.visitTip ?? null,
              });
            }
          });
        }
      });
    }

    console.log(`✅ Returning ${places.length} unique places`);

    return res.json({
      summary: parsed.summary ?? "Here is your itinerary! ✨",
      places,
    });

  } catch (err) {
    console.error("🔥 Critical Backend Error:", err);
    return res.status(500).json({ success: false, error: "Backend failure" });
  }
});


/* ---------------------------------------------------
   ROUTE 2: GET /api/daily-destination (Real-Time Discover Feed)
--------------------------------------------------- */
app.get('/api/daily-destination', async (req, res) => {
  try {
    console.log("🌍 Fetching daily destination from Gemini...");
    const prompt = `Act as a travel expert. Give me one random, highly trending, beautiful global travel destination for today.
    Return ONLY a raw JSON object (no markdown, no backticks) with two keys: "destination" (City, Country) and "description" (A short 10-word hook about why it is beautiful).`;

    // 🟢 Fix: Using your existing raw fetch logic instead of the missing SDK
    const response = await fetch(`${GEMINI_URL}?key=${API_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.8, // Slightly higher temp so it gives different cities
          responseMimeType: "application/json",
        },
      }),
    });

    if (!response.ok) {
        throw new Error(`Gemini API Error: ${response.status}`);
    }

    const data = await response.json();
    let responseText = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";

    // Clean up the response in case Gemini includes markdown formatting
    responseText = responseText.trim();
    if (responseText.startsWith('```json')) {
      responseText = responseText.replace(/```json/g, '').replace(/```/g, '').trim();
    } else if (responseText.startsWith('```')) {
      responseText = responseText.replace(/```/g, '').trim();
    }

    // Parse the JSON directly
    const destinationData = JSON.parse(responseText);
    res.json(destinationData);

  } catch (error) {
    console.error("❌ Gemini Daily Destination Error:", error);
    // Safe fallback so the Flutter app never crashes
    res.json({
        destination: "Kyoto, Japan",
        description: "Experience the timeless beauty of ancient temples and bamboo forests."
    });
  }
});


/* ---------------------------------------------------
   🧠 IN-MEMORY DATABASE (For Social Drops)
   In production, you would move this to Supabase/Postgres
--------------------------------------------------- */
//const socialDrops = []; // Stores all user memories

/* ---------------------------------------------------
   📍 ROUTE 3: POST /api/drops/create
   User leaves a memory at their current location
--------------------------------------------------- */
/* app.post("/api/drops/create", (req, res) => { ... }); */

/* ---------------------------------------------------
   📍 ROUTE 4: POST /api/drops/nearby
   Find memories within 500 meters
--------------------------------------------------- */
/* app.post("/api/drops/nearby", (req, res) => { ... }); */


// Crash Protectors
process.on('uncaughtException', (err) => console.error('🔥 UNCAUGHT EXCEPTION!', err));
process.on('unhandledRejection', (reason) => console.error('🔥 UNHANDLED REJECTION!', reason));

// 🟢 Fix: Safely extracted from the comment block so the server actually stays alive!
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 Backend running at http://0.0.0.0:${PORT}`);
});