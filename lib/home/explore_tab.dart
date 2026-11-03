import 'dart:ui';
import 'dart:convert';
import 'dart:math';

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

  // Bumped to invalidate cached events classified by the older logic.
  static const String _eventCachePrefix =
      'journii_explore_openagenda_events_longdesc_v3_';

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
  // untouched for OpenAgenda, Mapbox geocoding, caching, and backend use.
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
    // 2. NO VALID CACHE → OPENAGENDA
    // -------------------------------------------------------------------------

    setState(() {
      _isLoading = true;
      _isGeocoding = false;
    });

    final generatedEvents =
    await _fetchEventsFromOpenAgenda(
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
  // OPENAGENDA EVENT DISCOVERY
  // ===========================================================================

  static const Duration _openAgendaRequestTimeout =
  Duration(seconds: 20);

  static const int _openAgendaAgendaFallbackLimit = 8;
  static const int _openAgendaAgendaBatchSize = 4;

  Future<List<Map<String, dynamic>>>
  _fetchEventsFromOpenAgenda({
    required String cityName,
    required double latitude,
    required double longitude,
    String? countryCode,
    String destinationType = '',
  }) async {
    final apiKey = dotenv.env['OPENAGENDA_API_KEY']?.trim() ?? '';

    if (apiKey.isEmpty) {
      debugPrint(
        'OpenAgenda API key is missing. Add OPENAGENDA_API_KEY to .env.',
      );
      return [];
    }

    // Only a public/read key belongs in a Flutter application. Secret keys
    // (oa_sk_...) must remain on a server and must never be bundled in the app.
    if (apiKey.startsWith('oa_sk_')) {
      debugPrint(
        'OpenAgenda secret key detected. Use a public oa_pk_ read key in Flutter.',
      );
      return [];
    }

    try {
      final query = _buildOpenAgendaEventQuery(
        cityName: cityName,
        latitude: latitude,
        longitude: longitude,
        destinationType: destinationType,
      );

      // The cross-agenda endpoint searches published events across public,
      // indexed agendas. OpenAgenda currently documents this v2 route as an
      // experimental feature that may need to be enabled by their support team.
      final crossAgendaUri = Uri.https(
        'api.openagenda.com',
        '/v2/events',
        query,
      );

      debugPrint(
        'OpenAgenda cross-agenda search for $cityName: $crossAgendaUri',
      );

      final crossAgendaResponse = await _requestOpenAgenda(
        crossAgendaUri,
        apiKey,
        requestLabel: 'cross-agenda event search',
      );

      if (crossAgendaResponse != null) {
        if (crossAgendaResponse.statusCode == 200) {
          final rawEvents = _decodeOpenAgendaEvents(
            crossAgendaResponse.body,
          );

          if (rawEvents != null && rawEvents.isNotEmpty) {
            final normalized = _normalizeOpenAgendaEvents(
              rawEvents,
              cityName,
              countryCode,
              destinationType,
            );

            if (normalized.isNotEmpty) {
              debugPrint(
                'OpenAgenda returned ${normalized.length} usable events for $cityName.',
              );
              _logOpenAgendaCategoryDistribution(normalized, cityName);
              return normalized;
            }
          }

          debugPrint(
            'OpenAgenda cross-agenda search returned no usable events for $cityName. Trying agenda discovery fallback.',
          );
        } else {
          debugPrint(
            'OpenAgenda cross-agenda HTTP ${crossAgendaResponse.statusCode}: '
                '${crossAgendaResponse.body}',
          );

          // 401 usually means the key is invalid or lacks read permission.
          // 429 means the caller is rate limited; do not amplify it with more calls.
          if (crossAgendaResponse.statusCode == 401 ||
              crossAgendaResponse.statusCode == 429) {
            return [];
          }
        }
      }

      // Fallback for accounts that do not yet have experimental cross-agenda
      // access: discover relevant public agendas, then read their event lists.
      return await _fetchEventsThroughAgendaDiscovery(
        cityName: cityName,
        latitude: latitude,
        longitude: longitude,
        countryCode: countryCode,
        destinationType: destinationType,
        apiKey: apiKey,
      );
    } catch (e) {
      debugPrint('OpenAgenda event discovery error: $e');
      return [];
    }
  }

  Map<String, dynamic> _buildOpenAgendaEventQuery({
    required String cityName,
    required double latitude,
    required double longitude,
    required String destinationType,
  }) {
    final query = <String, dynamic>{
      'relative[]': const ['current', 'upcoming'],
      'size': '100',
      'detailed': '1',
      'includeLabels': '1',
      'longDescriptionFormat': 'markdown',
      'monolingual': 'en',
      'sort': 'timings.asc',
    };

    if (destinationType == 'country') {
      // The v2 cross-agenda documentation does not list a countryCode filter.
      // Search the country name and validate returned country codes locally.
      query['search'] = cityName.trim();
      return query;
    }

    // OpenAgenda accepts a geographic bounding box for event discovery.
    // Use a tighter box for city/neighborhood searches and a wider box for
    // region-level destinations.
    final normalizedType = destinationType.trim().toLowerCase();
    final radiusKm = normalizedType == 'neighborhood'
        ? 12.0
        : (normalizedType == 'region' || normalizedType == 'district')
        ? 90.0
        : 30.0;

    const kmPerLatitudeDegree = 111.32;
    final latitudeRadians = latitude * (pi / 180.0);
    final longitudeScale = cos(latitudeRadians).abs().clamp(0.15, 1.0);
    final latitudeDelta = radiusKm / kmPerLatitudeDegree;
    final longitudeDelta =
        radiusKm / (kmPerLatitudeDegree * longitudeScale);

    final north = (latitude + latitudeDelta).clamp(-90.0, 90.0);
    final south = (latitude - latitudeDelta).clamp(-90.0, 90.0);
    final east = (longitude + longitudeDelta).clamp(-180.0, 180.0);
    final west = (longitude - longitudeDelta).clamp(-180.0, 180.0);

    query['geo[northEast][lat]'] = north.toStringAsFixed(6);
    query['geo[northEast][lng]'] = east.toStringAsFixed(6);
    query['geo[southWest][lat]'] = south.toStringAsFixed(6);
    query['geo[southWest][lng]'] = west.toStringAsFixed(6);

    return query;
  }

  Future<http.Response?> _requestOpenAgenda(
      Uri uri,
      String apiKey, {
        required String requestLabel,
      }) async {
    try {
      return await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          // OpenAgenda v2 read authentication uses the account key header.
          'key': apiKey,
        },
      ).timeout(_openAgendaRequestTimeout);
    } catch (e) {
      debugPrint('OpenAgenda $requestLabel request failed: $e');
      return null;
    }
  }

  List<Map<String, dynamic>>? _decodeOpenAgendaEvents(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is! Map) {
        debugPrint('OpenAgenda returned an unexpected response shape.');
        return null;
      }

      final rawEvents = decoded['events'];
      if (rawEvents is! List) {
        debugPrint('OpenAgenda response did not contain an events array.');
        return null;
      }

      return rawEvents
          .whereType<Map>()
          .map((event) => Map<String, dynamic>.from(event))
          .toList();
    } catch (e) {
      debugPrint('OpenAgenda JSON parsing error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>>
  _fetchEventsThroughAgendaDiscovery({
    required String cityName,
    required double latitude,
    required double longitude,
    String? countryCode,
    required String destinationType,
    required String apiKey,
  }) async {
    final agendaSearchUri = Uri.https(
      'api.openagenda.com',
      '/v2/agendas',
      <String, dynamic>{
        'search': cityName.trim(),
        'size': '30',
      },
    );

    final agendaResponse = await _requestOpenAgenda(
      agendaSearchUri,
      apiKey,
      requestLabel: 'agenda discovery fallback',
    );

    if (agendaResponse == null || agendaResponse.statusCode != 200) {
      if (agendaResponse != null) {
        debugPrint(
          'OpenAgenda agenda discovery HTTP ${agendaResponse.statusCode}: '
              '${agendaResponse.body}',
        );
      }
      return [];
    }

    List<dynamic> rawAgendas;
    try {
      final decoded = json.decode(agendaResponse.body);
      if (decoded is! Map || decoded['agendas'] is! List) {
        debugPrint('OpenAgenda agenda search returned an unexpected response.');
        return [];
      }
      rawAgendas = decoded['agendas'] as List<dynamic>;
    } catch (e) {
      debugPrint('OpenAgenda agenda search JSON parsing error: $e');
      return [];
    }

    final agendaUids = <int>[];
    for (final rawAgenda in rawAgendas) {
      if (rawAgenda is! Map) continue;
      final uid = int.tryParse(rawAgenda['uid']?.toString() ?? '');
      if (uid != null && !agendaUids.contains(uid)) {
        agendaUids.add(uid);
      }
      if (agendaUids.length >= _openAgendaAgendaFallbackLimit) break;
    }

    if (agendaUids.isEmpty) {
      debugPrint('OpenAgenda did not find public agendas for $cityName.');
      return [];
    }

    debugPrint(
      'OpenAgenda fallback will inspect ${agendaUids.length} relevant agendas for $cityName.',
    );

    final allRawEvents = <Map<String, dynamic>>[];
    final eventQuery = _buildOpenAgendaEventQuery(
      cityName: cityName,
      latitude: latitude,
      longitude: longitude,
      destinationType: destinationType,
    );

    // The agenda search has already narrowed the candidate agendas by country.
    // Do not also apply a full-text country search to every event in each agenda;
    // validate the event's location.countryCode after retrieval instead.
    if (destinationType.trim().toLowerCase() == 'country') {
      eventQuery.remove('search');
    }

    for (int start = 0;
    start < agendaUids.length;
    start += _openAgendaAgendaBatchSize) {
      final end = (start + _openAgendaAgendaBatchSize < agendaUids.length)
          ? start + _openAgendaAgendaBatchSize
          : agendaUids.length;
      final batch = agendaUids.sublist(start, end);

      final batchResults = await Future.wait(
        batch.map((agendaUid) async {
          final uri = Uri.https(
            'api.openagenda.com',
            '/v2/agendas/$agendaUid/events',
            eventQuery,
          );

          final response = await _requestOpenAgenda(
            uri,
            apiKey,
            requestLabel: 'agenda $agendaUid event retrieval',
          );

          if (response == null || response.statusCode != 200) {
            if (response != null) {
              debugPrint(
                'OpenAgenda agenda $agendaUid returned HTTP '
                    '${response.statusCode}: ${response.body}',
              );
            }
            return <Map<String, dynamic>>[];
          }

          final agendaEvents = _decodeOpenAgendaEvents(response.body) ??
              <Map<String, dynamic>>[];

          // Preserve the agenda context used for this request. OpenAgenda's
          // event-detail route requires both agendaUID and eventUID.
          return agendaEvents
              .map((event) => <String, dynamic>{
            ...event,
            'agendaUID': agendaUid,
          })
              .toList();
        }),
      );

      for (final events in batchResults) {
        allRawEvents.addAll(events);
      }
    }

    final normalized = _normalizeOpenAgendaEvents(
      allRawEvents,
      cityName,
      countryCode,
      destinationType,
    );

    debugPrint(
      'OpenAgenda agenda-discovery fallback returned ${normalized.length} usable events for $cityName.',
    );
    _logOpenAgendaCategoryDistribution(normalized, cityName);

    return normalized;
  }

  List<Map<String, dynamic>> _normalizeOpenAgendaEvents(
      List<Map<String, dynamic>> rawEvents,
      String cityName,
      String? countryCode,
      String destinationType,
      ) {
    final normalized = <Map<String, dynamic>>[];
    final seenKeys = <String>{};
    final expectedCountryCode = countryCode?.trim().toUpperCase();
    final isCountry = destinationType.trim().toLowerCase() == 'country';

    for (int index = 0; index < rawEvents.length; index++) {
      final event = _normalizeOpenAgendaEvent(
        rawEvents[index],
        cityName,
        index,
      );

      if (event == null) continue;

      final eventCountryCode =
          event['countryCode']?.toString().trim().toUpperCase() ?? '';
      if (isCountry &&
          expectedCountryCode != null &&
          expectedCountryCode.isNotEmpty &&
          eventCountryCode.isNotEmpty &&
          eventCountryCode != expectedCountryCode) {
        continue;
      }

      final id = event['id']?.toString().trim() ?? '';
      final key = id.isNotEmpty
          ? id
          : '${event['name']?.toString().toLowerCase().trim()}|'
          '${event['venue']?.toString().toLowerCase().trim()}|'
          '${event['date']?.toString().trim()}';

      if (!seenKeys.add(key)) continue;

      normalized.add(event);

      // Preserve the same practical event-card count used by the previous
      // provider while still allowing duplicates to be removed first.
      if (normalized.length >= 15) break;
    }

    return normalized;
  }

  Map<String, dynamic>? _normalizeOpenAgendaEvent(
      Map<String, dynamic> raw,
      String cityName,
      int index,
      ) {
    final name = _openAgendaText(raw['title']);
    if (name.isEmpty) return null;

    final rawLocation = raw['location'];
    final location = rawLocation is Map
        ? Map<String, dynamic>.from(rawLocation)
        : <String, dynamic>{};

    final venueName = _openAgendaText(location['name']);
    final address = _openAgendaText(location['address']);
    final venue = venueName.isNotEmpty ? venueName : address;

    // Explore's current map/cards are venue-based. Keep the same rule as the
    // previous integration and omit events without a mappable physical venue.
    if (venue.isEmpty) return null;

    final eventCity = _openAgendaText(
      location['city'] ?? location['adminLevel4'],
    );
    final countryCode = _openAgendaText(location['countryCode']);
    final country = _openAgendaText(location['country']).isNotEmpty
        ? _openAgendaText(location['country'])
        : countryCode;
    final state = _openAgendaText(
      location['region'] ?? location['adminLevel1'],
    );

    // Keep `description` as the short listing summary for existing consumers.
    // Carry `longDescription` separately for the event detail page.
    final shortDescription = _openAgendaText(raw['description']);
    final longDescription = _openAgendaText(raw['longDescription']);
    final finalDescription = shortDescription.isNotEmpty
        ? shortDescription
        : longDescription.isNotEmpty
        ? longDescription
        : 'Upcoming event in ${eventCity.isNotEmpty ? eventCity : cityName}.';

    final agendaUID = _openAgendaAgendaUid(raw);

    // OpenAgenda v2 often exposes categories as agenda-specific additional
    // fields instead of one universal `category` property.
    final categoryMetadata = _collectOpenAgendaCategoryMetadata(raw);

    final category = _normalizeOpenAgendaCategory(
      name: name,
      description: finalDescription,
      metadata: categoryMetadata,
    );

    final categoryMetadataPreview = categoryMetadata.length > 160
        ? '${categoryMetadata.substring(0, 160)}…'
        : categoryMetadata;
    debugPrint(
      '🏷️ OpenAgenda category: "$name" → $category '
          '| metadata: ${categoryMetadataPreview.isEmpty ? 'none' : categoryMetadataPreview}',
    );

    final startValue = _openAgendaEventStart(raw);
    final normalizedDate = _normalizeDate(startValue);

    final rawUid = _openAgendaText(raw['uid']);
    final slug = _openAgendaText(raw['slug']);
    final eventId = rawUid.isNotEmpty
        ? rawUid
        : slug.isNotEmpty
        ? slug
        : _stableEventId(
      '${name.toLowerCase()}|'
          '${venue.toLowerCase()}|'
          '${eventCity.toLowerCase()}|'
          '${normalizedDate ?? index}',
    );

    final ticketUrl = _extractOpenAgendaRegistrationUrl(raw);
    final imageUrl = _extractOpenAgendaImageUrl(raw['image']);
    final effectiveCity = eventCity.isNotEmpty ? eventCity : cityName;

    return {
      'id': eventId,
      'openAgendaEventUID': rawUid,
      'agendaUID': agendaUID,
      'name': name,
      'description': finalDescription,
      'shortDescription': shortDescription,
      'longDescription': longDescription,
      'date': normalizedDate ?? 'TBA',
      'imageUrl': imageUrl ??
          'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&w=500&q=60',
      'venue': venue,
      'address': address,
      'city': effectiveCity,
      'country': country,
      'countryCode': countryCode,
      'state': state,
      // Keep the existing Mapbox venue-geocoding mechanism in place.
      'latitude': 0.0,
      'longitude': 0.0,
      'ticketUrl': ticketUrl.isNotEmpty
          ? ticketUrl
          : 'https://www.google.com/search?q='
          '${Uri.encodeComponent('$name $effectiveCity tickets')}',
      'categoryTag': category,
      'source': 'OpenAgenda',
      'rights': _openAgendaText(raw['rights']),
    };
  }

  String _openAgendaAgendaUid(Map<String, dynamic> raw) {
    final directUid = _openAgendaText(
      raw['agendaUID'] ?? raw['agendaUid'] ?? raw['agenda_uid'],
    );
    if (directUid.isNotEmpty) return directUid;

    // Cross-agenda results can describe the agenda that originated or supplied
    // the event. The fallback path sets agendaUID explicitly above.
    for (final key in const ['sourceAgenda', 'originAgenda', 'agenda']) {
      final candidate = raw[key];
      if (candidate is Map) {
        final uid = _openAgendaText(candidate['uid']);
        if (uid.isNotEmpty) return uid;
      }
    }

    return '';
  }

  String _openAgendaText(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString();

    if (value is List) {
      return value
          .map(_openAgendaText)
          .where((item) => item.isNotEmpty)
          .join(', ');
    }

    if (value is Map) {
      const preferredKeys = [
        'en',
        'en-GB',
        'en-US',
        'label',
        'name',
        'value',
        'fr',
      ];

      for (final key in preferredKeys) {
        if (value.containsKey(key)) {
          final candidate = _openAgendaText(value[key]);
          if (candidate.isNotEmpty) return candidate;
        }
      }

      for (final entry in value.entries) {
        final candidate = _openAgendaText(entry.value);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    return '';
  }

  String _openAgendaEventStart(Map<String, dynamic> raw) {
    final timings = raw['timings'];
    if (timings is List) {
      for (final timing in timings) {
        if (timing is! Map) continue;
        final begin = _openAgendaText(
          timing['begin'] ?? timing['start'],
        );
        if (begin.isNotEmpty) return begin;
      }
    }

    return _openAgendaText(
      raw['begin'] ?? raw['startDate'] ?? raw['date'],
    );
  }

  String _extractOpenAgendaRegistrationUrl(Map<String, dynamic> raw) {
    final onlineAccessLink = _openAgendaText(raw['onlineAccessLink']);
    if (onlineAccessLink.startsWith('http')) return onlineAccessLink;

    final registration = raw['registration'];
    if (registration is List) {
      for (final item in registration) {
        if (item is Map) {
          final type = _openAgendaText(item['type']).toLowerCase();
          final value = _openAgendaText(item['value']);
          if ((type.isEmpty || type == 'link') &&
              value.startsWith('http')) {
            return value;
          }
        } else {
          final value = _openAgendaText(item);
          if (value.startsWith('http')) return value;
        }
      }
    }

    // Newer OpenAgenda event payloads may include structured ticket offers.
    final offers = raw['offers'];
    if (offers is List) {
      for (final offer in offers) {
        if (offer is! Map) continue;
        final source = offer['source'];
        if (source is Map) {
          final url = _openAgendaText(source['url']);
          if (url.startsWith('http')) return url;
        }
      }
    }

    final directUrl = _openAgendaText(
      raw['url'] ?? raw['eventUrl'],
    );
    if (directUrl.startsWith('http')) return directUrl;

    return '';
  }

  String? _extractOpenAgendaImageUrl(dynamic rawImage) {
    if (rawImage is String) {
      final direct = rawImage.trim();
      return direct.startsWith('http') ? direct : null;
    }

    if (rawImage is! Map) return null;

    final base = _openAgendaText(rawImage['base']);
    final variants = rawImage['variants'];
    String filename = '';

    if (variants is List) {
      // Prefer the smaller thumbnail for the Explore cards.
      for (final variant in variants) {
        if (variant is Map &&
            _openAgendaText(variant['type']).toLowerCase() == 'thumbnail') {
          filename = _openAgendaText(variant['filename']);
          break;
        }
      }

      if (filename.isEmpty) {
        for (final variant in variants) {
          if (variant is Map &&
              _openAgendaText(variant['type']).toLowerCase() == 'base') {
            filename = _openAgendaText(variant['filename']);
            break;
          }
        }
      }
    }

    if (filename.isEmpty) {
      filename = _openAgendaText(rawImage['filename']);
    }
    if (filename.isEmpty) return null;
    if (filename.startsWith('http')) return filename;
    if (base.isEmpty) return null;

    final normalizedBase = base.endsWith('/') ? base : '$base/';
    return '$normalizedBase$filename';
  }

  String _collectOpenAgendaCategoryMetadata(Map<String, dynamic> raw) {
    final parts = <String>[];

    const exactFieldNames = <String>{
      'keyword', 'keywords',
      'category', 'categories', 'eventcategory', 'eventcategories',
      'type', 'types', 'eventtype', 'eventtypes',
      'genre', 'genres', 'eventgenre',
      'theme', 'themes', 'thematic', 'thematics', 'thematique', 'thematiques',
      'subject', 'subjects', 'discipline', 'disciplines',
      'tag', 'tags', 'taggroup', 'taggroups',
      'activity', 'activities', 'activite', 'activites',
      'typology', 'typologies', 'rubric', 'rubrique',
      'format', 'formats', 'classification', 'classifications',
      'domain', 'domains', 'univers', 'famille', 'nature',
    };

    for (final entry in raw.entries) {
      final normalizedKey = _normalizeOpenAgendaCategoryText(entry.key)
          .replaceAll(RegExp(r'[^a-z0-9]'), '');

      final isKnownField = exactFieldNames.contains(normalizedKey);
      final isCategoryLikeField =
          normalizedKey.contains('categor') ||
              normalizedKey.contains('themat') ||
              normalizedKey.contains('genre') ||
              normalizedKey.contains('keyword') ||
              normalizedKey.contains('tag') ||
              normalizedKey.contains('subject') ||
              normalizedKey.contains('disciplin') ||
              normalizedKey.contains('spectacle') ||
              normalizedKey.contains('rubriq') ||
              normalizedKey.contains('music') ||
              normalizedKey.contains('musique') ||
              normalizedKey.contains('sport') ||
              normalizedKey.contains('festival') ||
              normalizedKey.contains('theatre') ||
              normalizedKey.contains('theater') ||
              normalizedKey.contains('culture') ||
              normalizedKey.contains('activit') ||
              normalizedKey.contains('eventtype') ||
              normalizedKey.contains('eventkind') ||
              normalizedKey.contains('classification') ||
              normalizedKey.contains('domain') ||
              normalizedKey.contains('nature') ||
              normalizedKey.contains('type');

      if (!isKnownField && !isCategoryLikeField) continue;

      final valueText = _flattenOpenAgendaClassificationValue(entry.value);
      if (valueText.isNotEmpty) parts.add(valueText);

      // A field named `genre` may contain a specific music genre (e.g. Rock,
      // Jazz or Classical) rather than the literal word "Music".
      if (normalizedKey.contains('genre') &&
          RegExp(
            r'\b(rock|pop|classical|jazz|hip hop|rap|electronic|metal|blues|folk|indie|reggae|soul|funk|house|techno|punk|disco|country|k pop|afrobeats|drum and bass)\b',
            caseSensitive: false,
          ).hasMatch(_normalizeOpenAgendaCategoryText(valueText))) {
        parts.add('musicgenre');
      }

      // Some publishers encode the category directly in a custom field name.
      // Include only field names that themselves contain a meaningful category.
      if (normalizedKey.contains('music') ||
          normalizedKey.contains('musique') ||
          normalizedKey.contains('sport') ||
          normalizedKey.contains('festival') ||
          normalizedKey.contains('theatre') ||
          normalizedKey.contains('theater') ||
          normalizedKey.contains('concert')) {
        parts.add(entry.key);
      }
    }

    return parts.join(' ');
  }

  String _flattenOpenAgendaClassificationValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return '';

    if (value is List) {
      return value
          .map(_flattenOpenAgendaClassificationValue)
          .where((part) => part.isNotEmpty)
          .join(' ');
    }

    if (value is Map) {
      const ignoredKeys = <String>{
        'id', 'uid', 'code', 'slug', 'order', 'position',
      };

      return value.entries
          .where((entry) =>
      !ignoredKeys.contains(entry.key.toString().toLowerCase()))
          .map((entry) => _flattenOpenAgendaClassificationValue(entry.value))
          .where((part) => part.isNotEmpty)
          .join(' ');
    }

    return '';
  }

  String _normalizeOpenAgendaCategoryText(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('å', 'a')
        .replaceAll('ç', 'c')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ñ', 'n')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ý', 'y')
        .replaceAll('ÿ', 'y')
        .replaceAll('œ', 'oe')
        .replaceAll('ß', 'ss')
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizeOpenAgendaCategory({
    required String name,
    required String description,
    required String metadata,
  }) {
    final titleText = _normalizeOpenAgendaCategoryText(name);
    final descriptionText = _normalizeOpenAgendaCategoryText(description);
    final metadataText = _normalizeOpenAgendaCategoryText(metadata);

    const festivalPatterns = <String>[
      r'\b(festival|festivals|carnival|carnivals|carnaval|carnavals|fete|fetes|fiesta|fiestas|celebration|celebrations|foire|foires|fair|fairs)\b',
    ];

    // A festival remains a festival even when it is music- or sports-themed.
    // Only title and explicit metadata are decisive here; a casual mention in
    // the description should not override a more specific event category.
    if (_matchesOpenAgendaCategoryPatterns(titleText, festivalPatterns) ||
        _matchesOpenAgendaCategoryPatterns(metadataText, festivalPatterns)) {
      return 'Festivals 🎪';
    }

    const sportsPatterns = <String>[
      r'\b(sport|sports|football|soccer|rugby|basketball|tennis|baseball|cricket|volleyball|badminton|hockey|athletics|marathon|motorsport|motor racing|esports|e[- ]sports|championship|tournament|grand prix|formula 1|formula one|f1|boxing|golf|cycling|swimming|surfing|sailing|triathlon|wrestling|gymnastics|handball|rowing|canoe|kayak|skiing|snowboarding|skateboarding|equestrian|horse racing|ice hockey|table tennis|ping pong|martial arts|matchday)\b',
      r'\b(race|racing|league match|match day|competition)\b',
    ];

    const concertPatterns = <String>[
      r'\b(concert|concerts|gig|gigs|recital|recitals|orchestra|orchestral|symphony|symphonies|jazz|dj set|dj night|live music|music concert|music event|music night|music evening|music show|music showcase|music performance|band performance|live band|choir|choral|classical music|rock music|pop music|hip hop concert|rap concert|tournee)\b',
    ];

    const theaterPatterns = <String>[
      r'\b(theatre|theater|theatrical|opera|operetta|broadway|west end|stand up|standup|comedy|comedian|improv|improvisation|ballet|performing arts|stage play|theatre play|theater play|dramatic arts|dance performance|musical|circus|cabaret|teatro|spectacle vivant)\b',
    ];

    final scores = <String, double>{
      'Sports ⚽': 0.0,
      'Concerts 🎸': 0.0,
      'Theater 🎭': 0.0,
    };

    void addScore(
        String category,
        String text,
        double weight,
        List<String> patterns,
        ) {
      if (text.isEmpty) return;
      final matches = _countOpenAgendaCategoryPatternMatches(text, patterns);
      if (matches == 0) return;
      scores[category] =
          (scores[category] ?? 0) + (weight * (matches > 2 ? 2 : matches));
    }

    // Explicit agenda labels are strong evidence. The event title is also a
    // strong signal, while descriptions are deliberately weaker because they
    // may mention other kinds of events in passing.
    addScore('Sports ⚽', metadataText, 7.0, sportsPatterns);
    addScore('Sports ⚽', titleText, 6.5, sportsPatterns);
    addScore('Sports ⚽', descriptionText, 1.4, sportsPatterns);

    addScore('Concerts 🎸', metadataText, 7.0, concertPatterns);
    addScore('Concerts 🎸', titleText, 6.5, concertPatterns);
    addScore('Concerts 🎸', descriptionText, 1.4, concertPatterns);

    addScore('Theater 🎭', metadataText, 7.0, theaterPatterns);
    addScore('Theater 🎭', titleText, 6.5, theaterPatterns);
    addScore('Theater 🎭', descriptionText, 1.4, theaterPatterns);

    // OpenAgenda publishers commonly use a plain "Music/Musique" choice in a
    // genre/category field rather than writing "concert" in the title.
    if (RegExp(r'\b(music|musique|musica|musik|musicgenre)\b')
        .hasMatch(metadataText)) {
      scores['Concerts 🎸'] = (scores['Concerts 🎸'] ?? 0) + 7.0;
    }

    // Dance, ballet and similar performing-arts categories are normally
    // supplied as concise agenda labels rather than phrases in the event title.
    if (RegExp(r'\b(dance|danse|danza)\b').hasMatch(metadataText)) {
      scores['Theater 🎭'] = (scores['Theater 🎭'] ?? 0) + 7.0;
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // A description-only passing reference should not classify an event.
    if (ranked.isEmpty || ranked.first.value < 3.5) return 'All';
    return ranked.first.key;
  }

  bool _matchesOpenAgendaCategoryPatterns(
      String text,
      List<String> patterns,
      ) {
    return patterns.any(
          (pattern) => RegExp(pattern, caseSensitive: false).hasMatch(text),
    );
  }

  int _countOpenAgendaCategoryPatternMatches(
      String text,
      List<String> patterns,
      ) {
    var count = 0;
    for (final pattern in patterns) {
      count += RegExp(pattern, caseSensitive: false).allMatches(text).length;
    }
    return count;
  }

  void _logOpenAgendaCategoryDistribution(
      List<Map<String, dynamic>> events,
      String cityName,
      ) {
    final counts = <String, int>{
      'Concerts 🎸': 0,
      'Sports ⚽': 0,
      'Festivals 🎪': 0,
      'Theater 🎭': 0,
      'All': 0,
    };

    for (final event in events) {
      final category = event['categoryTag']?.toString() ?? 'All';
      counts[category] = (counts[category] ?? 0) + 1;
    }

    debugPrint(
      '📊 OpenAgenda category breakdown for $cityName: '
          'Concerts ${counts['Concerts 🎸']}, '
          'Sports ${counts['Sports ⚽']}, '
          'Festivals ${counts['Festivals 🎪']}, '
          'Theater ${counts['Theater 🎭']}, '
          'All ${counts['All']}.',
    );
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