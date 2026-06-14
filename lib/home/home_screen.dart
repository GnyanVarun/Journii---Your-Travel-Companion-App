import 'dart:ui';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:journii/features/trips/trip_provider.dart';

import '../services/unsplash_service.dart';
import 'live_journey_planner.dart';
import 'package:journii/features/trips/trip_detail_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ===========================================================================
// IMAGE URL CACHE
// ===========================================================================
class ImageUrlCache {
  static final Map<String, String> _cache = {};
  static String? getSync(String query) => _cache[query];
  static Future<String?> getAsync(String query) async {
    if (_cache.containsKey(query)) return _cache[query];
    final url = await UnsplashService.getPhotoUrl(query);
    if (url != null) _cache[query] = url;
    return url;
  }
}

// ===========================================================================
// 🟢 NEW: MASTER HOME DATA CACHE
// Locks down all API calls so they only fire once per app session.
// ===========================================================================
class HomeDataCache {
  static List<LiveDestination>? chasingSun;
  static List<LiveDestination>? perfectWeather;
  static List<LiveDestination>? cozyEscapes;

  static List<Map<String, String>>? trendingDestinations;
  static List<TravelNews>? travelNews;

  // Caches currency rates per base currency (e.g., 'USD', 'EUR')
  static final Map<String, Map<String, double>> currencyRatesCache = {};
}

class SafetyDataCache {
  static Map<String, CountrySafetyInfo>? radarPoolCache;
  static final Map<String, CountrySafetyInfo> searchDataCache = {};
  static final Map<String, String> searchNameCache = {};
}

// ===========================================================================
// ADAPTIVE THEME HELPER
// ===========================================================================
class _AppTheme {
  final bool isDark;
  const _AppTheme(this.isDark);

  Color get scaffold    => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F0);
  Color get card        => isDark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get cardBorder  => isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.07);
  Color get surface     => isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEEEEE9);

  Color get textPrimary => isDark ? Colors.white              : const Color(0xFF1A1A1A);
  Color get textSecond  => isDark ? Colors.white60            : const Color(0xFF6B6B6B);
  Color get textMuted   => isDark ? Colors.white30            : const Color(0xFFAAAAAA);

  Color get accent      => isDark ? const Color(0xFF00E5FF) : const Color(0xFF2E3192);
  Color get accentSoft  => accent.withOpacity(isDark ? 0.18 : 0.10);
  Color get accentForeground => isDark ? Colors.black : Colors.white;

  Color get golden      => const Color(0xFFF5A623);
  Color get goldenSoft  => golden.withOpacity(isDark ? 0.15 : 0.10);
  Color get red         => const Color(0xFFE5484D);
  Color get green       => const Color(0xFF30A46C);

  Color get sheetBg     => isDark ? const Color(0xFF121212) : Colors.white;
  Color get divider     => isDark ? Colors.white12          : Colors.black12;

  Color get searchBg     => isDark ? Colors.black                   : const Color(0xFFF0F0EB);
  Color get searchBorder => isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.10);

  Color get skeletonBase => isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5E0);

  List<BoxShadow> get cardShadow => isDark ? [] : [
    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 8)),
  ];
  List<BoxShadow> get smallShadow => isDark ? [] : [
    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4)),
  ];
}

// ===========================================================================
// DATA MODELS
// ===========================================================================
class GlobalHub {
  final String city, country;
  final double lat, lon;
  const GlobalHub(this.city, this.country, this.lat, this.lon);
}

class LiveDestination {
  final GlobalHub hub;
  final int temperature, weatherCode;
  final String condition, sunrise, sunset;
  const LiveDestination({
    required this.hub, required this.temperature,
    required this.condition, required this.weatherCode,
    required this.sunrise, required this.sunset,
  });
}

class TravelNews {
  final String title, source, imageUrl, url, description;
  const TravelNews({
    required this.title, required this.source,
    required this.imageUrl, required this.url, required this.description,
  });
}

class CountrySafetyInfo {
  final String region, currencyCode, currencySymbol, language, callingCode;
  CountrySafetyInfo({
    required this.region, required this.currencyCode, required this.currencySymbol,
    required this.language, required this.callingCode,
  });
}

// ===========================================================================
// RADAR POOL
// ===========================================================================
final List<GlobalHub> radarPool = [
  const GlobalHub("Bali",           "Indonesia",    -8.4095,  115.1889),
  const GlobalHub("Tokyo",          "Japan",        35.6762,  139.6503),
  const GlobalHub("Paris",          "France",       48.8566,    2.3522),
  const GlobalHub("Reykjavik",      "Iceland",      64.1466,  -21.9426),
  const GlobalHub("Cape Town",      "South Africa",-33.9249,   18.4241),
  const GlobalHub("Dubai",          "UAE",          25.2048,   55.2708),
  const GlobalHub("New York",       "USA",          40.7128,  -74.0060),
  const GlobalHub("Sydney",         "Australia",   -33.8688,  151.2093),
  const GlobalHub("Zermatt",        "Switzerland",  46.0207,    7.7491),
  const GlobalHub("Rio de Janeiro", "Brazil",      -22.9068,  -43.1729),
  const GlobalHub("Marrakech",      "Morocco",      31.6295,   -7.9811),
  const GlobalHub("Seoul",          "South Korea",  37.5665,  126.9780),
];

// ===========================================================================
// HOME PAGE
// ===========================================================================
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _isLoading = true;

  List<LiveDestination> _chasingSun     = [];
  List<LiveDestination> _perfectWeather = [];
  List<LiveDestination> _cozyEscapes    = [];

  List<Map<String, String>> _trendingDestinations = [];
  bool _isLoadingTrends = true;

  List<TravelNews> _travelNews = [];
  bool _isLoadingNews          = true;

  Map<String, double> _currencyRates = {};
  bool _isLoadingCurrency            = true;

  String _baseCurrency = 'USD';
  final List<String> _availableBases = ['USD', 'EUR', 'GBP', 'JPY', 'AUD', 'CAD', 'INR'];

  Map<String, CountrySafetyInfo> _countrySafetyData = {};
  bool _isLoadingSafety = true;

  bool _isSafetySearchOpen = false;
  final TextEditingController _safetySearchCtrl = TextEditingController();
  CountrySafetyInfo? _searchedCountrySafety;
  String? _searchedCountryName;
  bool _isPerformingSafetySearch = false;

  @override
  void initState() {
    super.initState();
    _scanGlobalConditions();
    _fetchTravelNews();
    _fetchCurrencyRates();
    _fetchCountrySafetyData();
    _fetchLiveGlobalTrends();
  }

  @override
  void dispose() {
    _safetySearchCtrl.dispose();
    super.dispose();
  }

  // --- DYNAMIC GREETING LOGIC ---
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning ☀️";
    if (hour < 17) return "Good afternoon 🌤️";
    return "Good evening 🌙";
  }

  // -------------------------------------------------------------------------
  // DATA FETCHING
  // -------------------------------------------------------------------------

  Future<void> _fetchCountrySafetyData() async {
    if (SafetyDataCache.radarPoolCache != null) {
      if (mounted) {
        setState(() {
          _countrySafetyData = Map.from(SafetyDataCache.radarPoolCache!);
          _isLoadingSafety = false;
        });
      }
      return;
    }

    final Map<String, CountrySafetyInfo> fetchedData = {};

    await Future.wait(radarPool.map((hub) async {
      try {
        String queryName = hub.country;
        if (queryName == "USA") queryName = "United States";
        if (queryName == "UAE") queryName = "United Arab Emirates";

        final url = Uri.parse('https://studies.cs.helsinki.fi/restcountries/api/name/${Uri.encodeComponent(queryName)}');

        final res = await http.get(
            url,
            headers: {
              'User-Agent': 'JourniiApp/1.0',
            }
        );

        if (res.statusCode == 200) {
          final decoded = json.decode(res.body);

          Map countryData;
          if (decoded is List) {
            if (decoded.isEmpty) return;
            countryData = decoded.first as Map;
          } else if (decoded is Map) {
            countryData = decoded;
          } else {
            return;
          }

          final region = countryData['region'] ?? 'Unknown';

          String currCode = '', currSymbol = '';
          final currencies = countryData['currencies'];
          if (currencies != null) {
            if (currencies is Map && currencies.isNotEmpty) {
              currCode = currencies.keys.first.toString();
              if (currencies[currCode] is Map) {
                currSymbol = currencies[currCode]['symbol']?.toString() ?? '';
              }
            } else if (currencies is List && currencies.isNotEmpty) {
              final c = currencies.first;
              if (c is Map) {
                currCode = c['code']?.toString() ?? c['name']?.toString() ?? '';
                currSymbol = c['symbol']?.toString() ?? '';
              } else {
                currCode = c.toString();
              }
            }
          }

          String language = '';
          final languages = countryData['languages'];
          if (languages != null) {
            if (languages is Map && languages.isNotEmpty) {
              language = languages.values.first.toString();
            } else if (languages is List && languages.isNotEmpty) {
              final l = languages.first;
              language = l is Map ? (l['name']?.toString() ?? '') : l.toString();
            }
          }

          String callingCode = '';
          final v5Codes = countryData['calling_codes'];

          if (v5Codes is List && v5Codes.isNotEmpty) {
            callingCode = v5Codes.first.toString();
          } else if (countryData['callingCodes'] is List && (countryData['callingCodes'] as List).isNotEmpty) {
            callingCode = (countryData['callingCodes'] as List).first.toString();
          } else if (countryData['idd'] is Map) {
            final idd = countryData['idd'];
            final root = idd['root']?.toString() ?? '';
            final suffixes = idd['suffixes'];
            if (suffixes is List && suffixes.isNotEmpty) {
              callingCode = suffixes.length == 1 ? '$root${suffixes.first}' : root;
            } else {
              callingCode = root;
            }
          }

          if (callingCode.isNotEmpty && callingCode != '+') {
            if (!callingCode.startsWith('+')) {
              callingCode = '+$callingCode';
            }
          } else {
            callingCode = '';
          }

          fetchedData[hub.country] = CountrySafetyInfo(
            region: region, currencyCode: currCode, currencySymbol: currSymbol,
            language: language, callingCode: callingCode,
          );
        }
      } catch (e) {
        debugPrint("Safety Data Parsing Error for ${hub.country}: $e");
      }
    }));

    if (mounted) {
      SafetyDataCache.radarPoolCache = fetchedData;
      setState(() {
        _countrySafetyData = fetchedData;
        _isLoadingSafety = false;
      });
    }
  }

  Future<void> _handleSafetySearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searchedCountrySafety = null; _searchedCountryName = null; });
      return;
    }

    String sanitizedQuery = query.trim();
    if (sanitizedQuery.toUpperCase() == "USA") sanitizedQuery = "United States";
    if (sanitizedQuery.toUpperCase() == "UAE") sanitizedQuery = "United Arab Emirates";
    if (sanitizedQuery.toUpperCase() == "UK") sanitizedQuery = "United Kingdom";

    final cacheKey = sanitizedQuery.toLowerCase();
    if (SafetyDataCache.searchDataCache.containsKey(cacheKey)) {
      setState(() {
        _searchedCountryName = SafetyDataCache.searchNameCache[cacheKey];
        _searchedCountrySafety = SafetyDataCache.searchDataCache[cacheKey];
        _isPerformingSafetySearch = false;
      });
      return;
    }

    setState(() => _isPerformingSafetySearch = true);

    try {
      final url = Uri.parse('https://studies.cs.helsinki.fi/restcountries/api/name/${Uri.encodeComponent(sanitizedQuery)}');

      final res = await http.get(
          url,
          headers: {
            'User-Agent': 'JourniiApp/1.0',
          }
      );

      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);

        Map countryData;
        if (decoded is List) {
          if (decoded.isEmpty) throw Exception("No data found");
          countryData = decoded.first as Map;
        } else if (decoded is Map) {
          countryData = decoded;
        } else {
          throw Exception("No data found");
        }

        final region = countryData['region'] ?? 'Unknown';

        String currCode = '', currSymbol = '';
        final currencies = countryData['currencies'];
        if (currencies != null) {
          if (currencies is Map && currencies.isNotEmpty) {
            currCode = currencies.keys.first.toString();
            if (currencies[currCode] is Map) {
              currSymbol = currencies[currCode]['symbol']?.toString() ?? '';
            }
          } else if (currencies is List && currencies.isNotEmpty) {
            final c = currencies.first;
            if (c is Map) {
              currCode = c['code']?.toString() ?? c['name']?.toString() ?? '';
              currSymbol = c['symbol']?.toString() ?? '';
            } else {
              currCode = c.toString();
            }
          }
        }

        String language = '';
        final languages = countryData['languages'];
        if (languages != null) {
          if (languages is Map && languages.isNotEmpty) {
            language = languages.values.first.toString();
          } else if (languages is List && languages.isNotEmpty) {
            final l = languages.first;
            language = l is Map ? (l['name']?.toString() ?? '') : l.toString();
          }
        }

        String callingCode = '';
        final v5Codes = countryData['calling_codes'];

        if (v5Codes is List && v5Codes.isNotEmpty) {
          callingCode = v5Codes.first.toString();
        } else if (countryData['callingCodes'] is List && (countryData['callingCodes'] as List).isNotEmpty) {
          callingCode = (countryData['callingCodes'] as List).first.toString();
        } else if (countryData['idd'] is Map) {
          final idd = countryData['idd'];
          final root = idd['root']?.toString() ?? '';
          final suffixes = idd['suffixes'];
          if (suffixes is List && suffixes.isNotEmpty) {
            callingCode = suffixes.length == 1 ? '$root${suffixes.first}' : root;
          } else {
            callingCode = root;
          }
        }

        if (callingCode.isNotEmpty && callingCode != '+') {
          if (!callingCode.startsWith('+')) {
            callingCode = '+$callingCode';
          }
        } else {
          callingCode = '';
        }

        final nameMap = countryData['names'] as Map<String, dynamic>? ?? {};
        final fetchedName = nameMap['common'] ?? countryData['name']?['common'] ?? query.trim();

        final fetchedSafetyInfo = CountrySafetyInfo(
          region: region, currencyCode: currCode, currencySymbol: currSymbol,
          language: language, callingCode: callingCode,
        );

        if (mounted) {
          SafetyDataCache.searchDataCache[cacheKey] = fetchedSafetyInfo;
          SafetyDataCache.searchNameCache[cacheKey] = fetchedName;

          setState(() {
            _searchedCountryName = fetchedName;
            _searchedCountrySafety = fetchedSafetyInfo;
          });
        }
      } else {
        if (mounted) {
          setState(() { _searchedCountrySafety = null; _searchedCountryName = null; });
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Country '${query.trim()}' not found."), backgroundColor: const Color(0xFFE5484D))
          );
        }
      }
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      if (mounted) setState(() => _isPerformingSafetySearch = false);
    }
  }

  Future<void> _fetchLiveGlobalTrends() async {
    // 🟢 FIXED: Check the Master Cache First
    if (HomeDataCache.trendingDestinations != null) {
      if (mounted) {
        setState(() {
          _trendingDestinations = List.from(HomeDataCache.trendingDestinations!);
          _isLoadingTrends = false;
        });
      }
      return;
    }

    try {
      final now = DateTime.now().toUtc().subtract(const Duration(days: 2));
      final year = now.year.toString();
      final month = now.month.toString().padLeft(2, '0');
      final day = now.day.toString().padLeft(2, '0');

      final topUrl = Uri.parse("https://wikimedia.org/api/rest_v1/metrics/pageviews/top/en.wikipedia/all-access/$year/$month/$day");
      final topRes = await http.get(topUrl, headers: {'User-Agent': 'JourniiApp/1.0'}).timeout(const Duration(seconds: 8));

      if (topRes.statusCode != 200) throw Exception("Wikipedia Top API Failed");

      final topData = json.decode(topRes.body);
      final articles = (topData['items'][0]['articles'] as List).cast<Map<String, dynamic>>();

      final candidates = articles.where((a) {
        final title = a['article'] as String;
        return !title.contains(':') && title != "Main_Page" && title != "Earth";
      }).take(200).toList();

      List<Map<String, dynamic>> trendingPlaces = [];
      final validPlaceKeywords = ['city', 'town', 'village', 'municipality', 'capital', 'island', 'province', 'state', 'national park', 'country', 'republic', 'territory', 'resort'];
      final invalidPlaceKeywords = ['stadium', 'arena', 'building', 'airport', 'assembly', 'politician', 'president', 'university', 'college', 'school', 'hospital', 'museum', 'bridge', 'company', 'actress', 'actor', 'singer', 'movie', 'film', 'album'];

      for (int i = 0; i < candidates.length; i += 50) {
        if (trendingPlaces.length >= 5) break;

        final chunk = candidates.skip(i).take(50).toList();
        final titlesParam = chunk.map((c) => Uri.encodeComponent(c['article'] as String)).join('|');

        final geoUrl = Uri.parse("https://en.wikipedia.org/w/api.php?action=query&prop=coordinates|description&titles=$titlesParam&format=json");

        final geoRes = await http.get(geoUrl).timeout(const Duration(seconds: 5));
        if (geoRes.statusCode == 200) {
          final geoData = json.decode(geoRes.body);
          final pages = geoData['query']['pages'] as Map<String, dynamic>;

          for (var pageId in pages.keys) {
            final page = pages[pageId];

            if (page.containsKey('coordinates') && page.containsKey('description')) {
              final description = (page['description'] as String).toLowerCase();
              final title = (page['title'] as String).toLowerCase();

              bool isPlace = validPlaceKeywords.any((k) => description.contains(k));
              bool isNotPlace = invalidPlaceKeywords.any((k) => description.contains(k) || title.contains(k));

              if (isPlace && !isNotPlace) {
                final match = chunk.firstWhere(
                        (c) => (c['article'] as String).replaceAll('_', ' ') == page['title'],
                    orElse: () => {'views': 0}
                );

                trendingPlaces.add({
                  'city': page['title'],
                  'views': match['views'] as int,
                  'lat': page['coordinates'][0]['lat'],
                  'lon': page['coordinates'][0]['lon'],
                });
              }
            }
          }
        }
      }

      trendingPlaces.sort((a, b) => (b['views'] as int).compareTo(a['views'] as int));

      if (mounted) {
        final finalTrends = trendingPlaces.take(5).map((p) {
          int v = p['views'] as int;
          String viewStr = v > 1000 ? "${(v / 1000).toStringAsFixed(1)}k" : v.toString();

          return {
            'city': p['city'].toString(),
            'country': 'Live Global Trend',
            'trend': '🔥 $viewStr views',
            'lat': p['lat'].toString(),
            'lon': p['lon'].toString(),
          };
        }).toList();

        // 🟢 FIXED: Save to Master Cache
        HomeDataCache.trendingDestinations = finalTrends;

        setState(() {
          _trendingDestinations = finalTrends;
          _isLoadingTrends = false;
        });
      }
    } catch (e) {
      debugPrint("Live Global Trends Error: $e");
      if (mounted) setState(() => _isLoadingTrends = false);
    }
  }

  Future<void> _fetchTravelNews() async {
    // 🟢 FIXED: Check the Master Cache First
    if (HomeDataCache.travelNews != null) {
      if (mounted) {
        setState(() {
          _travelNews = List.from(HomeDataCache.travelNews!);
          _isLoadingNews = false;
        });
      }
      return;
    }

    final String apiKey = dotenv.env['NEWS_API_KEY'] ?? '';
    const travelDomains = 'lonelyplanet.com,cntraveler.com,travelandleisure.com,nationalgeographic.com,matadornetwork.com,afar.com,thepointsguy.com,nomadicmatt.com,roughguides.com,frommers.com';
    final String strictQuery = Uri.encodeComponent('(travel OR tourism OR airlines OR hotels OR destinations) -health -disease -bacteria -gut -science -space -cloning -cholesterol');
    final url = Uri.parse('https://newsapi.org/v2/everything?q=$strictQuery&domains=$travelDomains&language=en&sortBy=publishedAt&pageSize=20&apiKey=$apiKey');

    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final List articles = json.decode(res.body)['articles'] ?? [];
        final List<TravelNews> fetched = [];

        for (var a in articles) {
          if (a['urlToImage'] == null || a['title'] == null) continue;
          final title = (a['title'] ?? '').toString();
          if (title == '[Removed]' || title.isEmpty) continue;

          fetched.add(TravelNews(
            title: title, source: a['source']['name'] ?? 'Travel News',
            imageUrl: a['urlToImage'], url: a['url'] ?? '',
            description: (a['description'] ?? 'No summary available.').toString(),
          ));
        }

        if (mounted) {
          // 🟢 FIXED: Save to Master Cache
          HomeDataCache.travelNews = fetched;
          setState(() { _travelNews = fetched; _isLoadingNews = false; });
        }
      } else {
        if (mounted) setState(() => _isLoadingNews = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingNews = false);
    }
  }

  Future<void> _fetchCurrencyRates() async {
    // 🟢 FIXED: Check the Master Cache First for the specific base currency
    if (HomeDataCache.currencyRatesCache.containsKey(_baseCurrency)) {
      if (mounted) {
        setState(() {
          _currencyRates = Map.from(HomeDataCache.currencyRatesCache[_baseCurrency]!);
          _isLoadingCurrency = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoadingCurrency = true);
    try {
      final res = await http.get(Uri.parse('https://api.frankfurter.app/latest?from=$_baseCurrency'));
      if (res.statusCode == 200) {
        final rates = Map<String, double>.from(
          (json.decode(res.body)['rates'] as Map).map((k, v) => MapEntry(k, (v as num).toDouble())),
        );

        if (mounted) {
          // 🟢 FIXED: Save to Master Cache
          HomeDataCache.currencyRatesCache[_baseCurrency] = rates;
          setState(() { _currencyRates = rates; _isLoadingCurrency = false; });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCurrency = false);
    }
  }

  Future<void> _scanGlobalConditions() async {
    // 🟢 FIXED: Check the Master Cache First
    if (HomeDataCache.chasingSun != null && HomeDataCache.perfectWeather != null && HomeDataCache.cozyEscapes != null) {
      if (mounted) {
        setState(() {
          _chasingSun = List.from(HomeDataCache.chasingSun!);
          _perfectWeather = List.from(HomeDataCache.perfectWeather!);
          _cozyEscapes = List.from(HomeDataCache.cozyEscapes!);
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final List<LiveDestination> all = [];
      await Future.wait(radarPool.map((hub) async {
        final res = await http.get(Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=${hub.lat}&longitude=${hub.lon}&current_weather=true&daily=sunrise,sunset&timezone=auto",
        ));
        if (res.statusCode == 200) {
          final data    = json.decode(res.body);
          final current = data['current_weather'];
          String sr = "06:00", ss = "18:00";
          if (data['daily'] != null) {
            sr = data['daily']['sunrise'][0].toString().split('T').last;
            ss = data['daily']['sunset'][0].toString().split('T').last;
          }
          all.add(LiveDestination(
            hub: hub, temperature: (current['temperature'] as num).round(),
            condition: _parseWeatherCode(current['weathercode'] as int), weatherCode: current['weathercode'] as int,
            sunrise: sr, sunset: ss,
          ));
        }
      }));

      setState(() {
        _chasingSun     = all.where((d)=>d.temperature>=24).toList()..sort((a,b)=>b.temperature.compareTo(a.temperature));
        _perfectWeather = all.where((d)=>d.temperature>=15&&d.temperature<24).toList()..sort((a,b)=>b.temperature.compareTo(a.temperature));
        _cozyEscapes    = all.where((d)=>d.temperature<15).toList()..sort((a,b)=>a.temperature.compareTo(b.temperature));

        // 🟢 FIXED: Save to Master Cache
        HomeDataCache.chasingSun = _chasingSun;
        HomeDataCache.perfectWeather = _perfectWeather;
        HomeDataCache.cozyEscapes = _cozyEscapes;

        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _parseWeatherCode(int code) {
    if (code == 0)  return "Clear Skies";
    if (code <= 3)  return "Partly Cloudy";
    if (code <= 48) return "Foggy";
    if (code <= 67) return "Raining";
    if (code <= 77) return "Snowing";
    if (code >= 95) return "Storms";
    return "Clear";
  }

  // -------------------------------------------------------------------------
  // ACTIONS
  // -------------------------------------------------------------------------

  void _showCityDetails(BuildContext context, LiveDestination dest) =>
      showModalBottomSheet(
        context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CityDetailSheet(dest: dest),
      );

  void _inspireMe() {
    final all = [..._chasingSun, ..._perfectWeather, ..._cozyEscapes];
    if (all.isEmpty) return;
    all.shuffle(Random());
    final pick = all.first;
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InspireMeSheet(
        dest: pick,
        onPlanTrip: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => LiveJourneyPlanner(destination: pick.hub.city)));
        },
      ),
    );
  }

  void _showDestinationPrompt(BuildContext context) {
    final theme = _AppTheme(Theme.of(context).brightness == Brightness.dark);
    final ctrl  = TextEditingController();
    String? errorMessage;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: theme.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              title: Text("Where to next?", style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.bold)),
              content: TextField(
                controller: ctrl,
                maxLength: 20,
                style: TextStyle(color: theme.textPrimary, fontSize: 18),
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onChanged: (value) {
                  if (errorMessage != null) {
                    setDialogState(() => errorMessage = null);
                  }
                },
                decoration: InputDecoration(
                  hintText: "e.g. Tokyo, Paris",
                  hintStyle: TextStyle(color: theme.textMuted),
                  errorText: errorMessage,
                  counterText: "",
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.divider)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.accent)),
                ),
              ),
              actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Cancel", style: TextStyle(color: theme.textSecond))
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: theme.accent, foregroundColor: theme.accentForeground, shape: const StadiumBorder()),
                  onPressed: () {
                    final dest = ctrl.text.trim();

                    if (dest.isEmpty) {
                      setDialogState(() => errorMessage = "Please enter a place name");
                      return;
                    }

                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => LiveJourneyPlanner(destination: dest)));
                  },
                  child: Text("Continue", style: TextStyle(fontWeight: FontWeight.bold, color: theme.accentForeground)),
                ),
              ],
            );
          }
      ),
    );
  }

  // -------------------------------------------------------------------------
  // BUILD
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = _AppTheme(Theme.of(context).brightness == Brightness.dark);

    return Scaffold(
      backgroundColor: theme.scaffold,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. CLEAN MODERN APP BAR
          SliverAppBar(
            backgroundColor: theme.scaffold,
            expandedHeight: 110.0,
            floating: false,
            pinned: true,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      "Journii",
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: -0.3,
                        height: 1.1,
                      )
                  ),
                  Text(
                      "YOUR TRAVEL COMPANION",
                      style: TextStyle(
                        color: theme.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 9,
                        letterSpacing: 1.5,
                      )
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(children: [
              _buildCommandCenter(ref, theme),
              const SizedBox(height: 16),
              _buildTravelStats(ref, theme),
              const SizedBox(height: 32),
            ]),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildTrendingRightNow(theme),
              const SizedBox(height: 32),

              _buildLiveFeedSection("Chasing the Sun ☀️", "Live temps above 24°C", _chasingSun, theme, _isLoading),
              _buildCurrencySpotlight(theme),
              const SizedBox(height: 32),

              _buildLiveFeedSection("Perfect City Breaks 🌤️", "Comfortable walking weather", _perfectWeather, theme, _isLoading),
              _buildTravelSafetySection(theme),
              const SizedBox(height: 32),

              _buildLiveFeedSection("Cozy & Cold ❄️", "Live temps below 15°C", _cozyEscapes, theme, _isLoading),
              _buildNewsSection(theme),
              const SizedBox(height: 60),
            ]),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // WIDGETS
  // =========================================================================

  Widget _buildCommandCenter(WidgetRef ref, _AppTheme theme) {
    final allTrips = ref.watch(tripProvider);
    final today    = DateTime.now().let((n) => DateTime(n.year, n.month, n.day));

    final upcoming = allTrips.where((trip) {
      if (trip.endDate == null) return true;
      final e = DateTime(trip.endDate!.year, trip.endDate!.month, trip.endDate!.day);
      return !e.isBefore(today);
    }).toList()
      ..sort((a, b) {
        if (a.startDate == null && b.startDate == null) return 0;
        if (a.startDate == null) return 1;
        if (b.startDate == null) return -1;
        return a.startDate!.compareTo(b.startDate!);
      });

    final hasTrip  = upcoming.isNotEmpty;
    final nextTrip = hasTrip ? upcoming.first : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.card, borderRadius: BorderRadius.circular(32),
          border: Border.all(color: theme.cardBorder), boxShadow: theme.cardShadow,
        ),
        child: Column(children: [
          GestureDetector(
            onTap: () => _showDestinationPrompt(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: theme.searchBg, borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.searchBorder),
              ),
              child: Row(children: [
                Icon(Icons.auto_awesome, color: theme.accent, size: 20),
                const SizedBox(width: 12),
                Text("Ask Journii to plan a trip...", style: TextStyle(color: theme.textSecond, fontSize: 15)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _inspireMe,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.accentSoft,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shuffle_rounded, color: theme.accent, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Inspire Me — Pick My Next Destination",
                      style: TextStyle(
                        color: theme.accent, fontSize: 14, fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              if (hasTrip && nextTrip != null) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailPage(trip: nextTrip, autoStartAI: false)));
              } else {
                _showDestinationPrompt(context);
              }
            },
            child: Container(
              color: Colors.transparent, padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(hasTrip ? "UPCOMING JOURNEY" : "NO PLANS YET", style: TextStyle(color: theme.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          const SizedBox(height: 4),
                          Text(hasTrip && nextTrip != null ? (nextTrip.destination ?? nextTrip.title) : "Create an escape", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                        ]
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                    child: Icon(Icons.arrow_forward, color: theme.accentForeground, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTravelStats(WidgetRef ref, _AppTheme theme) {
    final trips = ref.watch(tripProvider);
    final Set<String> places = {};
    int days = 0;
    for (final t in trips) {
      places.add(t.destination ?? t.title);
      if (t.startDate != null && t.endDate != null) days += t.endDate!.difference(t.startDate!).inDays;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(children: [
        _buildStatCard("TRIPS",  trips.length.toString(), Icons.flight_takeoff, theme.accent, theme),
        _buildStatCard("PLACES", places.length.toString(), Icons.place_outlined, theme.green, theme),
        _buildStatCard("DAYS",   days.toString(), Icons.calendar_month_outlined, theme.golden, theme),
      ]),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color iconColor, _AppTheme theme) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: theme.card, borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.cardBorder), boxShadow: theme.smallShadow,
        ),
        child: Column(children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: theme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: theme.textMuted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildTrendingRightNow(_AppTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Trending Right Now 📈", style: TextStyle(color: theme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
            const SizedBox(height: 2),
            Text("Top Wikipedia searches across the globe", style: TextStyle(color: theme.textSecond, fontSize: 14)),
          ]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: _isLoadingTrends
              ? ModernShimmer(
            child: ListView.builder(
              scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: 3,
              itemBuilder: (_, __) => _SkeletonBox(width: 260, height: 140, radius: 28, theme: theme),
            ),
          )
              : ListView.builder(
            scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: _trendingDestinations.length,
            itemBuilder: (context, index) {
              final place = _trendingDestinations[index];
              return TrendingCard(
                place: place,
                onTap: () {
                  final dynamicDest = LiveDestination(
                    hub: GlobalHub(place['city']!, place['country']!, double.tryParse(place['lat'] ?? '0') ?? 0, double.tryParse(place['lon'] ?? '0') ?? 0),
                    temperature: 22, condition: "Trending", weatherCode: 0, sunrise: "06:00", sunset: "18:00",
                  );
                  final all = [..._chasingSun, ..._perfectWeather, ..._cozyEscapes];
                  final match = all.firstWhere((d) => d.hub.city == place['city'], orElse: () => dynamicDest);
                  _showCityDetails(context, match);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencySpotlight(_AppTheme theme) {
    final fullMeta = {
      'USD': {'flag': '🇺🇸', 'color': theme.green},
      'EUR': {'flag': '🇪🇺', 'color': theme.accent},
      'GBP': {'flag': '🇬🇧', 'color': theme.green},
      'JPY': {'flag': '🇯🇵', 'color': theme.red},
      'AUD': {'flag': '🇦🇺', 'color': theme.green},
      'CAD': {'flag': '🇨🇦', 'color': theme.red},
      'INR': {'flag': '🇮🇳', 'color': theme.golden},
      'IDR': {'flag': '🇮🇩', 'color': theme.golden},
    };
    final displayCurrencies = fullMeta.keys.where((k) => k != _baseCurrency).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text("Currency Spotlight 💱", style: TextStyle(color: theme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.cardBorder)
            ),
            child: PopupMenuButton<String>(
              initialValue: _baseCurrency,
              color: theme.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 10,
              position: PopupMenuPosition.under,
              offset: const Offset(0, 8),
              onSelected: (String newValue) {
                if (newValue != _baseCurrency) {
                  setState(() { _baseCurrency = newValue; });
                  _fetchCurrencyRates();
                }
              },
              itemBuilder: (BuildContext context) {
                return _availableBases.map((String value) {
                  final isSelected = value == _baseCurrency;
                  return PopupMenuItem<String>(
                    value: value,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text(
                      value,
                      style: TextStyle(
                        color: isSelected ? theme.accent : theme.textPrimary,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  );
                }).toList();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_baseCurrency, style: TextStyle(color: theme.textPrimary, fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Icon(Icons.keyboard_arrow_down_rounded, color: theme.textSecond, size: 18),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 78,
          child: _isLoadingCurrency
              ? ModernShimmer(
            child: ListView.builder(
              scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(), itemCount: 4,
              itemBuilder: (_, __) => _SkeletonBox(width: 120, height: 78, radius: 20, theme: theme),
            ),
          )
              : ListView.builder(
            scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), itemCount: displayCurrencies.length,
            itemBuilder: (_, i) {
              final code  = displayCurrencies[i];
              final m     = fullMeta[code]!;
              final rate  = _currencyRates[code];
              if (rate == null) return const SizedBox.shrink();
              final fmt = rate >= 100 ? rate.toStringAsFixed(1) : rate.toStringAsFixed(4);
              return Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: theme.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: theme.cardBorder), boxShadow: theme.smallShadow),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${m['flag']}  $_baseCurrency → $code', style: TextStyle(color: theme.textSecond, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(fmt, style: TextStyle(color: m['color'] as Color, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildTravelSafetySection(_AppTheme theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Travel Safety Index 🛡️", style: TextStyle(color: theme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
              IconButton(
                icon: Icon(_isSafetySearchOpen ? Icons.close : Icons.search, color: theme.textPrimary, size: 22),
                onPressed: () {
                  setState(() {
                    _isSafetySearchOpen = !_isSafetySearchOpen;
                    if (!_isSafetySearchOpen) { _safetySearchCtrl.clear(); _searchedCountrySafety = null; _searchedCountryName = null; }
                  });
                },
              )
            ],
          ),
          const SizedBox(height: 2),
          Text("Essential country info before you pack your bags", style: TextStyle(color: theme.textSecond, fontSize: 14)),

          if (_isSafetySearchOpen) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _safetySearchCtrl, style: TextStyle(color: theme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Search any country (e.g., Italy, Canada)", hintStyle: TextStyle(color: theme.textMuted, fontSize: 14),
                filled: true, fillColor: theme.searchBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                suffixIcon: _isPerformingSafetySearch
                    ? Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: theme.accent)))
                    : IconButton(icon: Icon(Icons.search, color: theme.accent, size: 20), onPressed: () => _handleSafetySearch(_safetySearchCtrl.text)),
              ),
              onSubmitted: _handleSafetySearch,
            )
          ]
        ]),
      ),
      const SizedBox(height: 16),

      if (_countrySafetyData.isEmpty && _searchedCountrySafety == null && !_isLoadingSafety)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24.0), child: Text("Could not retrieve safety info.", style: TextStyle(color: theme.textMuted)))
      else
        SizedBox(
          height: 155,
          child: _isLoadingSafety
              ? ModernShimmer(
            child: ListView.builder(
              scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: 3,
              itemBuilder: (_, __) => _SkeletonBox(width: 250, height: 155, radius: 28, theme: theme),
            ),
          )
              : ListView(
            scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              if (_searchedCountrySafety != null) _buildSafetyCard(null, theme, overrideInfo: _searchedCountrySafety, overrideName: _searchedCountryName),
              ...radarPool.map((hub) => _buildSafetyCard(hub, theme)).toList(),
            ],
          ),
        ),
    ]);
  }

  Widget _buildSafetyCard(GlobalHub? hub, _AppTheme theme, {CountrySafetyInfo? overrideInfo, String? overrideName}) {
    final info = overrideInfo ?? (hub != null ? _countrySafetyData[hub.country] : null);
    if (info == null) return const SizedBox.shrink();

    final isSearch = overrideName != null;
    final title = overrideName ?? hub!.city;
    final subtitle = overrideName != null ? "Search Result" : hub!.country;

    return Container(
      width: 250, margin: const EdgeInsets.only(right: 16), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSearch ? theme.accentSoft : theme.card, borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isSearch ? theme.accent.withOpacity(0.5) : theme.cardBorder), boxShadow: theme.smallShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, style: TextStyle(color: theme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: isSearch ? theme.accent : theme.accentSoft, borderRadius: BorderRadius.circular(8)),
                child: Text(info.region.toUpperCase(), style: TextStyle(color: isSearch ? theme.accentForeground : theme.accent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              ),
            ],
          ),
          Text(subtitle, style: TextStyle(color: isSearch ? theme.accent : theme.textSecond, fontSize: 12, fontWeight: isSearch ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          _buildSafetyDetailRow(Icons.payments_outlined, "Currency", "${info.currencyCode} (${info.currencySymbol})", theme),
          const SizedBox(height: 8),
          _buildSafetyDetailRow(Icons.translate_rounded, "Language", info.language, theme),
          const SizedBox(height: 8),
          _buildSafetyDetailRow(Icons.call_outlined, "Dial Code", info.callingCode, theme),
        ],
      ),
    );
  }

  Widget _buildSafetyDetailRow(IconData icon, String label, String value, _AppTheme theme) {
    return Row(
      children: [
        Icon(icon, color: theme.textMuted, size: 14), const SizedBox(width: 8),
        Text("$label:", style: TextStyle(color: theme.textSecond, fontSize: 12)), const SizedBox(width: 6),
        Expanded(child: Text(value, style: TextStyle(color: theme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildLiveFeedSection(String title, String subtitle, List<LiveDestination> dests, _AppTheme theme, bool isLoading) {
    if (dests.isEmpty && !isLoading) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: theme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: theme.textSecond, fontSize: 14)),
        ]),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 260,
        child: isLoading
            ? ModernShimmer(
          child: ListView.builder(
            scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: 3,
            itemBuilder: (_, __) => _SkeletonBox(width: 180, height: 260, radius: 32, theme: theme),
          ),
        )
            : ListView.builder(
          scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: dests.length,
          itemBuilder: (_, i) => DestinationCard(dest: dests[i], onTap: () => _showCityDetails(context, dests[i])),
        ),
      ),
      const SizedBox(height: 36),
    ]);
  }

  Widget _buildNewsSection(_AppTheme theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Latest Travel News 📰", style: TextStyle(color: theme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text("Live updates from around the world", style: TextStyle(color: theme.textSecond, fontSize: 14)),
        const SizedBox(height: 16),

        if (_isLoadingNews)
          ModernShimmer(
            child: Column(
              children: List.generate(4, (_) => _SkeletonBox(width: double.infinity, height: 110, radius: 24, theme: theme, bottomMargin: 16)),
            ),
          )
        else
          ..._travelNews.map((n) => _buildNewsCard(n, theme)),
      ]),
    );
  }

  Widget _buildNewsCard(TravelNews news, _AppTheme theme) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => NewsDetailSheet(news: news)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: theme.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: theme.cardBorder), boxShadow: theme.smallShadow),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
            child: SizedBox(
              width: 110, height: 110,
              child: Image.network(news.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: theme.surface, child: Icon(Icons.image_not_supported, color: theme.textMuted))),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(news.source.toUpperCase(), style: TextStyle(color: theme.accent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 6),
                  Text(news.title, style: TextStyle(color: theme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ===========================================================================
// NEW 2026 UNIFIED SHIMMER EFFECTS
// ===========================================================================

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final double rightMargin;
  final double bottomMargin;
  final _AppTheme theme;

  const _SkeletonBox({required this.width, required this.height, required this.radius, required this.theme, this.rightMargin = 16, this.bottomMargin = 0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width, height: height,
      margin: EdgeInsets.only(right: rightMargin, bottom: bottomMargin),
      decoration: BoxDecoration(color: theme.skeletonBase, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

class ModernShimmer extends StatefulWidget {
  final Widget child;
  const ModernShimmer({super.key, required this.child});

  @override
  State<ModernShimmer> createState() => _ModernShimmerState();
}

class _ModernShimmerState extends State<ModernShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _AppTheme(Theme.of(context).brightness == Brightness.dark);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                theme.skeletonBase.withOpacity(0.5),
                theme.cardBorder.withOpacity(0.8),
                theme.skeletonBase.withOpacity(0.5),
              ],
              stops: const [0.1, 0.5, 0.9],
              begin: const Alignment(-1.0, -0.5),
              end: const Alignment(2.0, 0.5),
              transform: _SlidingGradientTransform(slidePercent: _controller.value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});
  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent * 2 - 1), 0.0, 0.0);
  }
}

// ===========================================================================
// KEEPALIVE CARDS
// ===========================================================================
class TrendingCard extends StatefulWidget {
  final Map<String, String> place;
  final VoidCallback onTap;
  const TrendingCard({super.key, required this.place, required this.onTap});

  @override
  State<TrendingCard> createState() => _TrendingCardState();
}

class _TrendingCardState extends State<TrendingCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = _AppTheme(Theme.of(context).brightness == Brightness.dark);
    final query = "${widget.place['city']} travel";

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28), color: theme.card),
        child: Stack(children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: FutureBuilder<String?>(
                initialData: ImageUrlCache.getSync(query),
                future: ImageUrlCache.getAsync(query),
                builder: (_, snap) => (snap.hasData && snap.data != null)
                    ? Image.network(snap.data!, fit: BoxFit.cover)
                    : Container(color: theme.surface),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                ),
              ),
            ),
          ),
          Positioned(
            top: 16, left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: theme.red, borderRadius: BorderRadius.circular(12)),
              child: Text(widget.place['trend']!,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
          Positioned(
            bottom: 16, left: 20,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.place['city']!, style: const TextStyle(color: Colors.white,
                  fontSize: 20, fontWeight: FontWeight.bold)),
              Text(widget.place['country']!, style: const TextStyle(
                  color: Colors.white70, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class DestinationCard extends StatefulWidget {
  final LiveDestination dest;
  final VoidCallback onTap;
  const DestinationCard({super.key, required this.dest, required this.onTap});

  @override
  State<DestinationCard> createState() => _DestinationCardState();
}

class _DestinationCardState extends State<DestinationCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = _AppTheme(Theme.of(context).brightness == Brightness.dark);
    final query = "${widget.dest.hub.city} travel";

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 180,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32), color: theme.surface),
        child: Stack(children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: FutureBuilder<String?>(
                initialData: ImageUrlCache.getSync(query),
                future: ImageUrlCache.getAsync(query),
                builder: (_, snap) => (snap.hasData && snap.data != null)
                    ? Image.network(snap.data!, fit: BoxFit.cover)
                    : Container(color: theme.surface),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.transparent,
                    Colors.black.withOpacity(0.45)
                  ],
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12, right: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.black.withOpacity(0.35),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(children: [
                      const Icon(Icons.thermostat, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text("${widget.dest.temperature}°C",
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.wb_twilight,
                          color: Color(0xFFF5A623), size: 12),
                      const SizedBox(width: 4),
                      Text(widget.dest.sunset,
                          style: const TextStyle(color: Color(0xFFF5A623),
                              fontWeight: FontWeight.bold, fontSize: 10)),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.dest.hub.city,
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold, fontSize: 22,
                        letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text("${widget.dest.hub.country} • ${widget.dest.condition}",
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ===========================================================================
// CITY DETAIL SHEET
// ===========================================================================
class CityDetailSheet extends StatefulWidget {
  final LiveDestination dest;
  const CityDetailSheet({super.key, required this.dest});
  @override
  State<CityDetailSheet> createState() => _CityDetailSheetState();
}

class _CityDetailSheetState extends State<CityDetailSheet> {
  String _summary   = "Loading travel insights...";
  bool   _isLoading = true;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    try {
      final res = await http.get(Uri.parse(
          "https://en.wikipedia.org/api/rest_v1/page/summary/${widget.dest.hub.city}"));
      if (res.statusCode == 200) {
        final full      = json.decode(res.body)['extract'] ?? "No summary available.";
        final sentences = full.split('. ');
        setState(() {
          _summary  = sentences.take(3).join('. ') + (sentences.length > 3 ? '...' : '');
          _isLoading = false;
        });
      } else {
        _fallback();
      }
    } catch (_) { _fallback(); }
  }

  void _fallback() => setState(() {
    _summary   = "Ready to explore ${widget.dest.hub.city}? "
        "Tap below to let Journii build a personalized itinerary for you.";
    _isLoading = false;
  });

  @override
  Widget build(BuildContext context) {
    final theme = _AppTheme(Theme.of(context).brightness == Brightness.dark);
    final query = "${widget.dest.hub.city} travel";

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: theme.sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: SizedBox(
            height: 250, width: double.infinity,
            child: Stack(children: [
              Positioned.fill(
                child: FutureBuilder<String?>(
                  initialData: ImageUrlCache.getSync(query),
                  future: ImageUrlCache.getAsync(query),
                  builder: (_, snap) => (snap.hasData && snap.data != null)
                      ? Image.network(snap.data!, fit: BoxFit.cover)
                      : Container(color: theme.surface),
                ),
              ),
              Positioned.fill(child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.sheetBg, Colors.transparent],
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  ),
                ),
              )),
              Positioned(top: 16, right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                        color: Colors.black45, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ]),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            physics: const BouncingScrollPhysics(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.dest.hub.city,
                        style: TextStyle(color: theme.textPrimary, fontSize: 36,
                            fontWeight: FontWeight.bold, height: 1.1)),
                    Text(widget.dest.hub.country,
                        style: TextStyle(color: theme.textSecond, fontSize: 18)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.cardBorder),
                    ),
                    child: Column(children: [
                      Icon(Icons.thermostat, color: theme.accent, size: 24),
                      const SizedBox(height: 4),
                      Text("${widget.dest.temperature}°C",
                          style: TextStyle(color: theme.textPrimary,
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(widget.dest.condition,
                          style: TextStyle(color: theme.textMuted, fontSize: 10)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.goldenSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.golden.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(children: [
                      Icon(Icons.wb_sunny_outlined, color: theme.golden, size: 18),
                      const SizedBox(width: 8),
                      Text("Sunrise: ${widget.dest.sunrise}",
                          style: TextStyle(color: theme.golden,
                              fontWeight: FontWeight.bold)),
                    ]),
                    Container(width: 1, height: 20,
                        color: theme.golden.withOpacity(0.3)),
                    Row(children: [
                      Icon(Icons.wb_twilight, color: theme.golden, size: 18),
                      const SizedBox(width: 8),
                      Text("Sunset: ${widget.dest.sunset}",
                          style: TextStyle(color: theme.golden,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text("LIVE INSIGHTS",
                  style: TextStyle(color: theme.textMuted, fontSize: 12,
                      fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(child: CircularProgressIndicator(
                      color: theme.textMuted, strokeWidth: 2)),
                )
              else
                Text(_summary,
                    style: TextStyle(color: theme.textPrimary,
                        fontSize: 16, height: 1.6)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => LiveJourneyPlanner(
                          destination: widget.dest.hub.city),
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accent, foregroundColor: theme.accentForeground,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  child: Text("Start Journey in ${widget.dest.hub.city}",
                      style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.bold, color: theme.accentForeground)),
                ),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ===========================================================================
// INSPIRE ME SHEET
// ===========================================================================
class _InspireMeSheet extends StatelessWidget {
  final LiveDestination dest;
  final VoidCallback onPlanTrip;
  const _InspireMeSheet({required this.dest, required this.onPlanTrip});

  @override
  Widget build(BuildContext context) {
    final theme = _AppTheme(Theme.of(context).brightness == Brightness.dark);
    final query = "${dest.hub.city} travel";

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: theme.sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: SizedBox(
            height: 220, width: double.infinity,
            child: Stack(children: [
              Positioned.fill(
                child: FutureBuilder<String?>(
                  initialData: ImageUrlCache.getSync(query),
                  future: ImageUrlCache.getAsync(query),
                  builder: (_, snap) => (snap.hasData && snap.data != null)
                      ? Image.network(snap.data!, fit: BoxFit.cover)
                      : Container(color: theme.surface),
                ),
              ),
              Positioned.fill(child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.sheetBg, Colors.transparent],
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  ),
                ),
              )),
              Positioned(
                top: 16, left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: theme.accent, borderRadius: BorderRadius.circular(12)),
                  child: Text("✨ YOUR PICK",
                      style: TextStyle(color: theme.accentForeground, fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              Positioned(
                top: 16, right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                        color: Colors.black45, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dest.hub.city,
                style: TextStyle(color: theme.textPrimary, fontSize: 32,
                    fontWeight: FontWeight.bold)),
            Text("${dest.hub.country} · ${dest.condition} · ${dest.temperature}°C",
                style: TextStyle(color: theme.textSecond, fontSize: 15)),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.wb_twilight, color: theme.golden, size: 16),
              const SizedBox(width: 6),
              Text("Golden hour at ${dest.sunset} local time",
                  style: TextStyle(color: theme.golden, fontSize: 13)),
            ]),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton(
                onPressed: onPlanTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accent, foregroundColor: theme.accentForeground,
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
                child: Text("Plan a Trip to ${dest.hub.city}",
                    style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.bold, color: theme.accentForeground)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ===========================================================================
// NEWS DETAIL SHEET
// ===========================================================================
class NewsDetailSheet extends StatelessWidget {
  final TravelNews news;
  const NewsDetailSheet({super.key, required this.news});

  @override
  Widget build(BuildContext context) {
    final theme = _AppTheme(Theme.of(context).brightness == Brightness.dark);
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: theme.sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: SizedBox(
            height: 220, width: double.infinity,
            child: Stack(children: [
              Positioned.fill(child: Image.network(
                news.imageUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: theme.surface),
              )),
              Positioned.fill(child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.sheetBg, Colors.transparent],
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  ),
                ),
              )),
              Positioned(
                top: 16, right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                        color: Colors.black45, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ]),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            physics: const BouncingScrollPhysics(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(news.source.toUpperCase(),
                    style: TextStyle(color: theme.accent, fontSize: 11,
                        fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
              const SizedBox(height: 16),
              Text(news.title,
                  style: TextStyle(color: theme.textPrimary, fontSize: 24,
                      fontWeight: FontWeight.bold, height: 1.2)),
              const SizedBox(height: 24),
              Text("SUMMARY",
                  style: TextStyle(color: theme.textMuted, fontSize: 12,
                      fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              Text(news.description,
                  style: TextStyle(color: theme.textPrimary,
                      fontSize: 16, height: 1.6)),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ]),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}