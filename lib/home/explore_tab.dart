import 'dart:ui';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'event_detail_page.dart';
import '../../services/translation_service.dart';

class ExploreTab extends ConsumerStatefulWidget {
  const ExploreTab({super.key});

  @override
  ConsumerState<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends ConsumerState<ExploreTab> {
  // ===========================================================================
  // STATE & CONTROLLERS
  // ===========================================================================

  int _selectedFilterIndex = 0;

  final List<String> _filters = [
    "All",
    "Concerts 🎸",
    "Sports ⚽",
    "Festivals 🎪",
    "Theater 🎭",
  ];

  final TextEditingController _searchController =
  TextEditingController();

  final MapController _mapController =
  MapController();

  final PageController _pageController =
  PageController(
    viewportFraction: 0.85,
  );

  // All discovered events for the current destination.
  List<Map<String, dynamic>> _allEvents = [];

  // Only successfully mapped events matching the selected filter.
  List<Map<String, dynamic>> _events = [];

  bool _isLoading = false;
  bool _isGeocoding = false;

  String _currentCity = "Explore the world";

  double _currentLat = 20.0;
  double _currentLon = 0.0;

  int _searchRequestId = 0;

  // ===========================================================================
  // CACHE
  // ===========================================================================

  static const Duration _eventCacheDuration =
  Duration(hours: 12);

  static const String _eventCachePrefix =
      'journii_explore_events_';

  final Map<String, LatLng> _destinationCache = {};
  final Map<String, String?> _destinationCountryCodeCache = {};
  final Map<String, String> _destinationTypeCache = {};

  String? _currentCountryCode;
  String _currentDestinationType = '';

  // Session cache only.
  //
  // Mapbox Search Box data is not persisted here. This cache is cleared when
  // the app process ends.
  final Map<String, LatLng> _venueCoordinateCache = {};

  // Prevent duplicate simultaneous Mapbox requests.
  final Map<String, Future<LatLng?>>
  _venueRequestsInFlight = {};

  SharedPreferences? _preferences;

  // ---------------------------------------------------------------------------
  // TRANSLATED EVENT DISPLAY CACHE
  // ---------------------------------------------------------------------------
  // These values are presentation-only. The original event name/venue remain
  // untouched for StungEvents, Mapbox geocoding, caching, and backend use.
  final Map<String, String> _translatedEventNames = {};
  final Map<String, String> _translatedEventVenues = {};
  int _displayTranslationRequestId = 0;

  // ===========================================================================
  // DESTINATION SUGGESTIONS
  // ===========================================================================

  final List<Map<String, String>>
  _destinationSuggestions = [
    {
      "name": "Tokyo",
      "subtitle": "Nightlife & major events",
    },
    {
      "name": "London",
      "subtitle": "Football, theatre & concerts",
    },
    {
      "name": "Paris",
      "subtitle": "Culture, music & festivals",
    },
    {
      "name": "Dubai",
      "subtitle": "Sports, shows & experiences",
    },
    {
      "name": "New York",
      "subtitle": "Concerts & iconic events",
    },
  ];

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    // IMPORTANT:
    // Explore does NOT automatically call the event API when the tab opens.
    _initializeLocalCache();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _mapController.move(
        const LatLng(20.0, 0.0),
        2.2,
      );
    });
  }

  Future<void> _initializeLocalCache() async {
    try {
      _preferences =
      await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint(
        "SharedPreferences initialization error: $e",
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // MAP
  // ===========================================================================

  void _fitMapToMarkers() {
    if (!mounted) return;

    if (_events.isEmpty) {
      _mapController.move(
        LatLng(
          _currentLat,
          _currentLon,
        ),
        _currentCity ==
            "Explore the world"
            ? 2.2
            : 11.5,
      );
      return;
    }

    final points = _events
        .where(
          (event) =>
      _validCoordinate(
        event['latitude'],
      ) &&
          _validCoordinate(
            event['longitude'],
          ),
    )
        .map(
          (event) => LatLng(
        (event['latitude'] as num)
            .toDouble(),
        (event['longitude'] as num)
            .toDouble(),
      ),
    )
        .toList();

    if (points.isEmpty) {
      _mapController.move(
        LatLng(
          _currentLat,
          _currentLon,
        ),
        11.5,
      );
      return;
    }

    if (points.length == 1) {
      _mapController.move(
        points.first,
        13.5,
      );
      return;
    }

    final bounds =
    LatLngBounds.fromPoints(
      points,
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding:
        const EdgeInsets.fromLTRB(
          50,
          150,
          50,
          180,
        ),
      ),
    );
  }

  bool _validCoordinate(
      dynamic value,
      ) {
    if (value is! num) {
      return false;
    }

    return value.toDouble() != 0.0;
  }

  // ===========================================================================
  // DESTINATION SEARCH
  // ===========================================================================

  Future<void> _handleSearch(
      String cityQuery,
      ) async {
    final query =
    cityQuery.trim();

    if (query.isEmpty) return;

    final requestId =
    ++_searchRequestId;

    FocusScope.of(context).unfocus();

    _displayTranslationRequestId++;
    _translatedEventNames.clear();
    _translatedEventVenues.clear();

    setState(() {
      _isLoading = true;
      _isGeocoding = false;
      _allEvents = [];
      _events = [];
    });

    try {
      final destination =
      await _mapboxGeocodeDestination(
        query,
      );

      if (!mounted ||
          requestId !=
              _searchRequestId) {
        return;
      }

      if (destination == null) {
        setState(() {
          _isLoading = false;
          _isGeocoding = false;
        });

        _showMessage(
          "We couldn't find that destination.",
        );

        return;
      }

      final cityName =
      destination['name']
      as String;

      final latitude =
      destination['latitude']
      as double;

      final longitude =
      destination['longitude']
      as double;

      final countryCode =
      destination['countryCode']
          ?.toString()
          .trim()
          .toUpperCase();

      final destinationType =
          destination['featureType']
              ?.toString()
              .trim()
              .toLowerCase() ?? '';

      setState(() {
        _currentCity =
            cityName;

        _searchController.text =
            cityName;

        _currentLat =
            latitude;

        _currentLon =
            longitude;

        _currentCountryCode = countryCode;
        _currentDestinationType = destinationType;
      });

      _mapController.move(
        LatLng(
          latitude,
          longitude,
        ),
        11.5,
      );

      await _loadEventsForDestination(
        cityName: cityName,
        latitude: latitude,
        longitude: longitude,
        countryCode: countryCode,
        destinationType: destinationType,
        forceRefresh: false,
      );

      if (!mounted ||
          requestId !=
              _searchRequestId) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint(
        "Destination search error: $e",
      );

      if (!mounted ||
          requestId !=
              _searchRequestId) {
        return;
      }

      setState(() {
        _isLoading = false;
        _isGeocoding = false;
      });

      _showMessage(
        "Something went wrong while finding that destination.",
      );
    }
  }

  // ===========================================================================
  // MAPBOX DESTINATION SEARCH
  // ===========================================================================

  Future<Map<String, dynamic>?>
  _mapboxGeocodeDestination(
      String query,
      ) async {
    final token =
    dotenv.env[
    'MAPBOX_PUBLIC_TOKEN']
        ?.trim();

    if (token == null ||
        token.isEmpty) {
      _showMessage(
        "Mapbox public token is missing from your .env file.",
      );
      return null;
    }

    final normalized =
    query.toLowerCase().trim();

    final cached =
    _destinationCache[
    normalized];

    if (cached != null) {
      return {
        'name':
        _prettyDestinationName(
          query,
        ),
        'latitude':
        cached.latitude,
        'longitude':
        cached.longitude,
        'countryCode':
        _destinationCountryCodeCache[normalized],
        'featureType':
        _destinationTypeCache[normalized] ?? '',
      };
    }

    final uri = Uri.https(
      'api.mapbox.com',
      '/search/searchbox/v1/forward',
      {
        'q': query,
        'access_token':
        token,
        'language': 'en',
        'limit': '5',
        'types':
        'country,region,district,place,locality,neighborhood',
      },
    );

    final response =
    await http.get(uri);

    if (response.statusCode !=
        200) {
      debugPrint(
        "Mapbox destination error "
            "${response.statusCode}: "
            "${response.body}",
      );
      return null;
    }

    final decoded =
    json.decode(
      response.body,
    );

    final features =
    decoded['features'];

    if (features is! List ||
        features.isEmpty) {
      return null;
    }

    Map<String, dynamic>?
    selectedFeature;

    const preferredTypes = [
      'place',
      'locality',
      'district',
      'region',
      'country',
    ];

    for (final preferred
    in preferredTypes) {
      for (final rawFeature
      in features) {
        if (rawFeature is! Map) {
          continue;
        }

        final properties =
        rawFeature[
        'properties'];

        final type =
        properties?[
        'feature_type']
            ?.toString()
            .toLowerCase();

        if (type == preferred) {
          selectedFeature =
          Map<String, dynamic>.from(
            rawFeature,
          );
          break;
        }
      }

      if (selectedFeature !=
          null) {
        break;
      }
    }

    selectedFeature ??=
    Map<String, dynamic>.from(
      features.first,
    );

    final geometry =
    selectedFeature[
    'geometry'];

    final coordinates =
    geometry?[
    'coordinates'];

    if (coordinates is! List ||
        coordinates.length <
            2) {
      return null;
    }

    final lon =
    double.tryParse(
      coordinates[0]
          .toString(),
    );

    final lat =
    double.tryParse(
      coordinates[1]
          .toString(),
    );

    if (lat == null ||
        lon == null) {
      return null;
    }

    final properties =
    selectedFeature[
    'properties'];

    final featureType =
        properties?['feature_type']
            ?.toString()
            .trim()
            .toLowerCase() ?? '';

    String? countryCode;
    final contextData = properties?['context'];
    if (contextData is Map) {
      final countryData = contextData['country'];
      if (countryData is Map) {
        countryCode = countryData['country_code']
            ?.toString()
            .trim()
            .toUpperCase();
      }
    }

    final mapboxName =
    properties?['name']
        ?.toString()
        .trim();

    final finalName =
    mapboxName != null &&
        mapboxName.isNotEmpty
        ? mapboxName
        : _prettyDestinationName(
      query,
    );

    final coordinate =
    LatLng(
      lat,
      lon,
    );

    _destinationCache[
    normalized] =
        coordinate;
    _destinationCountryCodeCache[normalized] =
        countryCode;
    _destinationTypeCache[normalized] =
        featureType;

    return {
      'name':
      finalName,
      'latitude':
      lat,
      'longitude':
      lon,
      'countryCode':
      countryCode,
      'featureType':
      featureType,
    };
  }

  String _prettyDestinationName(
      String value,
      ) {
    final trimmed =
    value.trim();

    if (trimmed.isEmpty) {
      return "Explore";
    }

    return trimmed
        .split(' ')
        .map(
          (word) =>
      word.isEmpty
          ? word
          : '${word[0].toUpperCase()}'
          '${word.substring(1)}',
    )
        .join(' ');
  }

  // ===========================================================================
  // SUGGESTED DESTINATIONS
  // ===========================================================================

  Future<void>
  _selectSuggestedDestination(
      String destination,
      ) async {
    _searchController.text =
        destination;

    await _handleSearch(
      destination,
    );
  }

  // ===========================================================================
  // EVENT LOADING
  // ===========================================================================

  Future<void>
  _loadEventsForDestination({
    required String cityName,
    required double latitude,
    required double longitude,
    String? countryCode,
    String destinationType = '',
    required bool forceRefresh,
  }) async {
    final cacheKey =
    _eventCacheKey(
      cityName,
      latitude,
      longitude,
    );

    // -------------------------------------------------------------------------
    // 1. CHECK PERSISTENT EVENT CACHE
    // -------------------------------------------------------------------------

    if (!forceRefresh) {
      final cachedEvents =
      await _readEventCache(
        cacheKey,
      );

      if (cachedEvents !=
          null &&
          cachedEvents.isNotEmpty) {
        debugPrint(
          "Using cached event results for $cityName",
        );

        if (!mounted) return;

        setState(() {
          _allEvents =
              cachedEvents
                  .map(
                    (event) =>
                Map<String, dynamic>.from(
                  event,
                ),
              )
                  .toList();

          _events = [];

          _isLoading = false;
          _isGeocoding = true;
        });

        _translateEventsForDisplay(_allEvents);

        await _resolveAndDisplayVenues(
          requestEvents:
          _allEvents,
          destinationLatitude:
          latitude,
          destinationLongitude:
          longitude,
        );

        if (!mounted) return;

        setState(() {
          _isGeocoding = false;
        });

        _applyCurrentFilter(
          animateMap: true,
        );

        return;
      }
    }

    // -------------------------------------------------------------------------
    // 2. NO VALID CACHE → STUNGEVENTS
    // -------------------------------------------------------------------------

    setState(() {
      _isLoading = true;
      _isGeocoding = false;
    });

    final generatedEvents =
    await _fetchEventsFromStungEvents(
      cityName: cityName,
      latitude: latitude,
      longitude: longitude,
      countryCode: countryCode,
      destinationType: destinationType,
    );

    if (!mounted) return;

    if (generatedEvents.isEmpty) {
      setState(() {
        _allEvents = [];
        _events = [];
        _isLoading = false;
        _isGeocoding = false;
      });

      _showMessage(
        "No upcoming events were discovered for $cityName.",
      );

      return;
    }

    // -------------------------------------------------------------------------
    // 3. SAVE RAW EVENT RESULTS
    // -------------------------------------------------------------------------
    //
    // Coordinates from Mapbox are deliberately not persisted here.
    //

    await _writeEventCache(
      cacheKey,
      generatedEvents,
    );

    setState(() {
      _allEvents =
          generatedEvents
              .map(
                (event) =>
            Map<String, dynamic>.from(
              event,
            ),
          )
              .toList();

      _events = [];

      _isLoading = false;
      _isGeocoding = true;
    });

    _translateEventsForDisplay(_allEvents);

    // -------------------------------------------------------------------------
    // 4. MAP VENUES
    // -------------------------------------------------------------------------

    await _resolveAndDisplayVenues(
      requestEvents:
      _allEvents,
      destinationLatitude:
      latitude,
      destinationLongitude:
      longitude,
    );

    if (!mounted) return;

    setState(() {
      _isGeocoding = false;
    });

    _applyCurrentFilter(
      animateMap: true,
    );
  }

  // ===========================================================================
  // EXPLICIT REFRESH
  // ===========================================================================

  Future<void> _refreshCurrentDestination() async {
    if (_currentCity ==
        "Explore the world") {
      _showMessage(
        "Choose a destination first.",
      );
      return;
    }

    final requestId =
    ++_searchRequestId;

    _displayTranslationRequestId++;
    _translatedEventNames.clear();
    _translatedEventVenues.clear();

    setState(() {
      _isLoading = true;
      _isGeocoding = false;
      _allEvents = [];
      _events = [];
    });

    final cacheKey =
    _eventCacheKey(
      _currentCity,
      _currentLat,
      _currentLon,
    );

    await _deleteEventCache(
      cacheKey,
    );

    if (!mounted ||
        requestId !=
            _searchRequestId) {
      return;
    }

    await _loadEventsForDestination(
      cityName:
      _currentCity,
      latitude:
      _currentLat,
      longitude:
      _currentLon,
      countryCode:
      _currentCountryCode,
      destinationType:
      _currentDestinationType,
      forceRefresh:
      true,
    );

    if (!mounted ||
        requestId !=
            _searchRequestId) {
      return;
    }

    setState(() {
      _isLoading = false;
    });
  }

  // ===========================================================================
  // STUNGEVENTS EVENT DISCOVERY
  // ===========================================================================

  Future<List<Map<String, dynamic>>>
  _fetchEventsFromStungEvents({
    required String cityName,
    required double latitude,
    required double longitude,
    String? countryCode,
    String destinationType = '',
  }) async {
    const host = 'api.stungevents.com';
    const path = '/events';

    final normalizedCountryCode =
    countryCode?.trim().toUpperCase();

    final isCountry = destinationType == 'country';

    const cityLikeTypes = {
      'place',
      'locality',
      'neighborhood',
      'city',
      'district',
      'region',
    };

    final baseParams = <String, String>{
      'limit': '100',
      'offset': '0',
    };

    // StungEvents documents city and country as first-class filters.
    // For countries, the resolved Mapbox display name (for example Japan)
    // is the best value for the country filter. For city-like destinations,
    // use the destination name directly.
    if (isCountry) {
      if (cityName.trim().isNotEmpty) {
        baseParams['country'] = cityName.trim();
      }
    } else if (cityLikeTypes.contains(destinationType) &&
        cityName.trim().isNotEmpty) {
      baseParams['city'] = cityName.trim();
    } else if (cityName.trim().isNotEmpty) {
      // Keep the existing region/district retrieval mechanism functional by
      // attempting the destination name as a city/prefix search first.
      baseParams['city'] = cityName.trim();
    }

    Future<List<Map<String, dynamic>>> requestEvents(
        Map<String, String> params) async {
      final uri = Uri.https(
        host,
        path,
        params,
      );

      try {
        final response = await http.get(
          uri,
          headers: const {
            'Accept': 'application/json',
          },
        );

        if (response.statusCode != 200) {
          debugPrint(
            "StungEvents error ${response.statusCode}: ${response.body}",
          );
          return [];
        }

        final decoded = json.decode(response.body);

        if (decoded is! Map) {
          debugPrint(
            "StungEvents returned an unexpected response shape.",
          );
          return [];
        }

        final rawEvents = decoded['events'];

        if (rawEvents is! List) {
          debugPrint(
            "StungEvents response did not contain an events array.",
          );
          return [];
        }

        return rawEvents
            .whereType<Map>()
            .map((event) => Map<String, dynamic>.from(event))
            .toList();
      } catch (e) {
        debugPrint(
          "StungEvents event retrieval error: $e",
        );
        return [];
      }
    }

    try {
      var rawEvents = await requestEvents(baseParams);

      // If a non-country destination did not return anything, try the
      // country filter with the resolved ISO-2 code as a conservative
      // fallback. This does not alter the UI or cache mechanism; it only
      // gives the retrieval layer another documented endpoint filter to use.
      if (rawEvents.isEmpty &&
          !isCountry &&
          normalizedCountryCode != null &&
          normalizedCountryCode.length == 2) {
        final fallbackParams = <String, String>{
          'country': normalizedCountryCode,
          'limit': '100',
          'offset': '0',
        };

        debugPrint(
          "StungEvents returned no events for $cityName. Trying country fallback $normalizedCountryCode.",
        );

        rawEvents = await requestEvents(fallbackParams);
      }

      if (rawEvents.isEmpty) {
        debugPrint(
          "StungEvents returned no events for $cityName.",
        );
        return [];
      }

      final normalized = <Map<String, dynamic>>[];
      final seenKeys = <String>{};

      for (int index = 0; index < rawEvents.length; index++) {
        final event = _normalizeStungEvent(
          rawEvents[index],
          cityName,
          index,
        );

        if (event == null) {
          continue;
        }

        final key =
            '${event['name']?.toString().toLowerCase().trim()}|'
            '${event['venue']?.toString().toLowerCase().trim()}|'
            '${event['date']?.toString().trim()}';

        if (seenKeys.contains(key)) {
          continue;
        }

        seenKeys.add(key);
        normalized.add(event);

        // Preserve the same practical 8–15 event display range used by the
        // previous retrieval mechanism while allowing the source API to
        // return a larger pool for filtering/deduplication.
        if (normalized.length >= 15) {
          break;
        }
      }

      debugPrint(
        "StungEvents returned ${normalized.length} usable events for $cityName.",
      );

      return normalized;
    } catch (e) {
      debugPrint(
        "StungEvents event retrieval error: $e",
      );
      return [];
    }
  }

  Map<String, dynamic>? _normalizeStungEvent(
      Map raw,
      String cityName,
      int index,
      ) {
    String readString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value.trim();
      return value.toString().trim();
    }

    String readNestedString(
        dynamic value,
        List<String> keys,
        ) {
      if (value is Map) {
        for (final key in keys) {
          final candidate = readString(value[key]);
          if (candidate.isNotEmpty) {
            return candidate;
          }
        }
      }
      return '';
    }

    final name = readString(
      raw['title'] ?? raw['name'],
    );

    if (name.isEmpty) {
      return null;
    }

    final slug = readString(
      raw['slug'] ?? raw['id'],
    );

    final startUtc = readString(
      raw['start_utc'] ??
          raw['start'] ??
          raw['startDate'] ??
          raw['date'],
    );

    final normalizedDate = _normalizeDate(startUtc);

    final rawVenue = raw['venue'];

    final venueName = readString(
      raw['venue_name'] ??
          (rawVenue is Map ? rawVenue['name'] : rawVenue),
    );

    if (venueName.isEmpty) {
      return null;
    }

    final venueAddress = readString(
      raw['venue_address'] ??
          raw['address'] ??
          raw['venueAddress'] ??
          (rawVenue is Map
              ? rawVenue['address'] ?? rawVenue['formatted_address']
              : null),
    );

    final nestedVenueAddress = readNestedString(
      rawVenue,
      const [
        'address',
        'address_line',
        'formatted_address',
      ],
    );

    final address = venueAddress.isNotEmpty
        ? venueAddress
        : nestedVenueAddress;

    final eventCity = readString(
      raw['city'] ??
          (rawVenue is Map ? rawVenue['city'] : null),
    );

    final country = readString(
      raw['country'] ??
          (rawVenue is Map ? rawVenue['country'] : null),
    );

    final categorySource = readString(
      raw['category'] ??
          raw['type'] ??
          raw['genre'],
    );

    final category = _normalizeStungCategory(
      name: name,
      category: categorySource,
    );

    final description = readString(
      raw['description'] ??
          raw['summary'] ??
          raw['info'] ??
          raw['details'],
    );

    final finalDescription = description.isNotEmpty
        ? description
        : 'Upcoming $category event in ${eventCity.isNotEmpty ? eventCity : cityName}.';

    final ticketUrl = readString(
      raw['ticket_url'] ??
          raw['ticketUrl'] ??
          raw['url'] ??
          raw['event_url'],
    );

    final imageUrl = _extractStungImageUrl(
      raw,
    );

    final eventId = slug.isNotEmpty
        ? slug
        : _stableEventId(
      '${name.toLowerCase()}|'
          '${venueName.toLowerCase()}|'
          '${eventCity.toLowerCase()}|'
          '${normalizedDate ?? index}',
    );

    return {
      'id': eventId,
      'name': name,
      'description': finalDescription,
      'date': normalizedDate ?? 'TBA',
      'imageUrl': imageUrl ??
          'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&w=500&q=60',
      'venue': venueName,
      'address': address,
      'city': eventCity.isNotEmpty ? eventCity : cityName,
      'country': country,
      'state': '',
      'latitude': 0.0,
      'longitude': 0.0,
      'ticketUrl': ticketUrl.isNotEmpty
          ? ticketUrl
          : slug.isNotEmpty
          ? 'https://api.stungevents.com/click/${Uri.encodeComponent(slug)}'
          : 'https://www.google.com/search?q='
          '${Uri.encodeComponent('$name ${eventCity.isNotEmpty ? eventCity : cityName} tickets')}',
      'categoryTag': category,
    };
  }

  String? _extractStungImageUrl(
      Map raw,
      ) {
    String? read(dynamic value) {
      final text = value?.toString().trim();
      return text != null && text.isNotEmpty ? text : null;
    }

    final direct = read(
      raw['image_url'] ??
          raw['imageUrl'] ??
          raw['image'],
    );

    if (direct != null) {
      return direct;
    }

    final images = raw['images'];
    if (images is List) {
      for (final image in images) {
        if (image is Map) {
          final candidate = read(
            image['url'] ?? image['image_url'],
          );
          if (candidate != null) {
            return candidate;
          }
        } else {
          final candidate = read(image);
          if (candidate != null) {
            return candidate;
          }
        }
      }
    }

    return null;
  }

  String _normalizeStungCategory({
    required String name,
    required String category,
  }) {
    final combined =
    '$name $category'.toLowerCase().trim();

    if (combined.contains('festival') ||
        combined.contains('carnival') ||
        combined.contains('celebration')) {
      return 'Festivals 🎪';
    }

    if (combined.contains('sport') ||
        combined.contains('football') ||
        combined.contains('soccer') ||
        combined.contains('basketball') ||
        combined.contains('tennis') ||
        combined.contains('baseball') ||
        combined.contains('cricket') ||
        combined.contains('racing') ||
        combined.contains('marathon') ||
        combined.contains('championship') ||
        combined.contains('wrestling') ||
        combined.contains('motorsport') ||
        combined.contains('esport')) {
      return 'Sports ⚽';
    }

    if (combined.contains('music') ||
        combined.contains('concert') ||
        combined.contains('gig') ||
        combined.contains('band') ||
        combined.contains('live music')) {
      return 'Concerts 🎸';
    }

    if (combined.contains('theater') ||
        combined.contains('theatre') ||
        combined.contains('comedy') ||
        combined.contains('performing') ||
        combined.contains('opera') ||
        combined.contains('musical') ||
        combined.contains('broadway') ||
        combined.contains('play') ||
        combined.contains('arts & theatre') ||
        combined.contains('arts and theatre') ||
        combined.contains('film') ||
        combined.contains('cinema')) {
      return 'Theater 🎭';
    }

    return 'All';
  }

  String? _normalizeDate(
      String value,
      ) {
    if (value.isEmpty) {
      return null;
    }

    final match =
    RegExp(
      r'(\d{4})-(\d{1,2})-(\d{1,2})',
    ).firstMatch(value);

    if (match == null) {
      return null;
    }

    final year =
    int.tryParse(
      match.group(1) ?? '',
    );

    final month =
    int.tryParse(
      match.group(2) ?? '',
    );

    final day =
    int.tryParse(
      match.group(3) ?? '',
    );

    if (year == null ||
        month == null ||
        day == null) {
      return null;
    }

    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }

    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  String _stableEventId(
      String value,
      ) {
    var hash = 0;

    for (final codeUnit
    in value.codeUnits) {
      hash = 0x1fffffff &
      (hash + codeUnit);

      hash = 0x1fffffff &
      (hash +
          ((hash &
          0x0007ffff) <<
              10));

      hash ^= hash >> 6;
    }

    hash = 0x1fffffff &
    (hash +
        ((hash &
        0x03ffffff) <<
            3));

    hash ^= hash >> 11;

    hash = 0x1fffffff &
    (hash +
        ((hash &
        0x00003fff) <<
            15));

    return 'journii_$hash';
  }

  // ===========================================================================
  // MAPBOX VENUE RESOLUTION
  // ===========================================================================

  Future<void>
  _resolveAndDisplayVenues({
    required List<Map<String, dynamic>>
    requestEvents,
    required double
    destinationLatitude,
    required double
    destinationLongitude,
  }) async {
    if (requestEvents.isEmpty) {
      return;
    }

    setState(() {
      _isGeocoding = true;
    });

    // -------------------------------------------------------------------------
    // Deduplicate the venue searches.
    // -------------------------------------------------------------------------

    final Map<String,
        Map<String, String>>
    uniqueVenues = {};

    for (final event
    in requestEvents) {
      final venue =
          event['venue']
              ?.toString()
              .trim() ??
              '';

      final address =
          event['address']
              ?.toString()
              .trim() ??
              '';

      final city =
          event['city']
              ?.toString()
              .trim() ??
              _currentCity;

      final country =
          event['country']
              ?.toString()
              .trim() ??
              '';

      if (venue.isEmpty) {
        continue;
      }

      final searchText =
      [
        venue,
        address,
        city,
        country,
      ].where(
            (value) =>
        value
            .trim()
            .isNotEmpty,
      ).join(', ');

      final key =
      searchText
          .toLowerCase()
          .trim();

      if (key.isEmpty) {
        continue;
      }

      uniqueVenues.putIfAbsent(
        key,
            () => {
          'searchText':
          searchText,
        },
      );
    }

    final venueEntries =
    uniqueVenues.entries.toList();

    // Five simultaneous requests.
    // Mapbox documents a default Search Box rate limit of 10 requests/sec.
    const batchSize = 5;

    for (
    int start = 0;
    start <
        venueEntries.length;
    start += batchSize
    ) {
      if (!mounted) return;

      final end =
      (start + batchSize <
          venueEntries.length)
          ? start + batchSize
          : venueEntries.length;

      final batch =
      venueEntries.sublist(
        start,
        end,
      );

      final results =
      await Future.wait(
        batch.map(
              (entry) async {
            final coordinates =
            await _mapboxGeocodeVenue(
              searchText:
              entry.value[
              'searchText']!,
              proximityLatitude:
              destinationLatitude,
              proximityLongitude:
              destinationLongitude,
            );

            return MapEntry(
              entry.key,
              coordinates,
            );
          },
        ),
      );

      if (!mounted) return;

      // Apply this batch's coordinates.
      for (final result
      in results) {
        final key =
            result.key;

        final coordinates =
            result.value;

        if (coordinates == null) {
          continue;
        }

        for (
        int index = 0;
        index < _allEvents.length;
        index++
        ) {
          final event =
          _allEvents[index];

          final eventSearchKey =
          _buildVenueSearchKey(
            event,
          );

          if (eventSearchKey ==
              key) {
            _allEvents[index] = {
              ...event,
              'latitude':
              coordinates.latitude,
              'longitude':
              coordinates.longitude,
            };
          }
        }
      }

      // Rebuild visible events after every batch.
      _applyCurrentFilter(
        animateMap: false,
        updateState: false,
      );

      if (mounted) {
        setState(() {});

        if (_events.isNotEmpty) {
          _fitMapToMarkers();
        }
      }
    }

    if (mounted) {
      _applyCurrentFilter(
        animateMap: false,
      );
    }
  }

  String _buildVenueSearchKey(
      Map<String, dynamic> event,
      ) {
    final venue =
        event['venue']
            ?.toString()
            .trim() ??
            '';

    final address =
        event['address']
            ?.toString()
            .trim() ??
            '';

    final city =
        event['city']
            ?.toString()
            .trim() ??
            _currentCity;

    final country =
        event['country']
            ?.toString()
            .trim() ??
            '';

    return [
      venue,
      address,
      city,
      country,
    ].where(
          (value) =>
      value
          .trim()
          .isNotEmpty,
    ).join(', ').toLowerCase().trim();
  }

  Future<LatLng?>
  _mapboxGeocodeVenue({
    required String searchText,
    required double
    proximityLatitude,
    required double
    proximityLongitude,
  }) async {
    final token =
    dotenv.env[
    'MAPBOX_PUBLIC_TOKEN']
        ?.trim();

    if (token == null ||
        token.isEmpty) {
      return null;
    }

    final cacheKey =
    searchText
        .toLowerCase()
        .trim();

    final sessionCached =
    _venueCoordinateCache[
    cacheKey];

    if (sessionCached !=
        null) {
      return sessionCached;
    }

    final existingRequest =
    _venueRequestsInFlight[
    cacheKey];

    if (existingRequest !=
        null) {
      return existingRequest;
    }

    final request =
    _performMapboxVenueSearch(
      searchText:
      searchText,
      token:
      token,
      proximityLatitude:
      proximityLatitude,
      proximityLongitude:
      proximityLongitude,
    );

    _venueRequestsInFlight[
    cacheKey] = request;

    try {
      final result =
      await request;

      if (result !=
          null) {
        _venueCoordinateCache[
        cacheKey] = result;
      }

      return result;
    } finally {
      _venueRequestsInFlight
          .remove(cacheKey);
    }
  }

  Future<LatLng?>
  _performMapboxVenueSearch({
    required String searchText,
    required String token,
    required double
    proximityLatitude,
    required double
    proximityLongitude,
  }) async {
    // -------------------------------------------------------------------------
    // Attempt 1: full venue + address + city
    // -------------------------------------------------------------------------

    final first =
    await _performMapboxSearchRequest(
      query:
      searchText,
      token:
      token,
      proximityLatitude:
      proximityLatitude,
      proximityLongitude:
      proximityLongitude,
    );

    if (first != null) {
      return first;
    }

    // -------------------------------------------------------------------------
    // Attempt 2: venue + city
    // -------------------------------------------------------------------------

    final parts =
    searchText
        .split(',')
        .map(
          (part) =>
          part.trim(),
    )
        .where(
          (part) =>
      part.isNotEmpty,
    )
        .toList();

    if (parts.length >= 2) {
      final fallbackQuery =
      [
        parts.first,
        parts[
        parts.length -
            2],
        parts.last,
      ].join(', ');

      final second =
      await _performMapboxSearchRequest(
        query:
        fallbackQuery,
        token:
        token,
        proximityLatitude:
        proximityLatitude,
        proximityLongitude:
        proximityLongitude,
      );

      if (second != null) {
        return second;
      }
    }

    // -------------------------------------------------------------------------
    // Attempt 3: venue + final location
    // -------------------------------------------------------------------------

    if (parts.isNotEmpty) {
      final finalQuery =
          '${parts.first}, '
          '${_currentCity}';

      final third =
      await _performMapboxSearchRequest(
        query:
        finalQuery,
        token:
        token,
        proximityLatitude:
        proximityLatitude,
        proximityLongitude:
        proximityLongitude,
      );

      if (third != null) {
        return third;
      }
    }

    return null;
  }

  Future<LatLng?>
  _performMapboxSearchRequest({
    required String query,
    required String token,
    required double
    proximityLatitude,
    required double
    proximityLongitude,
  }) async {
    final uri = Uri.https(
      'api.mapbox.com',
      '/search/searchbox/v1/forward',
      {
        'q': query,
        'access_token':
        token,
        'language':
        'en',
        'limit':
        '5',
        'types':
        'poi,address',
        'proximity':
        '$proximityLongitude,$proximityLatitude',
      },
    );

    try {
      final response =
      await http.get(uri);

      if (response.statusCode !=
          200) {
        debugPrint(
          "Mapbox venue error "
              "${response.statusCode}: "
              "${response.body}",
        );
        return null;
      }

      final decoded =
      json.decode(
        response.body,
      );

      final features =
      decoded['features'];

      if (features is! List ||
          features.isEmpty) {
        return null;
      }

      Map<String, dynamic>?
      selectedFeature;

      // Prefer a POI because this is an event venue.
      for (final feature
      in features) {
        if (feature is! Map) {
          continue;
        }

        final properties =
        feature[
        'properties'];

        final featureType =
        properties?[
        'feature_type']
            ?.toString()
            .toLowerCase();

        if (featureType ==
            'poi') {
          selectedFeature =
          Map<String, dynamic>.from(
            feature,
          );
          break;
        }
      }

      selectedFeature ??=
      Map<String, dynamic>.from(
        features.first,
      );

      final geometry =
      selectedFeature[
      'geometry'];

      final coordinates =
      geometry?[
      'coordinates'];

      if (coordinates is! List ||
          coordinates.length <
              2) {
        return null;
      }

      final lon =
      double.tryParse(
        coordinates[0]
            .toString(),
      );

      final lat =
      double.tryParse(
        coordinates[1]
            .toString(),
      );

      if (lat == null ||
          lon == null) {
        return null;
      }

      return LatLng(
        lat,
        lon,
      );
    } catch (e) {
      debugPrint(
        "Mapbox venue lookup failed: $e",
      );
      return null;
    }
  }

  // ===========================================================================
  // PERSISTENT EVENT CACHE
  // ===========================================================================

  String _eventCacheKey(
      String cityName,
      double latitude,
      double longitude,
      ) {
    final normalized =
        '${cityName.toLowerCase().trim()}_'
        '${latitude.toStringAsFixed(3)}_'
        '${longitude.toStringAsFixed(3)}';

    return '$_eventCachePrefix$normalized';
  }

  Future<List<Map<String, dynamic>>?>
  _readEventCache(
      String cacheKey,
      ) async {
    final prefs =
        _preferences ??
            await SharedPreferences
                .getInstance();

    _preferences =
        prefs;

    final raw =
    prefs.getString(
      cacheKey,
    );

    if (raw == null ||
        raw.isEmpty) {
      return null;
    }

    try {
      final decoded =
      json.decode(raw);

      if (decoded is! Map) {
        await prefs.remove(
          cacheKey,
        );
        return null;
      }

      final timestamp =
      int.tryParse(
        decoded['timestamp']
            ?.toString() ??
            '',
      );

      final rawEvents =
      decoded['events'];

      if (timestamp == null ||
          rawEvents is! List) {
        await prefs.remove(
          cacheKey,
        );
        return null;
      }

      final cacheAge =
      DateTime.now()
          .difference(
        DateTime.fromMillisecondsSinceEpoch(
          timestamp,
        ),
      );

      if (cacheAge >
          _eventCacheDuration) {
        await prefs.remove(
          cacheKey,
        );
        return null;
      }

      return rawEvents
          .whereType<Map>()
          .map(
            (event) =>
        Map<String, dynamic>.from(
          event,
        ),
      )
          .toList();
    } catch (e) {
      debugPrint(
        "Event cache read error: $e",
      );

      await prefs.remove(
        cacheKey,
      );

      return null;
    }
  }

  Future<void> _writeEventCache(
      String cacheKey,
      List<Map<String, dynamic>>
      events,
      ) async {
    try {
      final prefs =
          _preferences ??
              await SharedPreferences
                  .getInstance();

      _preferences =
          prefs;

      final cleanEvents =
      events.map(
            (event) {
          final copy =
          Map<String, dynamic>.from(
            event,
          );

          // Never persist session venue geocoding results.
          copy['latitude'] =
          0.0;
          copy['longitude'] =
          0.0;

          return copy;
        },
      ).toList();

      await prefs.setString(
        cacheKey,
        jsonEncode({
          'timestamp':
          DateTime.now()
              .millisecondsSinceEpoch,
          'events':
          cleanEvents,
        }),
      );
    } catch (e) {
      debugPrint(
        "Event cache write error: $e",
      );
    }
  }

  Future<void>
  _deleteEventCache(
      String cacheKey,
      ) async {
    try {
      final prefs =
          _preferences ??
              await SharedPreferences
                  .getInstance();

      _preferences =
          prefs;

      await prefs.remove(
        cacheKey,
      );
    } catch (e) {
      debugPrint(
        "Event cache delete error: $e",
      );
    }
  }

  // ===========================================================================
  // LOCAL FILTERING
  // ===========================================================================

  void _applyCurrentFilter({
    bool animateMap = true,
    bool updateState = true,
  }) {
    final selectedFilter =
    _filters[
    _selectedFilterIndex];

    // Only mapped events are part of the visible result.
    final mappedEvents =
    _allEvents.where(
          (event) =>
      _validCoordinate(
        event['latitude'],
      ) &&
          _validCoordinate(
            event['longitude'],
          ),
    );

    List<Map<String, dynamic>>
    filtered;

    if (selectedFilter ==
        "All") {
      filtered =
          mappedEvents
              .map(
                (event) =>
            Map<String, dynamic>.from(
              event,
            ),
          )
              .toList();
    } else {
      filtered =
          mappedEvents
              .where(
                (event) =>
            event[
            'categoryTag'] ==
                selectedFilter,
          )
              .map(
                (event) =>
            Map<String, dynamic>.from(
              event,
            ),
          )
              .toList();
    }

    if (updateState &&
        mounted) {
      setState(() {
        _events =
            filtered;
      });
    } else {
      _events =
          filtered;
    }

    if (animateMap) {
      Future.delayed(
        const Duration(
          milliseconds: 100,
        ),
            () {
          if (!mounted) return;

          _fitMapToMarkers();

          if (_pageController
              .hasClients &&
              _events.isNotEmpty) {
            _pageController
                .jumpToPage(0);
          }
        },
      );
    }
  }

  void _handleFilterSelection(
      int index,
      ) {
    if (_selectedFilterIndex ==
        index) {
      return;
    }

    // NO NIM.
    // NO Mapbox.
    // NO network operation.
    setState(() {
      _selectedFilterIndex =
          index;
    });

    _applyCurrentFilter(
      animateMap: true,
    );
  }

  // ===========================================================================
  // MESSAGE
  // ===========================================================================

  void _showMessage(
      String message,
      ) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content:
        Text(message),
        behavior:
        SnackBarBehavior
            .floating,
        duration:
        const Duration(
          seconds: 3,
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    final isDark =
        Theme.of(context)
            .brightness ==
            Brightness.dark;

    final cartoKey =
        dotenv.env[
        'CARTO_API_KEY']
            ?.trim() ??
            '';

    final textColor =
    isDark
        ? Colors.white
        : const Color(
      0xFF1E1E1E,
    );

    final textMuted =
    isDark
        ? Colors.white54
        : Colors.black54;

    final accentColor =
    isDark
        ? const Color(
      0xFF00E5FF,
    )
        : const Color(
      0xFF2E3192,
    );

    final accentForeground =
    isDark
        ? Colors.black
        : Colors.white;

    final bottomNavClearance =
        MediaQuery.of(context)
            .padding
            .bottom +
            96.0;

    return Scaffold(
      extendBodyBehindAppBar:
      true,
      body:
      Stack(
        children: [
          // ===================================================================
          // 1. CARTO MAP
          // ===================================================================

          FlutterMap(
            mapController:
            _mapController,
            options:
            MapOptions(
              initialCenter:
              const LatLng(
                20.0,
                0.0,
              ),
              initialZoom:
              2.2,
              interactionOptions:
              const InteractionOptions(
                flags:
                InteractiveFlag
                    .all &
                ~InteractiveFlag
                    .rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                isDark
                    ? 'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png?key=$cartoKey'
                    : 'https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png?key=$cartoKey',
                userAgentPackageName:
                'com.journii.app',
              ),

              MarkerLayer(
                markers:
                _events
                    .where(
                      (event) =>
                  _validCoordinate(
                    event[
                    'latitude'],
                  ) &&
                      _validCoordinate(
                        event[
                        'longitude'],
                      ),
                )
                    .map(
                      (event) {
                    return Marker(
                      key:
                      ValueKey(
                        event[
                        'id'],
                      ),
                      point:
                      LatLng(
                        (event[
                        'latitude']
                        as num)
                            .toDouble(),
                        (event[
                        'longitude']
                        as num)
                            .toDouble(),
                      ),
                      width:
                      140,
                      height:
                      80,
                      child:
                      _buildCustomMarker(
                        event,
                        isDark,
                        accentColor,
                      ),
                    );
                  },
                )
                    .toList(),
              ),

              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    '© OpenStreetMap contributors',
                  ),
                  TextSourceAttribution(
                    '© CARTO',
                  ),
                ],
              ),
            ],
          ),

          // ===================================================================
          // 2. SEARCH
          // ===================================================================

          Positioned(
            top:
            MediaQuery.of(
              context,
            )
                .padding
                .top +
                16,
            left:
            0,
            right:
            0,
            child:
            Column(
              children: [
                Padding(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal:
                    20,
                  ),
                  child:
                  _buildGlassContainer(
                    isDark:
                    isDark,
                    child:
                    Row(
                      children: [
                        Expanded(
                          child:
                          TextField(
                            controller:
                            _searchController,
                            onSubmitted:
                            _handleSearch,
                            textInputAction:
                            TextInputAction
                                .search,
                            style:
                            TextStyle(
                              color:
                              textColor,
                              fontWeight:
                              FontWeight.w600,
                            ),
                            decoration:
                            InputDecoration(
                              hintText:
                              "Where could your next adventure be?",
                              hintStyle:
                              TextStyle(
                                color:
                                textMuted,
                                fontWeight:
                                FontWeight.normal,
                              ),
                              prefixIcon:
                              Icon(
                                Icons.search,
                                color: isDark
                                    ? Colors.white70
                                    : accentColor,
                              ),
                              border:
                              InputBorder.none,
                              contentPadding:
                              const EdgeInsets
                                  .symmetric(
                                vertical:
                                16,
                              ),
                            ),
                          ),
                        ),

                        // Explicit refresh.
                        if (_currentCity !=
                            "Explore the world")
                          IconButton(
                            tooltip:
                            "Refresh events",
                            onPressed:
                            _isLoading
                                ? null
                                : _refreshCurrentDestination,
                            icon:
                            const Icon(
                              Icons.refresh_rounded,
                            ),
                            color:
                            accentColor,
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(
                  height:
                  10,
                ),

                if (_currentCity ==
                    "Explore the world" &&
                    _allEvents
                        .isEmpty)
                  _buildDestinationSuggestions(
                    isDark,
                    textMuted,
                    accentColor,
                  ),

                const SizedBox(
                  height:
                  10,
                ),

                SizedBox(
                  height:
                  44,
                  child:
                  ListView.builder(
                    scrollDirection:
                    Axis.horizontal,
                    physics:
                    const BouncingScrollPhysics(),
                    padding:
                    const EdgeInsets
                        .symmetric(
                      horizontal:
                      20,
                    ),
                    itemCount:
                    _filters.length,
                    itemBuilder:
                        (
                        context,
                        index,
                        ) {
                      final isSelected =
                          _selectedFilterIndex ==
                              index;

                      return Padding(
                        padding:
                        const EdgeInsets
                            .only(
                          right:
                          12,
                        ),
                        child:
                        _buildFilterPill(
                          label:
                          _filters[
                          index],
                          isSelected:
                          isSelected,
                          isDark:
                          isDark,
                          accentColor:
                          accentColor,
                          accentForeground:
                          accentForeground,
                          onTap:
                              () =>
                              _handleFilterSelection(
                                index,
                              ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ===================================================================
          // 3. DESTINATION HEADER
          // ===================================================================

          if (_currentCity !=
              "Explore the world" &&
              !_isLoading)
            Positioned(
              top:
              MediaQuery.of(
                context,
              )
                  .padding
                  .top +
                  146,
              left:
              20,
              right:
              20,
              child:
              IgnorePointer(
                child:
                _buildDiscoveryHeader(
                  isDark,
                  textMuted,
                  accentColor,
                ),
              ),
            ),

          // ===================================================================
          // 4. EVENT CAROUSEL
          // ===================================================================

          Positioned(
            left:
            0,
            right:
            0,
            bottom:
            bottomNavClearance +
                8,
            child:
            (_isLoading &&
                _events.isEmpty)
                ? const SizedBox
                .shrink()
                : _events.isEmpty
                ? _buildNoEventsCard(
              isDark,
              textMuted,
            )
                : SizedBox(
              height:
              140,
              child:
              PageView.builder(
                controller:
                _pageController,
                physics:
                const BouncingScrollPhysics(),
                onPageChanged:
                    (
                    index,
                    ) {
                  if (index <
                      0 ||
                      index >=
                          _events.length) {
                    return;
                  }

                  final event =
                  _events[
                  index];

                  final lat =
                  (event[
                  'latitude']
                  as num)
                      .toDouble();

                  final lon =
                  (event[
                  'longitude']
                  as num)
                      .toDouble();

                  _mapController
                      .move(
                    LatLng(
                      lat,
                      lon,
                    ),
                    13.5,
                  );
                },
                itemCount:
                _events
                    .length,
                itemBuilder:
                    (
                    context,
                    index,
                    ) {
                  return Padding(
                    padding:
                    const EdgeInsets
                        .symmetric(
                      horizontal:
                      6,
                    ),
                    child:
                    _buildCarouselEventTile(
                      _events[
                      index],
                      isDark,
                      accentColor,
                    ),
                  );
                },
              ),
            ),
          ),

          // ===================================================================
          // 5. MAIN LOADING
          // ===================================================================

          if (_isLoading)
            Center(
              child:
              _buildLoadingCard(
                isDark:
                isDark,
                textColor:
                textColor,
                accentColor:
                accentColor,
                message:
                "Discovering events...",
              ),
            )
          else if (_isGeocoding)
            Positioned(
              top:
              MediaQuery.of(
                context,
              )
                  .padding
                  .top +
                  150,
              right:
              20,
              child:
              _buildGeocodingIndicator(
                isDark,
                accentColor,
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DESTINATION SUGGESTIONS
  // ===========================================================================

  Widget
  _buildDestinationSuggestions(
      bool isDark,
      Color textMuted,
      Color accentColor,
      ) {
    return SizedBox(
      height:
      72,
      child:
      ListView.builder(
        scrollDirection:
        Axis.horizontal,
        physics:
        const BouncingScrollPhysics(),
        padding:
        const EdgeInsets
            .symmetric(
          horizontal:
          20,
        ),
        itemCount:
        _destinationSuggestions
            .length,
        itemBuilder:
            (
            context,
            index,
            ) {
          final suggestion =
          _destinationSuggestions[
          index];

          final name =
              suggestion[
              'name'] ??
                  '';

          final subtitle =
              suggestion[
              'subtitle'] ??
                  '';

          return Padding(
            padding:
            const EdgeInsets.only(
              right:
              10,
            ),
            child:
            GestureDetector(
              onTap:
                  () =>
                  _selectSuggestedDestination(
                    name,
                  ),
              child:
              Container(
                width:
                165,
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal:
                  14,
                  vertical:
                  10,
                ),
                decoration:
                BoxDecoration(
                  color: isDark
                      ? Colors.black
                      .withOpacity(
                    0.62,
                  )
                      : Colors.white
                      .withOpacity(
                    0.92,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    20,
                  ),
                  border:
                  Border.all(
                    color: isDark
                        ? Colors
                        .white
                        .withOpacity(
                      0.12,
                    )
                        : Colors.black12,
                  ),
                ),
                child:
                Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  mainAxisAlignment:
                  MainAxisAlignment
                      .center,
                  children: [
                    Text(
                      name,
                      maxLines:
                      1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      TextStyle(
                        color:
                        isDark
                            ? Colors.white
                            : const Color(
                          0xFF1E1E1E,
                        ),
                        fontWeight:
                        FontWeight.w800,
                        fontSize:
                        14,
                      ),
                    ),
                    const SizedBox(
                      height:
                      3,
                    ),
                    Text(
                      subtitle,
                      maxLines:
                      1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      TextStyle(
                        color:
                        textMuted,
                        fontSize:
                        10,
                        fontWeight:
                        FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // DISCOVERY HEADER
  // ===========================================================================

  Widget
  _buildDiscoveryHeader(
      bool isDark,
      Color textMuted,
      Color accentColor,
      ) {
    final selectedFilter =
    _filters[
    _selectedFilterIndex];

    final eventCount =
        _events.length;

    return ClipRRect(
      borderRadius:
      BorderRadius.circular(
        18,
      ),
      child:
      BackdropFilter(
        filter:
        ImageFilter.blur(
          sigmaX:
          12,
          sigmaY:
          12,
        ),
        child:
        Container(
          padding:
          const EdgeInsets
              .symmetric(
            horizontal:
            14,
            vertical:
            10,
          ),
          decoration:
          BoxDecoration(
            color:
            isDark
                ? Colors.black
                .withOpacity(
              0.42,
            )
                : Colors.white
                .withOpacity(
              0.80,
            ),
            borderRadius:
            BorderRadius.circular(
              18,
            ),
            border:
            Border.all(
              color: isDark
                  ? Colors.white
                  .withOpacity(
                0.10,
              )
                  : Colors.black12,
            ),
          ),
          child:
          Row(
            children: [
              Icon(
                Icons
                    .travel_explore_rounded,
                size:
                18,
                color:
                accentColor,
              ),
              const SizedBox(
                width:
                8,
              ),
              Expanded(
                child:
                Text(
                  "$eventCount ${eventCount == 1 ? 'event' : 'events'} in $_currentCity",
                  maxLines:
                  1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  TextStyle(
                    color:
                    isDark
                        ? Colors.white
                        : const Color(
                      0xFF1E1E1E,
                    ),
                    fontSize:
                    12,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(
                width:
                6,
              ),
              Text(
                selectedFilter,
                style:
                TextStyle(
                  color:
                  accentColor,
                  fontSize:
                  10,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // FILTER PILL
  // ===========================================================================

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required bool isDark,
    required Color accentColor,
    required Color accentForeground,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap:
      onTap,
      child:
      AnimatedContainer(
        duration:
        const Duration(
          milliseconds:
          250,
        ),
        curve:
        Curves.easeOutCubic,
        padding:
        const EdgeInsets
            .symmetric(
          horizontal:
          24,
        ),
        alignment:
        Alignment.center,
        decoration:
        BoxDecoration(
          color:
          isSelected
              ? accentColor
              : (isDark
              ? Colors.black
              .withOpacity(
            0.6,
          )
              : Colors.white
              .withOpacity(
            0.9,
          )),
          borderRadius:
          BorderRadius.circular(
            32,
          ),
          border:
          Border.all(
            color:
            isSelected
                ? accentColor
                : (isDark
                ? Colors.white
                .withOpacity(
              0.15,
            )
                : Colors.black12),
            width:
            1.5,
          ),
          boxShadow:
          isSelected
              ? [
            BoxShadow(
              color:
              accentColor
                  .withOpacity(
                0.3,
              ),
              blurRadius:
              12,
              offset:
              const Offset(
                0,
                4,
              ),
            ),
          ]
              : [],
        ),
        child:
        Text(
          label,
          style:
          TextStyle(
            color:
            isSelected
                ? accentForeground
                : (isDark
                ? Colors.white70
                : Colors.black87),
            fontWeight:
            isSelected
                ? FontWeight.bold
                : FontWeight.w600,
            fontSize:
            14,
            letterSpacing:
            0.3,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TRANSLATED EVENT DISPLAY
  // ===========================================================================

  String _eventTranslationKey(
      Map<String, dynamic> event,
      ) {
    final id =
        event['id']?.toString().trim() ?? '';

    if (id.isNotEmpty) {
      return id;
    }

    return [
      event['name']?.toString() ?? '',
      event['venue']?.toString() ?? '',
      event['date']?.toString() ?? '',
    ].join('|');
  }

  String _displayEventName(
      Map<String, dynamic> event,
      ) {
    final original =
        event['name']?.toString().trim() ?? '';

    if (original.isEmpty) {
      return 'Event';
    }

    final translated =
    _translatedEventNames[
    _eventTranslationKey(event)];

    return translated != null &&
        translated.trim().isNotEmpty
        ? translated
        : original;
  }

  String _displayEventVenue(
      Map<String, dynamic> event,
      ) {
    final original =
        event['venue']?.toString().trim() ?? '';

    if (original.isEmpty) {
      return 'Venue';
    }

    final translated =
    _translatedEventVenues[
    _eventTranslationKey(event)];

    return translated != null &&
        translated.trim().isNotEmpty
        ? translated
        : original;
  }

  Future<void> _translateEventsForDisplay(
      List<Map<String, dynamic>> events,
      ) async {
    if (events.isEmpty) {
      return;
    }

    final requestId =
    ++_displayTranslationRequestId;

    // Translate a few events at a time so the UI remains responsive and
    // we do not create a large number of simultaneous ML Kit requests.
    const batchSize = 3;

    for (
    int start = 0;
    start < events.length;
    start += batchSize
    ) {
      if (!mounted ||
          requestId !=
              _displayTranslationRequestId) {
        return;
      }

      final end =
      (start + batchSize < events.length)
          ? start + batchSize
          : events.length;

      final batch =
      events.sublist(start, end);

      final results =
      await Future.wait(
        batch.map(
              (event) async {
            final key =
            _eventTranslationKey(event);

            final originalName =
                event['name']?.toString().trim() ??
                    '';

            final originalVenue =
                event['venue']?.toString().trim() ??
                    '';

            final nameFuture =
            originalName.isEmpty
                ? Future.value('')
                : TranslationService
                .translateToEnglish(
              originalName,
            );

            final venueFuture =
            originalVenue.isEmpty
                ? Future.value('')
                : TranslationService
                .translateToEnglish(
              originalVenue,
            );

            final translated =
            await Future.wait<String>([
              nameFuture,
              venueFuture,
            ]);

            return (
            key: key,
            name: translated[0],
            venue: translated[1],
            );
          },
        ),
      );

      if (!mounted ||
          requestId !=
              _displayTranslationRequestId) {
        return;
      }

      var changed = false;

      for (final result in results) {
        final translatedName =
        result.name.trim();

        final translatedVenue =
        result.venue.trim();

        if (translatedName.isNotEmpty) {
          _translatedEventNames[
          result.key] = translatedName;
          changed = true;
        }

        if (translatedVenue.isNotEmpty) {
          _translatedEventVenues[
          result.key] = translatedVenue;
          changed = true;
        }
      }

      if (changed && mounted) {
        setState(() {});
      }
    }
  }

  // ===========================================================================
  // CUSTOM MARKER
  // ===========================================================================

  Widget _buildCustomMarker(
      Map<String, dynamic> event,
      bool isDark,
      Color accentColor,
      ) {
    return GestureDetector(
      onTap: () {
        final index =
        _events.indexOf(
          event,
        );

        if (index != -1 &&
            _pageController
                .hasClients) {
          _pageController
              .animateToPage(
            index,
            duration:
            const Duration(
              milliseconds:
              350,
            ),
            curve:
            Curves.easeOutCubic,
          );
        }
      },
      child:
      Column(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Stack(
            alignment:
            Alignment.center,
            children: [
              Container(
                width:
                18,
                height:
                18,
                decoration:
                BoxDecoration(
                  color: accentColor
                      .withOpacity(
                    0.2,
                  ),
                  shape:
                  BoxShape.circle,
                ),
              ),
              Icon(
                Icons.location_on,
                color:
                accentColor,
                size:
                38,
              ),
            ],
          ),
          const SizedBox(
            height:
            4,
          ),
          ClipRRect(
            borderRadius:
            BorderRadius.circular(
              12,
            ),
            child:
            BackdropFilter(
              filter:
              ImageFilter.blur(
                sigmaX:
                8,
                sigmaY:
                8,
              ),
              child:
              Container(
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal:
                  10,
                  vertical:
                  6,
                ),
                decoration:
                BoxDecoration(
                  color: isDark
                      ? Colors.black
                      .withOpacity(
                    0.7,
                  )
                      : Colors.white
                      .withOpacity(
                    0.85,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                  border:
                  Border.all(
                    color: isDark
                        ? Colors.white24
                        : Colors.black12,
                  ),
                ),
                child:
                Text(
                  _displayEventName(
                    event,
                  ),
                  maxLines:
                  1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  textAlign:
                  TextAlign.center,
                  style:
                  TextStyle(
                    color: isDark
                        ? Colors.white
                        : Colors.black87,
                    fontSize:
                    11,
                    fontWeight:
                    FontWeight.w800,
                    letterSpacing:
                    -0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LOADING CARD
  // ===========================================================================

  Widget _buildLoadingCard({
    required bool isDark,
    required Color textColor,
    required Color accentColor,
    required String message,
  }) {
    return ClipRRect(
      borderRadius:
      BorderRadius.circular(
        32,
      ),
      child:
      BackdropFilter(
        filter:
        ImageFilter.blur(
          sigmaX:
          10,
          sigmaY:
          10,
        ),
        child:
        Container(
          padding:
          const EdgeInsets
              .symmetric(
            horizontal:
            24,
            vertical:
            16,
          ),
          decoration:
          BoxDecoration(
            color: isDark
                ? Colors.black
                .withOpacity(
              0.7,
            )
                : Colors.white
                .withOpacity(
              0.85,
            ),
            borderRadius:
            BorderRadius.circular(
              32,
            ),
            border:
            Border.all(
              color: isDark
                  ? Colors.white
                  .withOpacity(
                0.12,
              )
                  : Colors.black12,
            ),
          ),
          child:
          Row(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              SizedBox(
                width:
                20,
                height:
                20,
                child:
                CircularProgressIndicator(
                  color:
                  accentColor,
                  strokeWidth:
                  2.5,
                ),
              ),
              const SizedBox(
                width:
                16,
              ),
              Text(
                message,
                style:
                TextStyle(
                  color:
                  textColor,
                  fontWeight:
                  FontWeight.bold,
                  fontSize:
                  15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // GEOCODING INDICATOR
  // ===========================================================================

  Widget
  _buildGeocodingIndicator(
      bool isDark,
      Color accentColor,
      ) {
    return ClipRRect(
      borderRadius:
      BorderRadius.circular(
        20,
      ),
      child:
      BackdropFilter(
        filter:
        ImageFilter.blur(
          sigmaX:
          10,
          sigmaY:
          10,
        ),
        child:
        Container(
          padding:
          const EdgeInsets
              .symmetric(
            horizontal:
            12,
            vertical:
            8,
          ),
          decoration:
          BoxDecoration(
            color: isDark
                ? Colors.black
                .withOpacity(
              0.60,
            )
                : Colors.white
                .withOpacity(
              0.80,
            ),
            borderRadius:
            BorderRadius.circular(
              20,
            ),
            border:
            Border.all(
              color: isDark
                  ? Colors.white
                  .withOpacity(
                0.12,
              )
                  : Colors.black12,
            ),
          ),
          child:
          Row(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              SizedBox(
                width:
                14,
                height:
                14,
                child:
                CircularProgressIndicator(
                  color:
                  accentColor,
                  strokeWidth:
                  1.8,
                ),
              ),
              const SizedBox(
                width:
                8,
              ),
              Text(
                "Placing events...",
                style:
                TextStyle(
                  color:
                  isDark
                      ? Colors.white
                      : Colors.black87,
                  fontSize:
                  11,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // DYNAMIC EVENT GRAPHIC
  // ===========================================================================

  Widget
  _buildDynamicEventGraphic(
      Map<String, dynamic> event,
      ) {
    final String name =
    (event['name'] ?? '')
        .toString()
        .toLowerCase();

    final String category =
    (event['categoryTag'] ??
        '')
        .toString()
        .toLowerCase();

    List<Color>
    gradientColors = [
      const Color(0xFF2E3192),
      const Color(0xFF1BFFFF),
    ];

    IconData categoryIcon =
        Icons.explore_rounded;

    if (category.contains(
      'concert',
    ) ||
        name.contains(
          'concert',
        ) ||
        name.contains(
          'tour',
        ) ||
        name.contains(
          'live',
        ) ||
        name.contains(
          'music',
        )) {
      gradientColors = [
        const Color(0xFF8A2387),
        const Color(0xFFE94057),
      ];

      categoryIcon =
          Icons.music_note_rounded;
    } else if (category.contains(
      'sport',
    ) ||
        name.contains(
          'sport',
        ) ||
        name.contains(
          'match',
        ) ||
        name.contains(
          'cup',
        ) ||
        name.contains(
          'marathon',
        ) ||
        name.contains(
          'championship',
        )) {
      gradientColors = [
        const Color(0xFFFF416C),
        const Color(0xFFFF4B2B),
      ];

      categoryIcon =
          Icons.sports_basketball_rounded;
    } else if (category.contains(
      'festival',
    ) ||
        name.contains(
          'festival',
        ) ||
        name.contains(
          'fest',
        ) ||
        name.contains(
          'party',
        )) {
      gradientColors = [
        const Color(0xFFF2994A),
        const Color(0xFFF2C94C),
      ];

      categoryIcon =
          Icons.celebration_rounded;
    } else if (category.contains(
      'theater',
    ) ||
        name.contains(
          'theater',
        ) ||
        name.contains(
          'theatre',
        ) ||
        name.contains(
          'play',
        ) ||
        name.contains(
          'show',
        ) ||
        name.contains(
          'comedy',
        )) {
      gradientColors = [
        const Color(0xFF11998E),
        const Color(0xFF38EF7D),
      ];

      categoryIcon =
          Icons.theater_comedy_rounded;
    }

    return Container(
      width:
      100,
      height:
      double.infinity,
      decoration:
      BoxDecoration(
        borderRadius:
        BorderRadius.circular(
          24,
        ),
        gradient:
        LinearGradient(
          begin:
          Alignment.topLeft,
          end:
          Alignment.bottomRight,
          colors:
          gradientColors,
        ),
      ),
      child:
      Center(
        child:
        Icon(
          categoryIcon,
          color:
          Colors.white.withOpacity(
            0.85,
          ),
          size:
          42,
        ),
      ),
    );
  }

  // ===========================================================================
  // CAROUSEL EVENT TILE
  // ===========================================================================

  Widget
  _buildCarouselEventTile(
      Map<String, dynamic> event,
      bool isDark,
      Color accentColor,
      ) {
    return GestureDetector(
      onTap:
          () =>
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) =>
                  EventDetailPage(
                    event:
                    event,
                  ),
            ),
          ),
      child:
      Container(
        padding:
        const EdgeInsets.all(
          12,
        ),
        decoration:
        BoxDecoration(
          color: isDark
              ? const Color(
            0xFF1E1E20,
          )
              : Colors.white,
          borderRadius:
          BorderRadius.circular(
            32,
          ),
          border:
          Border.all(
            color: isDark
                ? Colors.white
                .withOpacity(
              0.05,
            )
                : Colors.black
                .withOpacity(
              0.05,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color:
              Colors.black.withOpacity(
                isDark
                    ? 0.4
                    : 0.12,
              ),
              blurRadius:
              20,
              offset:
              const Offset(
                0,
                8,
              ),
            ),
          ],
        ),
        child:
        Row(
          children: [
            _buildDynamicEventGraphic(
              event,
            ),
            const SizedBox(
              width:
              16,
            ),
            Expanded(
              child:
              Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                mainAxisAlignment:
                MainAxisAlignment
                    .center,
                children: [
                  Container(
                    padding:
                    const EdgeInsets
                        .symmetric(
                      horizontal:
                      8,
                      vertical:
                      4,
                    ),
                    decoration:
                    BoxDecoration(
                      color: accentColor
                          .withOpacity(
                        0.1,
                      ),
                      borderRadius:
                      BorderRadius.circular(
                        8,
                      ),
                    ),
                    child:
                    Text(
                      event['date']
                          ?.toString() ??
                          'TBA',
                      style:
                      TextStyle(
                        color:
                        accentColor,
                        fontWeight:
                        FontWeight.bold,
                        fontSize:
                        10,
                        letterSpacing:
                        0.5,
                      ),
                    ),
                  ),
                  const SizedBox(
                    height:
                    8,
                  ),
                  Text(
                    _displayEventName(
                      event,
                    ),
                    maxLines:
                    2,
                    overflow:
                    TextOverflow
                        .ellipsis,
                    style:
                    TextStyle(
                      color: isDark
                          ? Colors.white
                          : const Color(
                        0xFF1E1E1E,
                      ),
                      fontWeight:
                      FontWeight.w800,
                      fontSize:
                      16,
                      height:
                      1.1,
                      letterSpacing:
                      -0.3,
                    ),
                  ),
                  const SizedBox(
                    height:
                    6,
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons
                            .location_on_outlined,
                        size:
                        14,
                        color:
                        Colors.grey
                            .shade500,
                      ),
                      const SizedBox(
                        width:
                        4,
                      ),
                      Expanded(
                        child:
                        Text(
                          _displayEventVenue(
                            event,
                          ),
                          style:
                          TextStyle(
                            color:
                            Colors.grey
                                .shade500,
                            fontSize:
                            12,
                            fontWeight:
                            FontWeight
                                .w500,
                          ),
                          maxLines:
                          1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(
              width:
              8,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // NO EVENTS
  // ===========================================================================

  Widget _buildNoEventsCard(
      bool isDark,
      Color textMuted,
      ) {
    return Padding(
      padding:
      const EdgeInsets
          .symmetric(
        horizontal:
        20,
      ),
      child:
      Container(
        height:
        100,
        decoration:
        BoxDecoration(
          color: isDark
              ? const Color(
            0xFF1E1E20,
          )
              : Colors.white,
          borderRadius:
          BorderRadius.circular(
            32,
          ),
          border:
          Border.all(
            color: isDark
                ? Colors.white
                .withOpacity(
              0.05,
            )
                : Colors.black
                .withOpacity(
              0.05,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color:
              Colors.black.withOpacity(
                isDark
                    ? 0.3
                    : 0.1,
              ),
              blurRadius:
              20,
              offset:
              const Offset(
                0,
                8,
              ),
            ),
          ],
        ),
        child:
        Row(
          mainAxisAlignment:
          MainAxisAlignment
              .center,
          children: [
            Icon(
              Icons
                  .event_busy_outlined,
              size:
              32,
              color:
              textMuted.withOpacity(
                0.5,
              ),
            ),
            const SizedBox(
              width:
              16,
            ),
            Flexible(
              child:
              Text(
                "No upcoming events found\naround $_currentCity",
                textAlign:
                TextAlign.center,
                style:
                TextStyle(
                  color:
                  textMuted,
                  fontSize:
                  14,
                  height:
                  1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // GLASS CONTAINER
  // ===========================================================================

  Widget _buildGlassContainer({
    required Widget child,
    required bool isDark,
  }) {
    return ClipRRect(
      borderRadius:
      BorderRadius.circular(
        32,
      ),
      child:
      BackdropFilter(
        filter:
        ImageFilter.blur(
          sigmaX:
          16,
          sigmaY:
          16,
        ),
        child:
        Container(
          decoration:
          BoxDecoration(
            color: isDark
                ? Colors.black
                .withOpacity(
              0.5,
            )
                : Colors.white
                .withOpacity(
              0.85,
            ),
            borderRadius:
            BorderRadius.circular(
              32,
            ),
            border:
            Border.all(
              color: isDark
                  ? Colors.white
                  .withOpacity(
                0.15,
              )
                  : Colors.black
                  .withOpacity(
                0.05,
              ),
              width:
              1.5,
            ),
            boxShadow: [
              BoxShadow(
                color:
                Colors.black.withOpacity(
                  0.1,
                ),
                blurRadius:
                20,
                offset:
                const Offset(
                  0,
                  10,
                ),
              ),
            ],
          ),
          child:
          child,
        ),
      ),
    );
  }
}