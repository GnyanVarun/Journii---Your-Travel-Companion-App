import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PoiBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  PoiBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
}

class OsmPoiService {
  static final List<String> _servers = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
    'https://z.overpass-api.de/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  static const String _photonUrl = 'https://photon.komoot.io/api/';
  static const String _nominatimUrl =
      'https://nominatim.openstreetmap.org/search';

  static int _serverIndex = 0;

  static const int _maxServerAttempts = 2;
  static const Duration _requestTimeout = Duration(seconds: 6);

  /// Fetches POIs within a bounding box using rotated Overpass servers,
  /// with a fast Photon spatial fallback if Overpass is unreachable.
  static Future<List<PoiModel>> fetchPOIs(PoiBounds bounds) async {
    final s = bounds.south;
    final w = bounds.west;
    final n = bounds.north;
    final e = bounds.east;

    final query = '''
[out:json][timeout:6];
(
  nw["amenity"~"^(restaurant|cafe|fast_food|bar|pub|place_of_worship)\$"]($s,$w,$n,$e);
  nw["tourism"~"^(hotel|hostel|motel|museum|viewpoint|attraction)\$"]($s,$w,$n,$e);
  nw["leisure"~"^(park|garden)\$"]($s,$w,$n,$e);
  nw["historic"~"^(monument|memorial|castle)\$"]($s,$w,$n,$e);
);
out center tags qt 50;
''';

    final attempts = _servers.length < _maxServerAttempts
        ? _servers.length
        : _maxServerAttempts;
    final selectedServers = List<String>.generate(
      attempts,
          (index) => _servers[(_serverIndex + index) % _servers.length],
    );
    _serverIndex = (_serverIndex + attempts) % _servers.length;

    for (int attempt = 0; attempt < selectedServers.length; attempt++) {
      final serverUrl = selectedServers[attempt];

      try {
        print(
          '🌍 OSM POI request ${attempt + 1}/${selectedServers.length}: $serverUrl',
        );

        final response = await http
            .post(
          Uri.parse(serverUrl),
          headers: const {
            'User-Agent': 'JourniiTravelApp/1.0',
            'Accept': 'application/json',
          },
          body: {'data': query},
        )
            .timeout(_requestTimeout);

        if (response.statusCode != 200) {
          print(
            '⚠️ OSM HTTP ${response.statusCode} from $serverUrl',
          );
        } else {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            final remark = decoded['remark']?.toString().trim();
            if (remark != null && remark.isNotEmpty) {
              print('⚠️ Overpass runtime warning from $serverUrl: $remark');
            } else if (decoded['elements'] is List) {
              final elements = decoded['elements'] as List;
              if (elements.isEmpty) {
                break;
              }

              final pois = <PoiModel>[];
              final seenIds = <String>{};

              for (final element in elements) {
                if (element is! Map) continue;
                try {
                  final poi = PoiModel.fromJson(
                    Map<String, dynamic>.from(element),
                  );
                  final elementKey =
                      '${element['type'] ?? 'element'}/${element['id'] ?? ''}';
                  if (poi.name != 'Unknown Place' && seenIds.add(elementKey)) {
                    pois.add(poi);
                  }
                } catch (_) {}
              }

              if (pois.isNotEmpty) {
                print(
                  '✅ Overpass returned ${pois.length} usable POIs from $serverUrl.',
                );
                return pois;
              }
            }
          }
        }
      } catch (err) {
        print('⚠️ POI Fetch Error from $serverUrl: $err');
      }

      if (attempt < selectedServers.length - 1) {
        print('🔄 OSM endpoint failed. Trying a different Overpass server...');
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }

    print('✨ Falling back to Photon spatial POI search...');
    return await _fetchPhotonHiddenGems(bounds);
  }

  // --------------------------------------------------
  // 💎 HIDDEN GEMS: focused, cached Overpass + Photon lookup
  // --------------------------------------------------

  static final Map<String, _PoiCacheEntry> _hiddenGemCache = {};
  static int _hiddenGemConsecutiveFailures = 0;
  static DateTime? _hiddenGemCooldownUntil;

  static const Duration _hiddenGemSuccessCacheTtl = Duration(minutes: 5);
  static const Duration _hiddenGemEmptyCacheTtl = Duration(minutes: 1);
  static const Duration _hiddenGemBaseBackoff = Duration(seconds: 1);
  static const Duration _hiddenGemMaxBackoff = Duration(seconds: 4);
  static const Duration _hiddenGemMaxCooldown = Duration(seconds: 30);

  static Future<List<PoiModel>> fetchHiddenGemPOIs(PoiBounds bounds) async {
    final cacheKey = _hiddenGemCacheKey(bounds);
    final now = DateTime.now();
    final cached = _hiddenGemCache[cacheKey];

    if (cached != null) {
      if (now.isBefore(cached.expiresAt) && cached.places.isNotEmpty) {
        print('💾 Using cached Hidden Gems POIs for this area.');
        return List<PoiModel>.unmodifiable(cached.places);
      }
      _hiddenGemCache.remove(cacheKey);
    }

    final s = bounds.south;
    final w = bounds.west;
    final n = bounds.north;
    final e = bounds.east;

    // Fast node + way query sorted by quadtile (qt) so Overpass responds quickly
    // without resolving heavy relation boundaries.
    final query = '''
[out:json][timeout:5];
(
  nw["historic"="monument"]["name"]($s,$w,$n,$e);
  nw["historic"="memorial"]["name"]($s,$w,$n,$e);
  nw["leisure"="park"]["name"]($s,$w,$n,$e);
  nw["leisure"="garden"]["name"]($s,$w,$n,$e);
  nw["tourism"="museum"]["name"]($s,$w,$n,$e);
  nw["tourism"="viewpoint"]["name"]($s,$w,$n,$e);
  nw["tourism"="attraction"]["name"]($s,$w,$n,$e);
  nw["tourism"="gallery"]["name"]($s,$w,$n,$e);
);
out center tags qt 50;
''';

    List<PoiModel>? places;

    final cooldownUntil = _hiddenGemCooldownUntil;
    if (cooldownUntil == null || now.isAfter(cooldownUntil)) {
      places = await _requestHiddenGemPOIs(query);
    } else {
      print(
        '⚡ Overpass in temporary cooldown; using fast Photon/Nominatim gem lookup.',
      );
    }

    // If Overpass timed out or returned 0 items in the tight box, fall back to
    // Photon + Nominatim spatial lookup around the user's coordinates.
    if (places == null || places.isEmpty) {
      if (places == null) {
        _hiddenGemConsecutiveFailures++;
        final exponent = (_hiddenGemConsecutiveFailures - 1).clamp(0, 3).toInt();
        final cooldownSeconds = math.min(
          _hiddenGemMaxCooldown.inSeconds,
          15 * (1 << exponent),
        ).toInt();
        _hiddenGemCooldownUntil = DateTime.now().add(
          Duration(seconds: cooldownSeconds),
        );
      }

      final fallbackGems = await _fetchPhotonHiddenGems(bounds);
      if (fallbackGems.isNotEmpty) {
        places = fallbackGems;
      }
    } else {
      _hiddenGemConsecutiveFailures = 0;
      _hiddenGemCooldownUntil = null;
    }

    if (places == null || places.isEmpty) {
      return [];
    }

    final ttl = places.isEmpty
        ? _hiddenGemEmptyCacheTtl
        : _hiddenGemSuccessCacheTtl;
    _hiddenGemCache[cacheKey] = _PoiCacheEntry(
      places: List<PoiModel>.unmodifiable(places),
      expiresAt: DateTime.now().add(ttl),
    );

    _hiddenGemCache.removeWhere(
          (_, entry) => DateTime.now().isAfter(entry.expiresAt),
    );
    if (_hiddenGemCache.length > 100) {
      _hiddenGemCache.remove(_hiddenGemCache.keys.first);
    }

    return places;
  }

  /// Fast, reliable spatial fallback using Photon + Nominatim when public
  /// Overpass servers time out or throttle requests.
  static Future<List<PoiModel>> _fetchPhotonHiddenGems(PoiBounds bounds) async {
    final centerLat = (bounds.south + bounds.north) / 2;
    final centerLng = (bounds.west + bounds.east) / 2;
    final center = LatLng(centerLat, centerLng);
    const distanceCalc = Distance();

    final List<PoiModel> discovered = [];
    final Set<String> seenNames = {};

    const gemQueries = [
      {'q': 'park', 'defaultCat': 'park'},
      {'q': 'museum', 'defaultCat': 'museum'},
      {'q': 'viewpoint', 'defaultCat': 'viewpoint'},
      {'q': 'monument', 'defaultCat': 'monument'},
      {'q': 'garden', 'defaultCat': 'park'},
    ];

    try {
      final responses = await Future.wait(
        gemQueries.map((spec) async {
          try {
            final uri = Uri.parse(_photonUrl).replace(
              queryParameters: {
                'q': spec['q']!,
                'lat': centerLat.toStringAsFixed(5),
                'lon': centerLng.toStringAsFixed(5),
                'limit': '12',
                'lang': 'en',
              },
            );
            final resp = await http
                .get(
              uri,
              headers: const {
                'User-Agent': 'JourniiTravelApp/1.0',
                'Accept': 'application/json',
              },
            )
                .timeout(const Duration(seconds: 6));
            if (resp.statusCode == 200) {
              return {
                'body': resp.body,
                'defaultCat': spec['defaultCat']!,
              };
            }
          } catch (_) {}
          return null;
        }),
      );

      for (final item in responses) {
        if (item == null) continue;
        final decoded = jsonDecode(item['body']!);
        if (decoded is! Map || decoded['features'] is! List) continue;
        final defaultCat = item['defaultCat']!;

        for (final feature in decoded['features'] as List) {
          if (feature is! Map) continue;
          final geometry = feature['geometry'];
          final properties = feature['properties'];
          if (geometry is! Map || properties is! Map) continue;

          final coords = geometry['coordinates'];
          if (coords is! List || coords.length < 2) continue;
          final lng = double.tryParse(coords[0].toString());
          final lat = double.tryParse(coords[1].toString());
          if (lat == null || lng == null) continue;

          final distMeters = distanceCalc.as(
            LengthUnit.Meter,
            center,
            LatLng(lat, lng),
          );
          if (distMeters < 15 || distMeters > 4500) continue;

          final name = (properties['name'] ?? '').toString().trim();
          if (name.isEmpty || !seenNames.add(name.toLowerCase())) continue;

          final osmKey = (properties['osm_key'] ?? '').toString().toLowerCase();
          final osmVal =
          (properties['osm_value'] ?? '').toString().toLowerCase();

          if (const {
            'hotel', 'hostel', 'motel', 'guest_house', 'apartment',
            'bus_stop', 'station', 'office', 'supermarket', 'convenience',
          }.contains(osmVal)) {
            continue;
          }

          String mappedCat = defaultCat;
          if (osmVal == 'museum' || osmVal == 'gallery') {
            mappedCat = 'museum';
          } else if (osmVal == 'viewpoint') {
            mappedCat = 'viewpoint';
          } else if (osmKey == 'leisure' ||
              osmVal == 'park' ||
              osmVal == 'garden' ||
              osmVal == 'nature_reserve') {
            mappedCat = 'park';
          } else if (osmKey == 'historic' ||
              osmVal == 'monument' ||
              osmVal == 'memorial' ||
              osmVal == 'castle') {
            mappedCat = 'monument';
          } else if (osmKey == 'tourism') {
            mappedCat = 'tourism';
          }

          discovered.add(
            PoiModel(
              id: (properties['osm_id'] ?? name).toString(),
              name: name,
              lat: lat,
              lng: lng,
              category: mappedCat,
            ),
          );
        }
      }
    } catch (e) {
      print('⚠️ Photon Hidden Gems fallback error: $e');
    }

    if (discovered.isNotEmpty) {
      print(
        '✨ Photon fallback found ${discovered.length} Hidden Gems near '
            '${centerLat.toStringAsFixed(4)}, ${centerLng.toStringAsFixed(4)}.',
      );
      return discovered;
    }

    try {
      const pad = 0.025;
      final uri = Uri.parse(_nominatimUrl).replace(
        queryParameters: {
          'q': 'park',
          'format': 'jsonv2',
          'limit': '15',
          'accept-language': 'en',
          'viewbox':
          '${(centerLng - pad).toStringAsFixed(4)},'
              '${(centerLat + pad).toStringAsFixed(4)},'
              '${(centerLng + pad).toStringAsFixed(4)},'
              '${(centerLat - pad).toStringAsFixed(4)}',
          'bounded': '1',
        },
      );
      final response = await http
          .get(
        uri,
        headers: const {
          'User-Agent': 'journii-app/1.0 (contact@journii.app)',
          'Accept': 'application/json',
        },
      )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final lat = double.tryParse(item['lat']?.toString() ?? '');
            final lng = double.tryParse(item['lon']?.toString() ?? '');
            final name = (item['name'] ??
                item['display_name']?.toString().split(',').first ??
                '')
                .toString()
                .trim();
            if (lat == null || lng == null || name.isEmpty) continue;
            if (seenNames.add(name.toLowerCase())) {
              discovered.add(
                PoiModel(
                  id: (item['osm_id'] ?? name).toString(),
                  name: name,
                  lat: lat,
                  lng: lng,
                  category: 'park',
                ),
              );
            }
          }
        }
      }
    } catch (_) {}

    return discovered;
  }

  static String _hiddenGemCacheKey(PoiBounds bounds) {
    final centerLat = (bounds.south + bounds.north) / 2;
    final centerLng = (bounds.west + bounds.east) / 2;
    return '${centerLat.toStringAsFixed(4)}:${centerLng.toStringAsFixed(4)}';
  }

  static Future<List<PoiModel>?> _requestHiddenGemPOIs(String query) async {
    final attempts = _servers.length < _maxServerAttempts
        ? _servers.length
        : _maxServerAttempts;
    final selectedServers = List<String>.generate(
      attempts,
          (index) => _servers[(_serverIndex + index) % _servers.length],
    );
    _serverIndex = (_serverIndex + attempts) % _servers.length;

    for (var attempt = 0; attempt < selectedServers.length; attempt++) {
      final serverUrl = selectedServers[attempt];
      print(
        '🌍 Hidden Gems Overpass request ${attempt + 1}/'
            '${selectedServers.length}: $serverUrl',
      );

      try {
        final response = await http
            .post(
          Uri.parse(serverUrl),
          headers: const {
            'User-Agent': 'JourniiTravelApp/1.0',
            'Accept': 'application/json',
          },
          body: {'data': query},
        )
            .timeout(_requestTimeout);

        if (response.statusCode != 200) {
          final preview = response.body.length > 350
              ? '${response.body.substring(0, 350)}…'
              : response.body;
          print(
            '⚠️ Hidden Gems Overpass HTTP ${response.statusCode} '
                'from $serverUrl: $preview',
          );

          final retryable = const {
            408, 425, 429, 500, 502, 503, 504,
          }.contains(response.statusCode);

          if (!retryable) {
            return null;
          }

          if (attempt < selectedServers.length - 1) {
            final delay = _hiddenGemRetryDelay(
              attempt,
              response.headers['retry-after'],
            );
            print(
              '🔁 Retrying after ${delay.inSeconds}s using another endpoint.',
            );
            await Future.delayed(delay);
          }
          continue;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException(
            'Overpass returned an unexpected JSON response.',
          );
        }

        final remark = decoded['remark']?.toString().trim();
        if (remark != null && remark.isNotEmpty) {
          throw FormatException('Overpass runtime warning: $remark');
        }

        final elements = decoded['elements'];
        if (elements is! List) {
          throw const FormatException(
            'Overpass response did not contain an elements array.',
          );
        }

        if (elements.isEmpty) {
          print('ℹ️ Hidden Gems query succeeded; no matching named POIs found.');
          return <PoiModel>[];
        }

        final pois = <PoiModel>[];
        final seenIds = <String>{};

        for (final element in elements) {
          if (element is! Map) continue;
          try {
            final poi = PoiModel.fromJson(
              Map<String, dynamic>.from(element),
            );
            final key =
                '${element['type'] ?? 'element'}/${element['id'] ?? ''}';
            if (poi.name != 'Unknown Place' && seenIds.add(key)) {
              pois.add(poi);
            }
          } catch (e) {
            print('⚠️ Skipping an unusable Hidden Gems POI: $e');
          }
        }

        print(
          '✅ Hidden Gems query returned ${pois.length} usable named POIs '
              'from $serverUrl.',
        );
        return pois;
      } catch (e) {
        print('⚠️ Hidden Gems request failed on $serverUrl: $e');
        if (attempt < selectedServers.length - 1) {
          final delay = _hiddenGemRetryDelay(attempt, null);
          print(
            '🔁 Retrying after ${delay.inSeconds}s using another endpoint.',
          );
          await Future.delayed(delay);
        }
      }
    }

    return null;
  }

  static Duration _hiddenGemRetryDelay(int attempt, String? retryAfter) {
    final retryAfterSeconds = int.tryParse(retryAfter?.trim() ?? '');
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      return Duration(seconds: retryAfterSeconds.clamp(1, 5).toInt());
    }

    final exponentialMilliseconds = math.min(
      _hiddenGemMaxBackoff.inMilliseconds,
      _hiddenGemBaseBackoff.inMilliseconds * (1 << attempt),
    ).toInt();
    return Duration(milliseconds: exponentialMilliseconds);
  }

  // --------------------------------------------------
  // 🌳 STEP 1: WANDER ENGINE
  // --------------------------------------------------
  static Future<List<LatLng>?> getWanderWaypoints({
    required LatLng start,
    required LatLng end,
    required String theme,
  }) async {
    final distanceCalc = const Distance();
    final directDistance = distanceCalc.as(LengthUnit.Meter, start, end);

    if (directDistance < 800) return null;

    final bounds = PoiBounds(
      south: math.min(start.latitude, end.latitude) - 0.015,
      west: math.min(start.longitude, end.longitude) - 0.015,
      north: math.max(start.latitude, end.latitude) + 0.015,
      east: math.max(start.longitude, end.longitude) + 0.015,
    );

    try {
      final rawPlaces = await fetchPOIs(bounds);

      List<PoiModel> themePlaces = [];
      if (theme == 'scenic') {
        themePlaces = rawPlaces
            .where(
              (p) =>
          p.category == 'viewpoint' ||
              p.category == 'park' ||
              p.category == 'tourism',
        )
            .toList();
      } else if (theme == 'foodie') {
        themePlaces = rawPlaces
            .where(
              (p) =>
          p.category == 'cafe' ||
              p.category == 'restaurant' ||
              p.category == 'fast_food' ||
              p.category == 'pub',
        )
            .toList();
      } else if (theme == 'culture') {
        themePlaces = rawPlaces
            .where(
              (p) =>
          p.category == 'museum' ||
              p.category == 'cinema' ||
              p.category == 'monument' ||
              p.category == 'place_of_worship' ||
              p.category == 'hindu' ||
              p.category == 'muslim' ||
              p.category == 'christian' ||
              p.category == 'buddhist',
        )
            .toList();
      }

      if (themePlaces.isEmpty) return null;

      PoiModel? bestStop;
      double minDetourScore = double.infinity;

      for (var place in themePlaces) {
        final placeLoc = LatLng(place.lat, place.lng);

        final detourDistance =
            distanceCalc.as(LengthUnit.Meter, start, placeLoc) +
                distanceCalc.as(LengthUnit.Meter, placeLoc, end);

        final extraDistance = detourDistance - directDistance;

        if (extraDistance < (directDistance * 0.60)) {
          if (extraDistance < minDetourScore) {
            minDetourScore = extraDistance;
            bestStop = place;
          }
        }
      }

      if (bestStop != null) {
        print(
          '🌳 WANDER ROUTE: Injecting ${bestStop.name} '
              '(Adds ${minDetourScore.round()}m extra)',
        );
        return [LatLng(bestStop.lat, bestStop.lng)];
      }

      return null;
    } catch (e) {
      print('Wander Engine Error: $e');
      return null;
    }
  }
}

class _PoiCacheEntry {
  final List<PoiModel> places;
  final DateTime expiresAt;

  const _PoiCacheEntry({required this.places, required this.expiresAt});
}

// 📦 THE MODEL
class PoiModel {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String category;

  PoiModel({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.category,
  });

  factory PoiModel.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final tags = rawTags is Map ? rawTags : <String, dynamic>{};

    final rawCenter = json['center'];
    final center = rawCenter is Map ? rawCenter : const <String, dynamic>{};

    final latitude = _readCoordinate(json['lat'] ?? center['lat']);
    final longitude = _readCoordinate(json['lon'] ?? center['lon']);

    if (latitude == null || longitude == null) {
      throw const FormatException('OSM element has no usable coordinates.');
    }

    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('OSM element contains invalid coordinates.');
    }

    String cat = 'place';
    if (tags.containsKey('tourism')) {
      final t = tags['tourism'].toString().toLowerCase();
      if (t == 'museum' || t == 'viewpoint' || t == 'hotel' || t == 'hostel' || t == 'motel') {
        cat = t;
      } else {
        cat = 'tourism';
      }
    } else if (tags.containsKey('leisure')) {
      final l = tags['leisure'].toString().toLowerCase();
      cat = (l == 'park' || l == 'garden' || l == 'nature_reserve') ? 'park' : l;
    } else if (tags.containsKey('historic')) {
      cat = 'monument';
    } else if (tags.containsKey('religion')) {
      cat = tags['religion'].toString();
    } else if (tags.containsKey('amenity')) {
      cat = tags['amenity'].toString();
    } else if (tags.containsKey('shop')) {
      cat = tags['shop'].toString();
    }

    final englishName = tags['name:en']?.toString().trim();
    final localName = tags['name']?.toString().trim();
    final resolvedName = (englishName != null && englishName.isNotEmpty)
        ? englishName
        : (localName != null && localName.isNotEmpty)
        ? localName
        : 'Unknown Place';

    return PoiModel(
      id: (json['id'] ?? '').toString(),
      name: resolvedName,
      lat: latitude,
      lng: longitude,
      category: cat,
    );
  }

  static double? _readCoordinate(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}