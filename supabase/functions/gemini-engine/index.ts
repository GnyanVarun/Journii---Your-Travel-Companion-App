// @ts-nocheck
// 🟢 CORS Headers are mandatory so your Flutter mobile app can communicate with this function
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

Deno.serve(async (req) => {
  // 1. Handle CORS Preflight Options Request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const path = url.pathname;
  const API_KEY = Deno.env.get('GEMINI_API_KEY');

  if (!API_KEY) {
    console.error("❌ GEMINI_API_KEY missing in Supabase Secrets Vault");
    return new Response(
      JSON.stringify({ success: false, error: "Server misconfiguration: API key missing" }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  /* -------------------------------------------------------------------------
     ROUTE 1: POST .../generate (Itinerary Generator & Chat Engine)
  ------------------------------------------------------------------------- */
  if (req.method === 'POST' && path.endsWith('/generate')) {
    try {
      console.log("⭐ /generate endpoint hit via Edge Function");
      const { history } = await req.json();

      if (!history || !Array.isArray(history)) {
        return new Response(
          JSON.stringify({ success: false, error: "History array required" }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 1. Convert Flutter history structure to Gemini's native API format
      const contents = history.map((msg: any) => ({
        role: msg.role === 'ai' ? 'model' : 'user',
        parts: [{ text: msg.text }]
      }));

      // 2. Your core System Instructions / Engineering Prompts
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

      // 3. Inject the instructions into the context pipeline
      if (contents.length > 0) {
        contents[0].parts[0].text = systemInstruction + "\n\nUSER SAYS:\n" + contents[0].parts[0].text;
      } else {
        contents.push({ role: 'user', parts: [{ text: systemInstruction }] });
      }

      // 4. Secure upstream request directly to Google
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
        throw new Error("Failed upstream response from Gemini cloud service.");
      }

      const data = await response.json();
      const rawText = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? null;

      if (!rawText) {
        return new Response(
          JSON.stringify({
            summary: "I'm having trouble connecting to the travel brain right now. 🧠💤",
            places: [],
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 5. Your exact JSON Cleaner Block
      let parsed: any;
      try {
        const firstBrace = rawText.indexOf('{');
        const lastBrace = rawText.lastIndexOf('}');

        if (firstBrace !== -1 && lastBrace !== -1) {
          const jsonString = rawText.substring(firstBrace, lastBrace + 1);
          parsed = JSON.parse(jsonString);
        } else {
          return new Response(
            JSON.stringify({ summary: rawText, places: [] }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }
      } catch (e) {
        console.error("❌ Failed to parse Gemini JSON output structure.", rawText);
        return new Response(
          JSON.stringify({ success: false, error: "Invalid JSON parsing context from model payload" }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // 6. Data Normalization pipeline & Unique verification tracking
      const places: any[] = [];
      const seenNames = new Set();

      if (parsed.days && Array.isArray(parsed.days)) {
        parsed.days.forEach((dayObj: any) => {
          const dayNumber = dayObj.day ?? 1;
          if (Array.isArray(dayObj.places)) {
            dayObj.places.forEach((p: any) => {
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

      console.log(`✅ Returning ${places.length} uniquely mapped locations`);
      return new Response(
        JSON.stringify({
          summary: parsed.summary ?? "Here is your itinerary! ✨",
          places,
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );

    } catch (err: any) {
      console.error("🔥 Critical Error in Edge Generation Engine:", err);
      return new Response(
        JSON.stringify({ success: false, error: "Internal Edge Failure execution context" }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
  }

  /* -------------------------------------------------------------------------
     ROUTE 2: GET .../api/daily-destination (Real-Time Discover Feed)
  ------------------------------------------------------------------------- */
  if (req.method === 'GET' && path.endsWith('/api/daily-destination')) {
    try {
      console.log("🌍 Fetching daily discovery feed destinations via Edge...");
      const prompt = `Act as a travel expert. Give me one random, highly trending, beautiful global travel destination for today.
    Return ONLY a raw JSON object (no markdown, no backticks) with two keys: "destination" (City, Country) and "description" (A short 10-word hook about why it is beautiful).`;

      const response = await fetch(`${GEMINI_URL}?key=${API_KEY}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0.8, // Structural entropy boost for discovery random variance
            responseMimeType: "application/json",
          },
        }),
      });

      if (!response.ok) throw new Error(`Upstream API Exception: ${response.status}`);

      const data = await response.json();
      let responseText = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";

      // Clean raw text formatting blocks gracefully
      responseText = responseText.trim();
      if (responseText.startsWith('```json')) {
        responseText = responseText.replace(/```json/g, '').replace(/```/g, '').trim();
      } else if (responseText.startsWith('```')) {
        responseText = responseText.replace(/```/g, '').trim();
      }

      // Validate parse structure before return deployment
      const destinationData = JSON.parse(responseText);
      return new Response(
        JSON.stringify(destinationData),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );

    } catch (error) {
      console.error("❌ Gemini Discovery Processing Error:", error);
      // Hard fallback safe configuration block prevent client app UI crashes
      return new Response(
        JSON.stringify({
          destination: "Kyoto, Japan",
          description: "Experience the timeless beauty of ancient temples and bamboo forests."
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
  }

  // 404 Route Catch Handler
  return new Response(
    JSON.stringify({ error: "Route routing profile not matched" }),
    { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
});