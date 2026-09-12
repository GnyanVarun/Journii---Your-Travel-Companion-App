import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import OpenAI from "openai";

dotenv.config();

const app = express();

app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;
const NVIDIA_API_KEY = process.env.NVIDIA_API_KEY;

if (!NVIDIA_API_KEY) {
  console.error("❌ NVIDIA_API_KEY missing in .env");
  process.exit(1);
}

/* ---------------------------------------------------
   NVIDIA NIM / Nemotron Configuration
--------------------------------------------------- */

const MODEL = "nvidia/nemotron-3.5-lightning-30b-a3b";

const openai = new OpenAI({
  apiKey: NVIDIA_API_KEY,
  baseURL: "https://integrate.api.nvidia.com/v1",
});

app.get("/", (_req, res) => {
  res.send("🚀 NVIDIA NIM backend running (Itinerary + Serendipity Engine)");
});

/* ---------------------------------------------------
   SYSTEM INSTRUCTION
--------------------------------------------------- */

const SYSTEM_INSTRUCTION = `
You are Journii, a travel assistant powered by strict data logic.

Your goal is to generate valid, useful, geocodable travel itineraries.

⭐ CRITICAL OUTPUT RULE (ALWAYS JSON):
- You MUST ALWAYS return valid JSON.
- NEVER return markdown.
- NEVER return JSON inside markdown code fences.
- NEVER return plain text outside the JSON structure.
- If the user is just chatting, put the reply in the "summary" field and return an empty "days" array.

⭐ STRICT GPS-COMPATIBLE NAMING RULES:
The "name" field MUST be compatible with a GPS search engine such as OpenStreetMap or Google Maps.

❌ BAD NAMES:
- "Dinner at Paradise Biryani"
- "Laad Bazaar (Choodi Bazaar)"
- "Mozamjahi Market"

✅ GOOD NAMES:
- "Paradise Biryani"
- "Laad Bazaar"
- "Moazzam Jahi Market"

⭐ PLANNING RULES:
1. NO REPETITION:
   Do not schedule the same place on multiple days.
2. LOGICAL FLOW:
   Group geographically nearby places together.
3. COMPLETE ITINERARY:
   Generate a plan for every single day requested.
4. DO NOT INVENT:
   Prefer recognizable real-world destinations.
5. MAP-FRIENDLY:
   Use official or commonly recognized place names.
6. BEST TIME:
   Use only:
   - Morning
   - Afternoon
   - Evening

⭐ REQUIRED JSON STRUCTURE:

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

/* ---------------------------------------------------
   HELPER: Convert Flutter History -> OpenAI/NIM Format
--------------------------------------------------- */

function normalizeHistory(history) {
  return history.map((msg) => ({
    role: msg.role === "ai" ? "assistant" : "user",
    content: String(msg.text ?? ""),
  }));
}

/* ---------------------------------------------------
   HELPER: Parse JSON Returned By Nemotron
--------------------------------------------------- */

function parseJsonResponse(rawText) {
  if (!rawText) {
    throw new Error("Empty response from NVIDIA NIM");
  }

  const cleaned = String(rawText).trim();

  // First attempt: parse the complete response directly.
  try {
    return JSON.parse(cleaned);
  } catch (_) {
    // Continue to fallback extraction.
  }

  // Fallback: remove markdown code fences if the model included them.
  const withoutCodeFence = cleaned
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  try {
    return JSON.parse(withoutCodeFence);
  } catch (_) {
    // Continue to object extraction.
  }

  // Final fallback: extract the first complete JSON object.
  const firstBrace = withoutCodeFence.indexOf("{");
  const lastBrace = withoutCodeFence.lastIndexOf("}");

  if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
    const jsonString = withoutCodeFence.substring(
      firstBrace,
      lastBrace + 1
    );

    return JSON.parse(jsonString);
  }

  throw new Error("No valid JSON object found in model response.");
}

/* ---------------------------------------------------
   HELPER: Call NVIDIA NIM With Conversation History
--------------------------------------------------- */

async function callNemotronWithHistory(history) {
  console.log("📤 Sending history to NVIDIA NIM...");

  const messages = [
    {
      role: "system",
      content: SYSTEM_INSTRUCTION,
    },
    ...normalizeHistory(history),
  ];

  try {
    const completion = await openai.chat.completions.create({
      model: MODEL,
      messages,

      // Lower temperature helps maintain consistent JSON.
      temperature: 0.3,

      // Enough room for itinerary generation.
      max_tokens: 4096,

      // Disable visible/hidden reasoning for this structured response.
      chat_template_kwargs: {
        enable_thinking: false,
      },

      // Ask the model for JSON output.
      response_format: {
        type: "json_object",
      },
    });

    const content = completion?.choices?.[0]?.message?.content;

    if (!content) {
      console.error("❌ NVIDIA NIM returned an empty response.");
      return null;
    }

    return content;
  } catch (error) {
    console.error("❌ NVIDIA NIM request failed:");

    if (error?.response) {
      console.error(error.response);
    }

    console.error(error);

    return null;
  }
}

/* ---------------------------------------------------
   ROUTE 1: POST /generate
   Itinerary Generator
--------------------------------------------------- */

app.post("/generate", async (req, res) => {
  try {
    console.log("\n⭐ /generate endpoint HIT");

    const { history } = req.body;

    if (!Array.isArray(history)) {
      return res.status(400).json({
        success: false,
        error: "History array required",
      });
    }

    const rawText = await callNemotronWithHistory(history);

    if (!rawText) {
      return res.status(502).json({
        success: false,
        summary:
          "I'm having trouble connecting to the travel brain right now. 🧠💤",
        places: [],
      });
    }

    let parsed;

    try {
      parsed = parseJsonResponse(rawText);
    } catch (error) {
      console.error("❌ Failed to parse NVIDIA NIM JSON.");
      console.error("Raw NIM response:", rawText);
      console.error("Parse error:", error.message);

      return res.status(502).json({
        success: false,
        error: "Invalid JSON from NVIDIA NIM",
        places: [],
      });
    }

    /* ---------------------------------------------------
       Normalize Itinerary Data
    --------------------------------------------------- */

    const places = [];
    const seenNames = new Set();

    if (Array.isArray(parsed.days)) {
      parsed.days.forEach((dayObj) => {
        const dayNumber = dayObj?.day ?? 1;

        if (!Array.isArray(dayObj?.places)) {
          return;
        }

        dayObj.places.forEach((place) => {
          const rawName = String(place?.name ?? "").trim();
          const cleanName = rawName.toLowerCase();

          if (!cleanName || seenNames.has(cleanName)) {
            return;
          }

          seenNames.add(cleanName);

          places.push({
            name: rawName,
            description: String(place?.description ?? ""),
            day: dayNumber,
            bestTime: String(place?.bestTime ?? "Morning"),
            visitTip: place?.visitTip ?? null,
          });
        });
      });
    }

    console.log(`✅ Returning ${places.length} unique places`);

    return res.json({
      success: true,
      summary: parsed?.summary ?? "Here is your itinerary! ✨",
      places,
    });
  } catch (error) {
    console.error("🔥 Critical /generate Error:", error);

    return res.status(500).json({
      success: false,
      error: "Backend failure",
      places: [],
    });
  }
});

/* ---------------------------------------------------
   ROUTE 2: GET /api/daily-destination
   Real-Time Discover Feed
--------------------------------------------------- */

app.get("/api/daily-destination", async (_req, res) => {
  try {
    console.log("🌍 Generating daily destination with NVIDIA NIM...");

    const prompt = `
Act as a travel inspiration expert.

Choose one beautiful and interesting global travel destination.

Return ONLY a valid JSON object with exactly these two keys:

{
  "destination": "City, Country",
  "description": "A short 10-word hook about why it is beautiful."
}

Do not use markdown.
Do not use code fences.
`;

    const completion = await openai.chat.completions.create({
      model: MODEL,
      messages: [
        {
          role: "system",
          content:
            "You are Journii's destination discovery engine. Return valid JSON only.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],

      temperature: 0.8,
      max_tokens: 500,

      chat_template_kwargs: {
        enable_thinking: false,
      },

      response_format: {
        type: "json_object",
      },
    });

    const responseText =
      completion?.choices?.[0]?.message?.content ?? "";

    if (!responseText) {
      throw new Error("Empty response from NVIDIA NIM");
    }

    const destinationData = parseJsonResponse(responseText);

    return res.json({
      destination:
        destinationData?.destination ?? "Kyoto, Japan",
      description:
        destinationData?.description ??
        "Experience the timeless beauty of ancient temples and bamboo forests.",
    });
  } catch (error) {
    console.error("❌ NVIDIA NIM Daily Destination Error:", error);

    // Safe fallback so the Flutter app doesn't crash.
    return res.json({
      destination: "Kyoto, Japan",
      description:
        "Experience the timeless beauty of ancient temples and bamboo forests.",
    });
  }
});

/* ---------------------------------------------------
   SOCIAL DROPS
   Currently disabled
--------------------------------------------------- */

// const socialDrops = [];

/*
app.post("/api/drops/create", (req, res) => {
  // Future implementation
});

app.post("/api/drops/nearby", (req, res) => {
  // Future implementation
});
*/

/* ---------------------------------------------------
   CRASH PROTECTORS
--------------------------------------------------- */

process.on("uncaughtException", (error) => {
  console.error("🔥 UNCAUGHT EXCEPTION!", error);
});

process.on("unhandledRejection", (reason) => {
  console.error("🔥 UNHANDLED REJECTION!", reason);
});

/* ---------------------------------------------------
   START SERVER
--------------------------------------------------- */

app.listen(PORT, "0.0.0.0", () => {
  console.log(`\n🚀 Journii NVIDIA NIM backend running on port ${PORT}`);
  console.log(`🤖 Model: ${MODEL}`);
  console.log(`🌐 Port: ${PORT}`);
});

