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

/*if (!NVIDIA_API_KEY) {
  console.error("❌ NVIDIA_API_KEY missing in .env");
  process.exit(1);
} */

/* ---------------------------------------------------
   NVIDIA NIM / Nemotron Configuration
--------------------------------------------------- */

const MODEL = "nvidia/nemotron-3.5-lightning-30b-a3b";

let openai;

function getOpenAIClient() {
  if (!NVIDIA_API_KEY) {
    throw new Error(
      "NVIDIA_API_KEY environment variable is not configured."
    );
  }

  if (!openai) {
    openai = new OpenAI({
      apiKey: NVIDIA_API_KEY,
      baseURL: "https://integrate.api.nvidia.com/v1",
    });
  }

  return openai;
}

/*const openai = new OpenAI({
  apiKey: NVIDIA_API_KEY,
  baseURL: "https://integrate.api.nvidia.com/v1",
}); */

// OpenStreetMap's Overpass API is used for map-object verification.
// Replace this URL with a dedicated Overpass endpoint if required.
const OVERPASS_API_URL =
  process.env.OVERPASS_API_URL || "https://overpass-api.de/api/interpreter";
const OSM_LOOKUP_TIMEOUT_MS = 20000;

app.get("/", (_req, res) => {
  res.send("🚀 NVIDIA NIM backend running (Itinerary + Serendipity Engine)");
});

/* ---------------------------------------------------
   SYSTEM INSTRUCTION
   Keep the existing itinerary-generation rules.
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
- If the user explicitly asks for an itinerary, you MUST generate the itinerary in the required JSON structure.
- Do NOT return an empty "days" array when the user has requested an itinerary.

⭐ STRICT GPS-COMPATIBLE NAMING RULES:
The "name" field MUST be compatible with a GPS search engine such as OpenStreetMap or Google Maps.

The "name" field must also be suitable for normal web/search-engine lookup.
A traveler should be able to search the exact name in a search engine such as Brave
and in a map service and reasonably find the intended physical place.

The "name" field is the REAL PHYSICAL PLACE NAME.
It is NOT the name of an activity, experience, route, tour, recommendation,
photo opportunity, or descriptive event.

❌ BAD NAMES:
- "Dinner at Paradise Biryani"
- "Laad Bazaar (Choodi Bazaar)"
- "Mozamjahi Market"
- "Brooklyn Bridge Walk"
- "Sunset at Times Square"
- "Walking Tour of Greenwich Village"
- "Charging Bull & Fearless Girl"

✅ GOOD NAMES:
- "Paradise Biryani"
- "Laad Bazaar"
- "Moazzam Jahi Market"
- "Brooklyn Bridge"
- "Times Square"
- "Greenwich Village"
- "Charging Bull"

⭐ CRITICAL MAP-FIRST NAMING RULE:

Every itinerary place must represent ONE real, physical, geographic destination.

Before returning a "name", mentally apply this test:

"Would a traveler normally type this exact name into Brave, Google Search,
OpenStreetMap, or another map/search service to find this physical place?"

If YES:
Use that name.

If NO:
Replace it with the actual official, canonical, or commonly recognized
physical place name.

Do NOT create a name simply because it sounds attractive,
descriptive, exciting, or travel-friendly.

⭐ NAME VS EXPERIENCE:

The "name" identifies the physical place.

The "description" explains the experience.

For example:

{
  "name": "Brooklyn Bridge",
  "description": "Walk across the bridge for panoramic views of Manhattan."
}

NOT:

{
  "name": "Brooklyn Bridge Walk",
  "description": "A scenic walk across the bridge."
}

The activity belongs in "description", not in "name".

⭐ ONE PHYSICAL PLACE PER ITINERARY ITEM:

Each "name" must identify ONE physical place.

Do NOT combine multiple separate attractions into one itinerary item.

Do NOT combine separate attractions using:
- "&"
- "and"
- "/"
- "+"
- commas used to join multiple attractions

Examples:

❌ "Charging Bull & Fearless Girl"
✅ "Charging Bull"

❌ "Rockefeller Center & Top of the Rock"
✅ "Rockefeller Center"
OR
✅ "Top of the Rock"

❌ "Duomo & Galleria Vittorio Emanuele II"
✅ "Duomo di Milano"
OR
✅ "Galleria Vittorio Emanuele II"

When two attractions are genuinely separate places, they should be represented
as separate itinerary items.

⭐ OFFICIAL / CANONICAL / COMMON NAME RULE:

Prefer the following order when selecting a place name:

1. Official name of the physical place.
2. Canonical name commonly used by maps and reputable sources.
3. Widely recognized public name used by travelers.

Use the normal name that people actually search for.

Do NOT:

- invent a new name
- creatively rename a landmark
- turn an activity into a landmark name
- add unnecessary descriptive words
- use marketing language
- use itinerary language
- use a fictional or invented attraction name
- unnecessarily translate a proper place name
- unnecessarily append words such as "Walk", "Tour", "Experience",
  "Adventure", "Visit", "Exploration", "Stop", or "Day Trip"

unless those words are genuinely part of the real place's recognized name.

⭐ SUB-ATTRACTION / FEATURE RULE:

Some interesting travel experiences are features inside a larger physical
landmark, building, park, museum, station, monument, or attraction.

If the smaller feature is not clearly a standalone physical location
that can reliably be searched on a map, use the real containing landmark
as the "name".

Example:

❌ "The Whispering Gallery at Grand Central Terminal"
✅ "Grand Central Terminal"

The description can say:

"Visit the famous Whispering Gallery inside Grand Central Terminal."

Another example:

❌ "The Mall & Literary Walk"
✅ "The Mall"

The description can explain the Literary Walk experience.

⭐ REAL-WORLD PLACE RULE:

Every place must be a real-world destination that physically exists.

Prefer recognizable destinations that can reasonably be found through
normal web search or map search.

Good examples:

✅ "Statue of Liberty"
✅ "Central Park"
✅ "Metropolitan Museum of Art"
✅ "Times Square"
✅ "Brooklyn Bridge"
✅ "Chelsea Market"
✅ "Grand Central Terminal"
✅ "The High Line"

Bad examples:

❌ "Best Skyline Photo Spot"
❌ "Hidden Gem Walk"
❌ "Secret Food Experience"
❌ "Downtown Sightseeing Route"
❌ "Perfect Sunset Location"

⭐ DO NOT INVENT:

Never invent:

- attractions
- landmarks
- museums
- parks
- monuments
- streets
- neighborhoods
- restaurants
- viewpoints
- venues
- geographic locations

Prefer established real-world destinations.

⭐ MAP-FIRST DECISION RULE:

When choosing attractions for an itinerary, think about the actual
physical destination first and the travel experience second.

The place name must remain map-friendly even when the description is creative.

For example:

❌ "New York's Ultimate Skyline Sunset Experience"
✅ "Top of the Rock"

❌ "Secret Shopping Adventure in SoHo"
✅ "SoHo"

❌ "Historic Financial District Walking Tour"
✅ "Financial District"

⭐ IMPORTANT: DO NOT SACRIFICE PLACE ACCURACY FOR CREATIVITY

A boring but real and searchable place name is better than a creative
name that cannot be reliably located.

The itinerary should feel interesting through the:
- description
- visitTip
- ordering
- timing
- geographic flow

The "name" itself must remain the real place name.

⭐ ADDITIONAL MAP SEARCH RELIABILITY RULE:

When a real museum, gallery, cultural institution, attraction, or venue
has a name that may be ambiguous or may exist inside a larger institution,
use the most recognizable searchable form of the real place.

If necessary, include the parent institution or containing venue
AFTER the real place name to improve search recognition.

Examples:

✅ "Hunterian Museum, Royal College of Surgeons of England"
✅ "National Maritime Museum, Greenwich"
✅ "Victoria and Albert Museum"

Do NOT turn the name into a sentence or description.

Do NOT invent a shortened name if doing so could make the place ambiguous.

The objective is that the exact value of "name" remains useful for both
normal web search and direct map/geocoding lookup.

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

⭐ NATURAL DAILY PACING:

A real travel itinerary should NOT distribute attractions equally
or mechanically across every day.

Do NOT assume that every day must contain the same number of places.

Do NOT generate exactly two places per day simply because the trip
has multiple days.

For a normal full sightseeing day, aim for approximately 4-6 meaningful
places when the destination and trip duration provide enough suitable
attractions.

Around 5 places in a full day is a useful target, but this is NOT a
hard requirement.

Different days may naturally contain different numbers of places.

For example:

- One day may contain 4 places.
- Another day may contain 5 places.
- Another day may contain 6 places.
- A lighter day may contain fewer places when there is a genuine reason.

Reasons for a lighter day can include:
- major attractions requiring substantial time
- opening hours
- long-distance travel
- special activities
- natural pacing
- limited suitable attractions in that area

Do NOT artificially add places just to reach a number.

Do NOT artificially reduce the itinerary just to keep every day equal.

The goal is to create a natural human travel experience,
not a mathematically balanced distribution.

Use the available days meaningfully and allow the number of places
per day to vary according to the destination, geographic flow,
time requirements, and overall travel experience.

⭐ ITINERARY COMPLETENESS:

When the user requests an itinerary:

- Generate the requested itinerary.
- Generate every requested day.
- Include meaningful real-world places.
- Do not replace the itinerary with a conversational response.
- Do not return only a summary.
- Do not return an empty "days" array.
- Do not say that an itinerary is ready without actually providing it.

The "empty days" behavior is ONLY for normal conversation where
the user has not requested an itinerary.

⭐ NO REPETITION:

Do not schedule the same physical place more than once unless
the user explicitly requests a repeat visit.

⭐ LOGICAL GEOGRAPHIC FLOW:

Group geographically nearby places together where practical.

Avoid unnecessary backtracking.

Places scheduled for the same day should make practical geographic sense.

⭐ COMPLETE TRIP:

Generate a meaningful plan for every requested day.

Do not intentionally leave days empty when suitable real-world places exist.

⭐ FINAL PLACE-NAME CHECK:

Before returning every place in "days[].places[]", verify:

1. Is this a real physical place?
2. Is this ONE physical place?
3. Is this the official, canonical, or commonly recognized name?
4. Would a normal traveler search for this exact name?
5. Would a map/search service reasonably understand this exact name?
6. Is this a place name rather than an activity or experience?
7. Did I accidentally combine multiple attractions?
8. Did I invent or creatively rename the place?
9. Would the name work as a direct geocoding query?

If any answer is NO, correct the name before returning the itinerary.

⭐ VERY IMPORTANT:

The geocoding system will receive the value of "name" directly.

Therefore, do NOT assume that another system will understand or
correct a creative name later.

Return the best real-world searchable place name at the source.

⭐ GEOGRAPHIC CONTEXT FOR PLACE RESOLUTION (ADDITIVE RULE):

For EVERY object in days[].places[], include a "geoContext" string.
This field is additional geographic context for resolving the SAME physical place;
it does not replace the place's real name and must not combine separate attractions.

Use the most specific reliable locality for the named place:
- For a city itinerary, include the correct city and country.
- For a multi-city or country-wide itinerary, identify the actual city, town,
  island, or region where this particular place is located, plus the country.
- For a feature or sub-attraction, include its parent landmark or nearby named
  square/street and its city when that information is known.
- Do NOT put only the trip's country in every geoContext when the actual city
  or locality is known.
- Do NOT invent a city, address, parent venue, or departure point.
- If the suggestion is an activity rather than a physical place, choose a real
  physical venue or departure point as the place name only when it can be
  identified reliably. Do not invent a venue just to make it mappable.

Examples:
- name: "Aventine Keyhole"
  geoContext: "Piazza dei Cavalieri di Malta, Aventine Hill, Rome, Italy"
- name: "Uffizi Gallery"
  geoContext: "Florence, Italy"
- name: "Promthep Cape"
  geoContext: "Rawai, Phuket, Thailand"

The "geoContext" must describe the real location of the named place, not a
suggested itinerary route or a different nearby attraction.

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
          "visitTip": "Pro-tip for this place.",
          "geoContext": "City or locality, Country"
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

  try {
    return JSON.parse(cleaned);
  } catch (_) {
    // Fall through to code-fence cleanup.
  }

  const withoutCodeFence = cleaned
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  try {
    return JSON.parse(withoutCodeFence);
  } catch (_) {
    // Fall through to extraction.
  }

  const firstBrace = withoutCodeFence.indexOf("{");
  const lastBrace = withoutCodeFence.lastIndexOf("}");

  if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
    const jsonString = withoutCodeFence.substring(firstBrace, lastBrace + 1);
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
    // FIX: Initialize the NVIDIA client before accessing chat completions.
    const completion = await getOpenAIClient().chat.completions.create({
      model: MODEL,
      messages,
      temperature: 0.3,
      max_tokens: 4096,
      chat_template_kwargs: {
        enable_thinking: false,
      },
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
    console.error("❌ NVIDIA NIM request failed:", {
      name: error?.name,
      message: error?.message,
      status: error?.status,
      code: error?.code,
      type: error?.type,
    });

    return null;
  }
}

/* ---------------------------------------------------
   OPENSTREETMAP / OVERPASS PLACE VERIFICATION
--------------------------------------------------- */

function normalizeOsmName(value) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

function escapeOverpassRegex(value) {
  return String(value ?? "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function escapeOverpassString(value) {
  return String(value ?? "")
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/[\r\n]+/g, " ")
    .trim();
}

function getPlaceScope(place) {
  const name = String(place?.name ?? "").trim();
  const contextParts = String(place?.geoContext ?? "")
    .split(",")
    .map((part) => part.trim())
    .filter(
      (part) =>
        part &&
        normalizeOsmName(part) !== normalizeOsmName(name),
    );

  if (contextParts.length === 0) return null;

  const country = contextParts[contextParts.length - 1];
  const locality =
    contextParts.length >= 2
      ? contextParts[contextParts.length - 2]
      : null;

  if (!country) return null;
  return { country, locality };
}

function buildOverpassScopedQuery(places, scope) {
  const countryName = escapeOverpassString(scope.country);
  if (!countryName) return null;

  const countryRegex = `^${escapeOverpassRegex(countryName)}$`;
  const countrySet = ".countryArea";
  const scopeSet = ".placeArea";
  const lines = ["[out:json][timeout:18];"];

  lines.push(
    "(",
    `area["name"~"${countryRegex}",i]["admin_level"="2"];`,
    `area["name:en"~"${countryRegex}",i]["admin_level"="2"];`,
    ")->" + countrySet + ";",
  );

  if (scope.locality) {
    const localityRegex =
      `^${escapeOverpassRegex(escapeOverpassString(scope.locality))}$`;

    lines.push(
      "(",
      `area["name"~"${localityRegex}",i](area${countrySet});`,
      `area["name:en"~"${localityRegex}",i](area${countrySet});`,
      ")->" + scopeSet + ";",
    );
  } else {
    lines.push(`${countrySet}->${scopeSet};`);
  }

  const clauses = [];
  const exactKeys = [
    "name",
    "name:en",
    "official_name",
    "official_name:en",
    "int_name",
  ];
  const aliasKeys = [
    "alt_name",
    "alt_name:en",
    "loc_name",
    "loc_name:en",
    "short_name",
    "old_name",
  ];

  for (const place of places) {
    const target = String(place?.name ?? "").trim();
    if (!target || target.length > 120) continue;

    const escaped = escapeOverpassString(escapeOverpassRegex(target));

    for (const key of exactKeys) {
      clauses.push(`nwr["${key}"~"^${escaped}$",i](area${scopeSet});`);
    }

    const aliasPattern = escapeOverpassString(
      `(^|;)\\s*${escapeOverpassRegex(target)}\\s*(;|$)`,
    );

    for (const key of aliasKeys) {
      clauses.push(`nwr["${key}"~"${aliasPattern}",i](area${scopeSet});`);
    }
  }

  if (clauses.length === 0) return null;

  lines.push("(", ...clauses, ");", "out center tags;");
  return lines.join("\n");
}

async function fetchOverpassElements(query) {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    OSM_LOOKUP_TIMEOUT_MS,
  );

  try {
    const response = await fetch(OVERPASS_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        Accept: "application/json",
        "User-Agent": "Journii/1.0 (travel place verification)",
      },
      body: new URLSearchParams({ data: query }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`Overpass HTTP ${response.status}`);
    }

    const data = await response.json();
    return Array.isArray(data?.elements) ? data.elements : [];
  } finally {
    clearTimeout(timeout);
  }
}

function osmElementCoordinates(element) {
  const latitude = Number(element?.lat ?? element?.center?.lat);
  const longitude = Number(element?.lon ?? element?.center?.lon);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;

  if (
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }

  return { latitude, longitude };
}

function getOsmNames(tags) {
  const keys = [
    "name",
    "name:en",
    "official_name",
    "official_name:en",
    "int_name",
    "alt_name",
    "alt_name:en",
    "loc_name",
    "loc_name:en",
    "short_name",
    "old_name",
  ];

  return keys
    .flatMap((key) => String(tags?.[key] ?? "").split(";"))
    .map((value) => value.trim())
    .filter(Boolean);
}

function distanceKm(a, b) {
  const radians = (degrees) => (degrees * Math.PI) / 180;
  const dLat = radians(b.latitude - a.latitude);
  const dLon = radians(b.longitude - a.longitude);
  const lat1 = radians(a.latitude);
  const lat2 = radians(b.latitude);

  const value =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) *
      Math.cos(lat2) *
      Math.sin(dLon / 2) ** 2;

  return (
    6371 *
    2 *
    Math.asin(Math.sqrt(Math.max(0, Math.min(1, value))))
  );
}

function chooseUniqueOsmMatch(place, elements) {
  const target = normalizeOsmName(place?.name);
  if (!target) return null;

  const candidates = [];
  const seen = new Set();

  for (const element of elements) {
    const tags = element?.tags ?? {};
    const coordinates = osmElementCoordinates(element);

    if (!coordinates) continue;

    const names = getOsmNames(tags);

    if (
      !names.some(
        (candidateName) => normalizeOsmName(candidateName) === target,
      )
    ) {
      continue;
    }

    const key = `${element.type}/${element.id}`;
    if (seen.has(key)) continue;
    seen.add(key);

    const canonicalName = String(
      tags.name ||
        tags["name:en"] ||
        tags.official_name ||
        tags.int_name ||
        "",
    ).trim();

    if (!canonicalName) continue;

    candidates.push({
      element,
      tags,
      coordinates,
      canonicalName,
      exactPrimaryName: normalizeOsmName(tags.name) === target,
    });
  }

  if (candidates.length === 0) return null;

  // Ambiguous places must not be resolved by simply taking the first result.
  for (let i = 0; i < candidates.length; i++) {
    for (let j = i + 1; j < candidates.length; j++) {
      if (
        distanceKm(
          candidates[i].coordinates,
          candidates[j].coordinates,
        ) > 2
      ) {
        return null;
      }
    }
  }

  candidates.sort(
    (a, b) => Number(b.exactPrimaryName) - Number(a.exactPrimaryName),
  );

  return candidates[0];
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

    const places = [];
    const seenNames = new Set();

    if (Array.isArray(parsed.days)) {
      parsed.days.forEach((dayObj) => {
        const dayNumber = dayObj?.day ?? 1;

        if (!Array.isArray(dayObj?.places)) return;

        dayObj.places.forEach((place) => {
          const rawName = String(place?.name ?? "").trim();
          const cleanName = rawName.toLowerCase();

          if (!cleanName || seenNames.has(cleanName)) return;

          seenNames.add(cleanName);

          places.push({
            name: rawName,
            description: String(place?.description ?? ""),
            day: dayNumber,
            bestTime: String(place?.bestTime ?? "Morning"),
            visitTip: place?.visitTip ?? null,

            // Preserve geoContext for the subsequent OSM verification flow.
            geoContext: String(place?.geoContext ?? "").trim() || null,
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
   ROUTE 2: POST /verify-places
   Verify place identity against mapped OpenStreetMap objects.
   Ordering and count are preserved for the Flutter caller.
--------------------------------------------------- */

app.post("/verify-places", async (req, res) => {
  const inputPlaces = req.body?.places;

  if (!Array.isArray(inputPlaces)) {
    return res.status(400).json({
      success: false,
      error: "Places array required",
      places: [],
    });
  }

  if (inputPlaces.length > 60) {
    return res.status(400).json({
      success: false,
      error: "A maximum of 60 itinerary places can be verified per request",
      places: [],
    });
  }

  const places = inputPlaces.map((place) => ({
    name: String(place?.name ?? "").trim(),
    description: String(place?.description ?? ""),
    day: place?.day ?? 1,
    bestTime: String(place?.bestTime ?? "Morning"),
    visitTip: place?.visitTip ?? null,
    geoContext: String(place?.geoContext ?? "").trim() || null,
    verificationStatus: "unverified",
  }));

  const groups = new Map();

  places.forEach((place, index) => {
    const scope = getPlaceScope(place);
    if (!scope || !place.name) return;

    const key =
      `${normalizeOsmName(scope.country)}|` +
      `${normalizeOsmName(scope.locality ?? "")}`;

    if (!groups.has(key)) {
      groups.set(key, { scope, entries: [] });
    }

    groups.get(key).entries.push({ place, index });
  });

  let searchedGroupCount = 0;

  for (const { scope, entries } of groups.values()) {
    const query = buildOverpassScopedQuery(
      entries.map((entry) => entry.place),
      scope,
    );

    if (!query) continue;

    try {
      const elements = await fetchOverpassElements(query);
      searchedGroupCount++;

      for (const { place, index } of entries) {
        const match = chooseUniqueOsmMatch(place, elements);

        if (!match) {
          console.log(
            `🗺️ OSM did not return a unique mapped match for ` +
              `"${place.name}" (${place.geoContext ?? "no geoContext"}).`,
          );
          continue;
        }

        const { element, tags, coordinates, canonicalName } = match;

        places[index] = {
          ...place,
          name: canonicalName,
          verificationStatus: "verified",
          latitude: coordinates.latitude,
          longitude: coordinates.longitude,
          osmType: element.type,
          osmId: element.id,
          osmTags: {
            name: tags.name ?? null,
            nameEn: tags["name:en"] ?? null,
            officialName: tags.official_name ?? null,
          },
        };

        console.log(
          `✅ OSM verified "${place.name}" → "${canonicalName}" ` +
            `(${element.type}/${element.id}).`,
        );
      }
    } catch (error) {
      console.warn(
        `⚠️ OSM verification failed for scope ` +
          `"${scope.locality ?? scope.country}":`,
        error?.message ?? error,
      );

      // Leave unresolved entries unchanged so the existing fallback can run.
    }
  }

  return res.json({
    success: true,
    summary: "OSM place verification completed; unresolved names were preserved.",
    places,
    verification: {
      provider: "OpenStreetMap Overpass API",
      searchedScopes: searchedGroupCount,
      verifiedCount: places.filter(
        (place) => place.verificationStatus === "verified",
      ).length,
      unresolvedCount: places.filter(
        (place) => place.verificationStatus !== "verified",
      ).length,
    },
  });
});

/* ---------------------------------------------------
   ROUTE 3: GET /api/daily-destination
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

    // FIX: Use the initialized NVIDIA client here too.
    const completion = await getOpenAIClient().chat.completions.create({
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
      destination: destinationData?.destination ?? "Kyoto, Japan",
      description:
        destinationData?.description ??
        "Experience the timeless beauty of ancient temples and bamboo forests.",
    });
  } catch (error) {
    console.error("❌ NVIDIA NIM Daily Destination Error:", {
      name: error?.name,
      message: error?.message,
      status: error?.status,
      code: error?.code,
      type: error?.type,
    });

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

export default app;

/*const isDirectRun =
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url);*/

/* if (isDirectRun) {
  app.listen(PORT, "0.0.0.0", () => {
    console.log(
      `\n🚀 Journii NVIDIA NIM backend running on port ${PORT}`
    );
    console.log(`🤖 Model: ${MODEL}`);
    console.log(`🌐 Port: ${PORT}`);
  });
} */

/*
app.listen(PORT, "0.0.0.0", () => {
  console.log(`\n🚀 Journii NVIDIA NIM backend running on port ${PORT}`);
  console.log(`🤖 Model: ${MODEL}`);
  console.log(`🌐 Port: ${PORT}`);
});*/