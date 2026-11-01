import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Coordinates from another mapped place in the same itinerary day.
/// They are used only as weak geographic evidence when an AI place has no
/// city-level geoContext; they never override an explicit geoContext.
class GeocodingAnchor {
  final double latitude;
  final double longitude;
  final String label;
  final String? locality;
  final String? region;

  const GeocodingAnchor({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.locality,
    this.region,
  });
}

class GeocodingService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org/search';
  static const String _photonUrl = 'https://photon.komoot.io/api/';
  static const String _overpassUrl = String.fromEnvironment(
    'OSM_OVERPASS_URL',
    defaultValue: 'https://overpass-api.de/api/interpreter',
  );
  static const Duration _overpassTimeout = Duration(seconds: 12);

  static const String _searxngSearchUrl = String.fromEnvironment(
    'SEARXNG_SEARCH_URL',
    defaultValue: 'https://searxng-production-1eb8.up.railway.app/search',
  );
  static const Duration _webSearchTimeout = Duration(seconds: 10);

  static const Duration _minimumRequestInterval =
  Duration(milliseconds: 1100);

  static DateTime? _lastRequestStartedAt;
  static Future<void> _requestQueue = Future<void>.value();

  static const double _confidentMatchScore = 8.0;
  static const double _minimumAcceptableScore = 5.0;
  static const double _maxSameDayAnchorDistanceKm = 65.0;

  /// Cache of web aliases discovered per targetName so Pass 2 retries don't
  /// lose aliases found during Pass 1.
  static final Map<String, List<String>> _webAliasCache = {};

  static Future<LatLngResult?> geocodeDetailed(
      String placeName, {
        String? countryCode,
        bool useWebSearch = false,
        List<GeocodingAnchor> nearbyAnchors = const <GeocodingAnchor>[],
        List<String> additionalAliases = const <String>[],
        bool allowUnanchoredFallback = false,
      }) async {
    final originalQuery = placeName.trim();
    if (originalQuery.isEmpty) return null;

    final targetName = _extractTargetName(originalQuery);
    final geographicContext = _extractGeographicContext(
      originalQuery,
      countryCode,
    );
    final hasSpecificGeographicContext =
        geographicContext.localityParts.isNotEmpty;

    // Always retain coherent same-day anchors when provided by the caller.
    // Even when the trip destination is a city (e.g. "New York City", "Paris"),
    // same-day anchors bias results toward the right borough/neighborhood
    // (e.g. Coney Island vs Manhattan, or Williamsburg vs Flatbush) and prevent
    // fallback queries from jumping to another state.
    final effectiveAnchors = _selectCoherentAnchors(nearbyAnchors);
    if (nearbyAnchors.length > effectiveAnchors.length) {
      print(
        '🧭 Reduced geographic context from ${nearbyAnchors.length} '
            'anchor(s) to ${effectiveAnchors.length} coherent anchor(s) '
            'for "$targetName".',
      );
    }

    final nearbyLocalities = <String>[];
    final seenNearbyLocalities = <String>{};
    for (final anchor in effectiveAnchors) {
      // Prefer region/city over tiny sub-villages ("Ban ...")
      final primaryLocality = anchor.locality?.trim() ?? '';
      final regionLocality = anchor.region?.trim() ?? '';
      final candidates = <String>[
        if (primaryLocality.isNotEmpty &&
            !RegExp(r'^ban\s+', caseSensitive: false).hasMatch(primaryLocality))
          primaryLocality,
        if (regionLocality.isNotEmpty) regionLocality,
        if (primaryLocality.isNotEmpty) primaryLocality,
      ];
      for (final loc in candidates) {
        final key = _normalise(loc);
        if (loc.isNotEmpty && key.isNotEmpty && seenNearbyLocalities.add(key)) {
          nearbyLocalities.add(loc);
          break;
        }
      }
    }

    final cacheKey = '${countryCode ?? ''}:${_normalise(targetName)}';
    var webAliases = <String>[...(_webAliasCache[cacheKey] ?? const [])];
    if (useWebSearch) {
      final commaIndex = originalQuery.indexOf(',');
      final placeContext = commaIndex >= 0
          ? originalQuery.substring(commaIndex + 1).trim()
          : '';
      final searchContext =
      !hasSpecificGeographicContext && nearbyLocalities.isNotEmpty
          ? <String>[
        ...nearbyLocalities.take(1),
        if (placeContext.isNotEmpty) placeContext,
      ].join(', ')
          : placeContext;
      final fetchedAliases = await _searchWebTitleAliases(
        targetName: targetName,
        geoContext: searchContext,
      );
      if (fetchedAliases.isNotEmpty) {
        webAliases = <String>{...webAliases, ...fetchedAliases}.toList();
        _webAliasCache[cacheKey] = webAliases;
      }
    }

    // If the query includes a specific square/sub-venue before the city
    // (e.g. "Aventine Keyhole, Piazza dei Cavalieri di Malta, Rome, Lazio, Italy"),
    // include that sub-venue as a fallback alias.
    final rawQueryParts = originalQuery
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final subVenueAlias = (rawQueryParts.length >= 4 &&
        _normalise(rawQueryParts[1]) != 'vatican city' &&
        _normalise(rawQueryParts[1]) != 'vatican')
        ? <String>[rawQueryParts[1]]
        : const <String>[];

    final targetAliases = <String>{
      ...additionalAliases,
      ..._buildTargetNameAlternatives(targetName),
      ...webAliases,
      ...subVenueAlias,
    }.where((a) => a.trim().isNotEmpty).take(8).toList();

    final queries = _buildQueryVariants(
      originalQuery,
      additionalTargetNames: targetAliases,
      additionalLocalities: nearbyLocalities,
    );

    LatLngResult? bestResult;
    double bestScore = double.negativeInfinity;
    final candidateResultsByCoordinate = <String, LatLngResult>{};
    final candidateScoresByCoordinate = <String, double>{};

    try {
      for (var queryIndex = 0; queryIndex < queries.length; queryIndex++) {
        final query = queries[queryIndex];
        LatLngResult? bestQueryResult;
        double bestQueryScore = double.negativeInfinity;
        final bestScoreAtQueryStart = bestScore;
        print(
          '🌍 OSM geocoding attempt ${queryIndex + 1}/${queries.length}: '
              '"$query"${countryCode != null ? ' [country=$countryCode]' : ''}',
        );

        final candidates = await _searchCandidates(
          query,
          countryCode: countryCode,
          preferOverpass: false,
          nearbyAnchors: effectiveAnchors,
        );

        if (candidates == null || candidates.isEmpty) {
          print('   ↪ No candidates returned for "$query".');
          continue;
        }

        for (final candidate in candidates) {
          final result = _toLatLngResult(candidate);
          if (result == null) continue;

          final expectedCountryCode = countryCode?.trim().toLowerCase();
          final returnedCountryCode = result.countryCode?.trim().toLowerCase();

          if (expectedCountryCode != null &&
              expectedCountryCode.isNotEmpty &&
              returnedCountryCode != null &&
              returnedCountryCode.isNotEmpty &&
              returnedCountryCode != expectedCountryCode) {
            print(
              '   🚫 Rejected country mismatch: ${result.displayName} '
                  '(${result.countryCode}; expected $expectedCountryCode).',
            );
            continue;
          }

          if (geographicContext.hasContext &&
              !_candidateMatchesGeographicContext(
                candidate: candidate,
                result: result,
                context: geographicContext,
              )) {
            final anchorLocality = geographicContext.anchorLocality;

            if (anchorLocality == null) {
              if (!_hasExactCandidateNameMatch(
                candidate,
                targetName,
                additionalNames: targetAliases,
              )) {
                print(
                  '   🚫 Rejected geographic mismatch: no usable locality '
                      'anchor and no exact place-name match for '
                      '"${result.displayName ?? result.name ?? targetName}".',
                );
                continue;
              }
            } else {
              final anchor = await _getContextAnchor(
                anchorLocality,
                countryCode: expectedCountryCode,
              );

              if (anchor == null) {
                if (!_hasExactCandidateNameMatch(
                  candidate,
                  targetName,
                  additionalNames: targetAliases,
                )) {
                  print(
                    '   🚫 Rejected geographic mismatch: could not resolve '
                        'context anchor "$anchorLocality" for '
                        '"${result.displayName ?? result.name ?? targetName}".',
                  );
                  continue;
                }
              } else {
                final distanceKm = _distanceInKm(
                  anchor.latitude,
                  anchor.longitude,
                  result.latitude,
                  result.longitude,
                );
                final maxDistanceKm = _contextRadiusKm(
                  anchorLocality,
                  targetName: targetName,
                );

                if (distanceKm > maxDistanceKm) {
                  print(
                    '   🚫 Rejected geographic mismatch: candidate is '
                        '${distanceKm.toStringAsFixed(1)} km from "$anchorLocality" '
                        '(allowed ${maxDistanceKm.toStringAsFixed(0)} km). '
                        'Result: ${result.displayName ?? result.name ?? '(unnamed)'}.',
                  );
                  continue;
                }
              }
            }
          }

          // Enforce same-day anchor proximity whenever coherent same-day anchors
          // are available, preventing fallback queries from jumping across states
          // (e.g. "Nathan's Famous" matching Hershey, PA instead of Brooklyn, NY).
          if (effectiveAnchors.isNotEmpty) {
            final nearestAnchorKm = _nearestAnchorDistanceKm(
              result,
              effectiveAnchors,
            );
            final allowedAnchorDistanceKm =
            _maxAnchorDistanceKmForTarget(targetName);
            if (nearestAnchorKm > allowedAnchorDistanceKm) {
              print(
                '   🚫 Rejected same-day locality mismatch: candidate is '
                    '${nearestAnchorKm.toStringAsFixed(1)} km from the nearest '
                    'mapped itinerary place (allowed '
                    '${allowedAnchorDistanceKm.toStringAsFixed(0)} km). Result: '
                    '${result.displayName ?? result.name ?? '(unnamed)'}.',
              );
              continue;
            }

            if (!hasSpecificGeographicContext &&
                _conflictsWithAnchorRegions(
                  result: result,
                  targetName: targetName,
                  anchors: effectiveAnchors,
                  nearestAnchorDistanceKm: nearestAnchorKm,
                )) {
              print(
                '   🚫 Rejected region mismatch: ${result.region} does not '
                    'match any nearby itinerary region. Result: '
                    '${result.displayName ?? result.name ?? '(unnamed)'}.',
              );
              continue;
            }
          }

          if (!_hasSufficientNameEvidence(
            candidate,
            targetName,
            additionalNames: targetAliases,
          )) {
            print(
              '   🚫 Rejected place-identity mismatch for "$targetName": '
                  '${result.displayName ?? result.name ?? '(unnamed result)'}',
            );
            continue;
          }

          final score = _scoreCandidate(
            candidate: candidate,
            targetName: targetName,
            query: query,
            expectedCountryCode: expectedCountryCode,
            additionalNames: targetAliases,
            nearbyAnchors: effectiveAnchors,
          );

          print(
            '   🔎 Candidate score ${score.toStringAsFixed(1)}: '
                '${result.displayName ?? result.name ?? '(unnamed result)'} '
                '[${result.category ?? 'unknown category'}/'
                '${result.type ?? 'unknown type'}]',
          );

          final coordinateKey =
              '${result.latitude.toStringAsFixed(4)},${result.longitude.toStringAsFixed(4)}';
          if (score >
              (candidateScoresByCoordinate[coordinateKey] ??
                  double.negativeInfinity)) {
            candidateScoresByCoordinate[coordinateKey] = score;
            candidateResultsByCoordinate[coordinateKey] = result;
          }

          if (score > bestQueryScore) {
            bestQueryScore = score;
            bestQueryResult = result;
          }
          if (score > bestScore) {
            bestScore = score;
            bestResult = result;
          }
        }

        final queryUsesInferredLocality = nearbyLocalities.any(
              (locality) => _normalise(query).contains(_normalise(locality)),
        );
        if (bestQueryResult != null &&
            bestQueryScore >= _confidentMatchScore &&
            bestQueryScore > bestScoreAtQueryStart &&
            (hasSpecificGeographicContext || queryUsesInferredLocality)) {
          print(
            '✅ Accepted high-confidence match for "$targetName" '
                '(score ${bestQueryScore.toStringAsFixed(1)}).',
          );
          _logApproximateAliasIfNeeded(targetName, bestQueryResult);
          return bestQueryResult;
        }
      }

      final isGeographicallyAmbiguous = _hasGeographicallyAmbiguousCandidates(
        candidateResultsByCoordinate,
        candidateScoresByCoordinate,
        bestScore,
      );

      if (!allowUnanchoredFallback &&
          bestResult != null &&
          !hasSpecificGeographicContext &&
          effectiveAnchors.isEmpty) {
        if (isGeographicallyAmbiguous) {
          print(
            '⚠️ Ambiguous country-level match for "$targetName"; '
                'waiting for same-day geographic context before accepting coordinates.',
          );
          return null;
        }
        if (_isStrictlyGenericPlaceName(targetName) && bestScore < 18.0) {
          print(
            '⚠️ "$targetName" is a generic place name and needs city-level context; '
                'waiting for same-day geographic anchors before accepting coordinates.',
          );
          return null;
        }
      }

      if (bestResult != null && bestScore >= _minimumAcceptableScore) {
        print(
          '✅ Accepted best available match for "$targetName" '
              'after fallback searches (score ${bestScore.toStringAsFixed(1)}): '
              '${bestResult.displayName}',
        );
        _logApproximateAliasIfNeeded(targetName, bestResult);
        return bestResult;
      }

      // 🛡️ ULTIMATE GLOBAL SAFETY NET:
      // If the AI generated a descriptive/poetic activity name that is not
      // indexed as a standalone POI in OSM, pin it to its specific geoContext
      // locality (or same-day neighborhood anchor) so 0 items are ever dropped.
      if (geographicContext.localityParts.isNotEmpty) {
        final fallbackLocality = geographicContext.localityParts.first;
        final anchor = await _getContextAnchor(
          fallbackLocality,
          countryCode: countryCode?.trim().toLowerCase(),
        );
        if (anchor != null) {
          print(
            '📍 Mapped "$targetName" via locality anchor fallback "$fallbackLocality": '
                '${anchor.latitude}, ${anchor.longitude}',
          );
          return LatLngResult(
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            countryCode: countryCode?.trim().toLowerCase(),
            locality: fallbackLocality,
            displayName: '$targetName ($fallbackLocality)',
            name: targetName,
          );
        }
      }

      if (allowUnanchoredFallback && effectiveAnchors.isNotEmpty) {
        final primaryAnchor = effectiveAnchors.first;
        print(
          '📍 Mapped "$targetName" via same-day neighborhood anchor "${primaryAnchor.label}": '
              '${primaryAnchor.latitude}, ${primaryAnchor.longitude}',
        );
        return LatLngResult(
          latitude: primaryAnchor.latitude,
          longitude: primaryAnchor.longitude,
          countryCode: countryCode?.trim().toLowerCase(),
          locality: primaryAnchor.locality,
          region: primaryAnchor.region,
          displayName: '$targetName (near ${primaryAnchor.label})',
          name: targetName,
        );
      }

      print(
        '⚠️ No sufficiently reliable geocoding match for "$targetName". '
            'Best score: ${bestScore.isFinite ? bestScore.toStringAsFixed(1) : 'none'}.',
      );
      return null;

    } catch (e) {
      print('💥 Geocoding error for "$originalQuery": $e');
      return null;
    }
  }

  static Future<LatLngResult?> geocode(String placeName) async {
    return geocodeDetailed(placeName);
  }

  static double _nearestAnchorDistanceKm(
      LatLngResult result,
      List<GeocodingAnchor> anchors,
      ) {
    if (anchors.isEmpty) return double.infinity;
    var nearestDistance = double.infinity;
    for (final anchor in anchors) {
      final distance = _distanceInKm(
        result.latitude,
        result.longitude,
        anchor.latitude,
        anchor.longitude,
      );
      if (distance < nearestDistance) nearestDistance = distance;
    }
    return nearestDistance;
  }

  static List<GeocodingAnchor> _selectCoherentAnchors(
      List<GeocodingAnchor> anchors,
      ) {
    if (anchors.length <= 1) return List<GeocodingAnchor>.from(anchors);

    for (var i = 0; i < anchors.length; i++) {
      for (var j = i + 1; j < anchors.length; j++) {
        final a = anchors[i];
        final b = anchors[j];
        final distanceKm = _distanceInKm(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        );
        if (distanceKm > _maxSameDayAnchorDistanceKm) {
          print(
            '⚠️ Geographic anchors span multiple localities '
                '(${distanceKm.toStringAsFixed(1)} km apart); '
                'ignoring them rather than guessing a city.',
          );
          return const <GeocodingAnchor>[];
        }
      }
    }

    return List<GeocodingAnchor>.from(anchors);
  }

  static double _maxAnchorDistanceKmForTarget(String targetName) {
    final normalized = _normalise(targetName);
    const excursionFeatureTerms = {
      'island', 'islands', 'ko', 'koh', 'bay', 'ao', 'beach', 'hat', 'cape',
      'laem', 'waterfall', 'waterfalls', 'namtok', 'river', 'reef', 'lagoon',
      'coast', 'coastline', 'archipelago', 'cave', 'tham', 'national', 'park',
      'mangrove', 'forest', 'pool', 'spring', 'springs', 'tour', 'tours',
      'excursion', 'cruise', 'mountain', 'mount', 'mt', 'volcano', 'canyon',
    };
    final words = normalized.split(' ').toSet();
    return words.intersection(excursionFeatureTerms).isNotEmpty
        ? 120.0
        : _maxSameDayAnchorDistanceKm;
  }

  static bool _conflictsWithAnchorRegions({
    required LatLngResult result,
    required String targetName,
    required List<GeocodingAnchor> anchors,
    required double nearestAnchorDistanceKm,
  }) {
    if (_maxAnchorDistanceKmForTarget(targetName) >
        _maxSameDayAnchorDistanceKm) {
      return false;
    }

    final candidateRegion = result.region?.trim() ?? '';
    if (candidateRegion.isEmpty || nearestAnchorDistanceKm <= 25.0) {
      return false;
    }

    if (_normalise(candidateRegion) == _normalise(result.countryName ?? '')) {
      return false;
    }

    final anchorRegions = anchors
        .map((anchor) => anchor.region?.trim() ?? '')
        .where((region) => region.isNotEmpty)
        .map(_normalise)
        .toSet();
    if (anchorRegions.isEmpty) return false;

    final normalizedCandidateRegion = _normalise(candidateRegion);
    final matchesAnAnchorRegion = anchorRegions.any(
          (region) =>
      region == normalizedCandidateRegion ||
          region.contains(normalizedCandidateRegion) ||
          normalizedCandidateRegion.contains(region),
    );
    return !matchesAnAnchorRegion;
  }

  /// Only truly generic labels (without a unique proper noun) should be forced
  /// to wait when Nominatim returns a single unambiguous city match.
  static bool _isStrictlyGenericPlaceName(String targetName) {
    final normalized = _normalise(targetName);
    const genericLabels = {
      'big buddha',
      'grand palace',
      'night bazaar',
      'night market',
      'walking street',
      'sunday market',
      'weekend market',
      'floating market',
      'central market',
      'flower market',
      'old city',
      'old town',
      'chinatown',
      'little italy',
      'city pillar shrine',
      'white temple',
      'black house',
      'blue temple',
      'hong island',
    };
    return genericLabels.contains(normalized);
  }

  static bool _hasGeographicallyAmbiguousCandidates(
      Map<String, LatLngResult> resultsByCoordinate,
      Map<String, double> scoresByCoordinate,
      double bestScore,
      ) {
    final plausibleResults = resultsByCoordinate.entries
        .where(
          (entry) =>
      (scoresByCoordinate[entry.key] ?? double.negativeInfinity) >=
          bestScore - 4.0,
    )
        .map((entry) => entry.value)
        .toList();

    for (var first = 0; first < plausibleResults.length; first++) {
      for (var second = first + 1; second < plausibleResults.length; second++) {
        final a = plausibleResults[first];
        final b = plausibleResults[second];
        if (_distanceInKm(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ) >
            40.0) {
          print(
            '   🧭 Competing locations: '
                '${a.displayName ?? a.name ?? '(candidate A)'} versus '
                '${b.displayName ?? b.name ?? '(candidate B)'}.',
          );
          return true;
        }
      }
    }
    return false;
  }

  static void _logApproximateAliasIfNeeded(
      String targetName,
      LatLngResult result,
      ) {
    final target = _normalise(targetName);
    final resolvedName = _normalise(
      result.name ?? result.displayName?.split(',').first ?? '',
    );
    if (target == 'thonburi canals' || target == 'thonburi canal') {
      if (resolvedName.contains('bangkok yai canal') ||
          resolvedName.contains('khlong bangkok yai')) {
        print(
          'ℹ️ "Thonburi Canals" resolved to Bangkok Yai Canal as a '
              'representative canal location; this is not a specific tour pier.',
        );
      }
    }
  }

  static String _extractTargetName(String query) {
    final commaIndex = query.indexOf(',');
    if (commaIndex < 0) return query.trim();
    return query.substring(0, commaIndex).trim();
  }

  static Future<List<String>> _searchWebTitleAliases({
    required String targetName,
    required String geoContext,
  }) async {
    final configuredUrl = _searxngSearchUrl.trim();
    final baseEndpoint = Uri.tryParse(configuredUrl);
    if (baseEndpoint == null ||
        !baseEndpoint.hasAuthority ||
        !const {'http', 'https'}.contains(baseEndpoint.scheme)) {
      print('⚠️ Invalid SearXNG search URL; continuing with Nominatim.');
      return <String>[];
    }

    final searchQuery = <String>[
      targetName.trim(),
      if (geoContext.trim().isNotEmpty) geoContext.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    if (searchQuery.isEmpty) return <String>[];

    final endpoint = baseEndpoint.replace(
      queryParameters: <String, String>{
        ...baseEndpoint.queryParameters,
        'q': searchQuery,
        'format': 'json',
        'language': 'en',
        'pageno': '1',
        'safesearch': '1',
      },
    );

    try {
      print('🔎 Direct SearXNG lookup: "$searchQuery"');
      final response = await http
          .get(
        endpoint,
        headers: const {'Accept': 'application/json'},
      )
          .timeout(_webSearchTimeout);

      if (response.statusCode != 200) {
        print(
          '⚠️ SearXNG returned HTTP ${response.statusCode}; '
              'continuing with Nominatim.',
        );
        return <String>[];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return <String>[];

      final results = decoded['results'];
      if (results is! List || results.isEmpty) return <String>[];

      final aliases = _extractSearchTitleAliases(results, targetName);
      print(
        '🔎 SearXNG returned ${results.length} result(s); '
            'accepted ${aliases.length} conservative title alias(es).',
      );
      return aliases;
    } on TimeoutException {
      print('⏱️ SearXNG lookup timed out; continuing with Nominatim.');
      return <String>[];
    } catch (error) {
      print('⚠️ Direct SearXNG lookup failed; continuing with Nominatim: $error');
      return <String>[];
    }
  }

  static final RegExp _editorialHeadlinePattern = RegExp(
    r'(\bthe\s+\d+\s+best\b|\bthe\s+best\b|^best\s+|\btop\s+\d+\b|\bmy\s+guide\b|'
    r'\bcomplete\s+guide\b|\btravel\s+guide\b|\bvisitor\s+guide\b|\bguide\s+to\b|'
    r'\bguide\b|\bthings\s+to\s+do\b|\bwhat\s+to\s+know\b|\bdeep\s+dive\b|'
    r'\breview\b|\breviews\b|\b360°|\bhow\s+to\s+visit\b|\beverything\s+you\s+need\b|'
    r'\bitinerary\b|\bbest\s+time\s+to\b|\bflights\s+from\b|\breal\s+experience\b|'
    r'\bfor\s+sale\b|\bfor\s+rent\b|\breal\s+estate\b|\bwhere\s+to\b|'
    r'\b202\d\b|\b203\d\b)',
    caseSensitive: false,
  );

  static List<String> _extractSearchTitleAliases(
      List<dynamic> results,
      String targetName,
      ) {
    final targetNormalized = _normalise(targetName);
    final targetTokens = targetNormalized
        .split(' ')
        .where((token) => token.isNotEmpty && !_isStopWord(token))
        .toSet();
    if (targetTokens.isEmpty) return <String>[];

    final aliases = <String>[];
    final seen = <String>{targetNormalized};

    void addCandidateAlias(String rawCandidate) {
      final cleaned = rawCandidate
          .replaceAll(RegExp(r'\([^)]*\)'), '')
          .replaceFirst(RegExp(r'^map\s+of\s+', caseSensitive: false), '')
          .replaceAll(RegExp(r'\b(in\s+)?20[23]\d\b', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.isEmpty || _editorialHeadlinePattern.hasMatch(cleaned)) {
        return;
      }
      final norm = _normalise(cleaned);
      // Never accept purely numeric strings (e.g. "2026"), 2-letter codes, or long sentences
      if (norm.isEmpty ||
          norm.length < 4 ||
          RegExp(r'^\d+$').hasMatch(norm.replaceAll(' ', '')) ||
          !RegExp(r'[a-zA-Z\u0E00-\u0E7F]').hasMatch(norm) ||
          norm.split(' ').length > 6 ||
          !seen.add(norm)) {
        return;
      }
      aliases.add(cleaned);
    }

    final parentheticalRegex = RegExp(r'([^(]+)\(([^)]+)\)');

    for (final rawResult in results.take(6)) {
      if (rawResult is! Map) continue;
      final rawTitle = (rawResult['title'] ?? '').toString().trim();
      if (rawTitle.isEmpty) continue;

      final firstSegment = rawTitle
          .split(RegExp(r'\s+(?:\||—|–|-|:)\s+'))
          .first
          .replaceFirst(RegExp(r'^map\s+of\s+', caseSensitive: false), '')
          .trim();

      final parenMatch = parentheticalRegex.firstMatch(firstSegment);
      if (parenMatch != null) {
        final outside = parenMatch.group(1)!.trim();
        final inside = parenMatch.group(2)!.trim();
        final outsideNorm = _normalise(outside);
        final insideNorm = _normalise(inside);

        if (!RegExp(r'^\d{4}$').hasMatch(insideNorm)) {
          if (outsideNorm.contains(targetNormalized) ||
              targetNormalized.contains(outsideNorm) ||
              insideNorm.contains(targetNormalized) ||
              targetNormalized.contains(insideNorm)) {
            addCandidateAlias(outside);
            addCandidateAlias(inside);
          }
        }
      }

      if (_editorialHeadlinePattern.hasMatch(firstSegment)) continue;

      final cleanTitle = firstSegment
          .replaceAll(RegExp(r'\([^)]*\)'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final normalizedTitle = _normalise(cleanTitle);
      if (normalizedTitle.isEmpty) continue;

      final candidateTokens = normalizedTitle
          .split(' ')
          .where((token) => token.isNotEmpty && !_isStopWord(token))
          .toSet();
      if (candidateTokens.isEmpty ||
          candidateTokens.length > targetTokens.length + 3) {
        continue;
      }

      final sharedTokens = targetTokens.intersection(candidateTokens);
      final targetOverlap = sharedTokens.length / targetTokens.length;
      final candidateOverlap = sharedTokens.length / candidateTokens.length;

      if (targetTokens.length == 1) {
        if (!normalizedTitle.startsWith('$targetNormalized ') ||
            candidateTokens.length > 3) {
          continue;
        }
      } else if (targetOverlap < 0.5 && candidateOverlap < 0.6) {
        continue;
      }

      addCandidateAlias(cleanTitle);
      if (aliases.length >= 4) break;
    }

    return aliases;
  }

  static List<String> _buildQueryVariants(
      String query, {
        List<String> additionalTargetNames = const <String>[],
        List<String> additionalLocalities = const <String>[],
      }) {
    final rawParts = query
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (rawParts.isEmpty) return <String>[];

    final parts = <String>[];
    final seenParts = <String>{};
    for (var index = 0; index < rawParts.length; index++) {
      final part = rawParts[index];
      final key = _normalise(part);
      if (key.isEmpty) continue;
      if (index > 0 && key == _normalise(rawParts.first)) continue;
      if (seenParts.add(key)) parts.add(part);
    }

    final canonicalQuery = parts.join(', ');
    final variants = <String>[canonicalQuery];

    // If a context part ends with " City" (e.g. "New York City", "Mexico City",
    // "Ho Chi Minh City"), also build a query with the base city name ("New York")
    // because many OpenStreetMap addresses omit the word "City".
    final strippedCityParts = parts.map((part) {
      if (part == parts.first) return part;
      if (_normalise(part) == 'vatican city') return part;
      final stripped = part
          .replaceFirst(RegExp(r'\s+city$', caseSensitive: false), '')
          .trim();
      return stripped.isNotEmpty ? stripped : part;
    }).toList();
    final strippedCityQuery = strippedCityParts.join(', ');
    if (strippedCityQuery.toLowerCase() != canonicalQuery.toLowerCase()) {
      variants.add(strippedCityQuery);
    }

    // For 4+ part queries like "[Place, City, Region, Country]", also build
    // "[Place, City, Country]" and "[Place, City]" without the broad region.
    if (strippedCityParts.length >= 4) {
      variants.add(
        <String>[
          strippedCityParts.first,
          strippedCityParts[1],
          strippedCityParts.last,
        ].join(', '),
      );
      variants.add(
        <String>[
          strippedCityParts.first,
          strippedCityParts[1],
        ].join(', '),
      );
    }

    if (parts.length >= 3) {
      variants.add(<String>[parts.first, ...parts.skip(2)].join(', '));
      variants.add(parts.take(parts.length - 1).join(', '));
    }

    final contextWithCountry = strippedCityParts.length >= 4
        ? '${strippedCityParts[1]}, ${strippedCityParts.last}'
        : strippedCityParts.skip(1).join(', ');
    final contextWithoutCountry = strippedCityParts.length >= 3
        ? strippedCityParts[1]
        : contextWithCountry;

    final allTargetAlternatives = <String>{
      ..._buildTargetNameAlternatives(parts.first),
      ...additionalTargetNames,
    }.take(6).toList();
    final seenTargetAlternatives = <String>{};

    final seenLocalities = <String>{};
    for (final rawLocality in additionalLocalities.take(2)) {
      final locality = rawLocality.trim();
      final localityKey = _normalise(locality);
      if (locality.isEmpty ||
          localityKey.isEmpty ||
          !seenLocalities.add(localityKey) ||
          strippedCityParts.any((part) => _normalise(part) == localityKey)) {
        continue;
      }

      final localityParts = <String>[
        parts.first,
        locality,
        ...strippedCityParts.skip(1),
      ];
      final seenLocalityParts = <String>{};
      final localityQuery = localityParts
          .where((part) => seenLocalityParts.add(_normalise(part)))
          .join(', ');
      variants.add(localityQuery);

      for (final rawAlternative in allTargetAlternatives) {
        final alternative = rawAlternative.trim();
        if (alternative.isEmpty ||
            _normalise(alternative) == _normalise(parts.first)) {
          continue;
        }
        final alternativeParts = <String>[
          alternative,
          locality,
          ...strippedCityParts.skip(1),
        ];
        final seenAlternativeParts = <String>{};
        variants.add(
          alternativeParts
              .where((part) => seenAlternativeParts.add(_normalise(part)))
              .join(', '),
        );
      }
    }

    for (final rawAlternative in allTargetAlternatives) {
      final alternative = rawAlternative.trim();
      final alternativeKey = _normalise(alternative);
      if (alternative.isEmpty ||
          alternativeKey.isEmpty ||
          alternativeKey == _normalise(parts.first) ||
          !seenTargetAlternatives.add(alternativeKey)) {
        continue;
      }

      if (contextWithCountry.isNotEmpty) {
        variants.add('$alternative, $contextWithCountry');
      }
      if (contextWithoutCountry.isNotEmpty) {
        variants.add('$alternative, $contextWithoutCountry');
      }
      variants.add(alternative);
    }

    variants.add(parts.first);

    final unique = <String>[];
    final seen = <String>{};
    for (final variant in variants) {
      final cleaned = variant.trim();
      final key = cleaned.toLowerCase();
      if (cleaned.isNotEmpty && seen.add(key)) unique.add(cleaned);
    }
    return unique.take(12).toList();
  }

  /// Strips royal ceremonial temple suffixes, normalizes singular/plural
  /// natural features, and expands common global & Southeast Asian variants.
  static final RegExp _thaiCeremonialSuffixes = RegExp(
    r'\b(ratchawararam|ratchaworamahawihan|ratchawaramahawihan|'
    r'ratchawarawihan|ratchaworawihan|woramahawihan|worawihan|'
    r'warawihan|varavihara|mahawihan|ratcha\s+wora\s+maha\s+wihan|'
    r'ratcha\s+woramahawihan|racha\s+worawihan)\b',
    caseSensitive: false,
  );

  static List<String> _buildTargetNameAlternatives(String targetName) {
    final alternatives = <String>[];
    final simplified = targetName.trim();
    final normalizedTarget = _normalise(simplified);

    // 1. Strip Thai royal temple ceremonial suffixes
    final withoutRoyalSuffix = simplified
        .replaceAll(_thaiCeremonialSuffixes, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (withoutRoyalSuffix.isNotEmpty &&
        withoutRoyalSuffix.length >= 4 &&
        _normalise(withoutRoyalSuffix) != normalizedTarget) {
      alternatives.add(withoutRoyalSuffix);
    }

    // 2. Strip trailing hospitality, meal, or brand modifiers
    // e.g. "Sala Rattanakosin Eatery And Bar" -> "Sala Rattanakosin"
    // e.g. "Upper East Side Dinner" -> "Upper East Side"
    // e.g. "Nathan's Famous" -> "Nathan's"
    final withoutVenueSuffix = simplified
        .replaceFirst(
      RegExp(
        r'\s+(eatery\s+and\s+bar|restaurant\s+and\s+bar|bar\s+and\s+restaurant|'
        r'bar\s+and\s+grill|rooftop\s+bar|sky\s+bar|beach\s+club|'
        r'jazz\s+club|comedy\s+club|night\s+club|nightclub|'
        r'eatery|restaurant|restaurants|bistro|bar|bars|cafe|cafes|coffee|'
        r'dinner|lunch|brunch|breakfast|food\s+tour|food\s+crawl|street\s+food|'
        r'resort\s+and\s+spa|famous)$',
        caseSensitive: false,
      ),
      '',
    )
        .trim();
    if (withoutVenueSuffix.isNotEmpty &&
        withoutVenueSuffix.length >= 4 &&
        _normalise(withoutVenueSuffix) != normalizedTarget) {
      alternatives.add(withoutVenueSuffix);
    }

    // 3. Strip trailing natural-feature, architectural-walk, observation, or tour descriptors
    // e.g. "Harlem Brownstones" -> "Harlem"
    // e.g. "Edge Observation Deck" -> "Edge"
    // e.g. "Bor Thor Mangrove Forest" -> "Bor Thor"
    final withoutDescriptorSuffix = simplified
        .replaceFirst(
      RegExp(
        r'\s+(mangrove\s+forest|mangrove|forest\s+park|forest|nature\s+reserve|'
        r'observation\s+deck|viewing\s+deck|sky\s+deck|skydeck|observatory|'
        r'brownstones|brownstone|architecture|street\s+art|murals|'
        r'shopping|boutiques|nightlife|stroll|walk|walking\s+tour|'
        r'fire\s+show|cabaret\s+show|cultural\s+show|show|island\s+tour|'
        r'islands\s+tour|boat\s+tour|day\s+tour|tour|excursion|cruise)$',
        caseSensitive: false,
      ),
      '',
    )
        .trim();
    if (withoutDescriptorSuffix.isNotEmpty &&
        _normalise(withoutDescriptorSuffix) != normalizedTarget &&
        !const {'four', '4', 'five', '5', 'seven', '7', 'three', '3', 'half', 'full', 'one'}
            .contains(_normalise(withoutDescriptorSuffix))) {
      alternatives.add(withoutDescriptorSuffix);
    }

    // 4. Handle "<Street/City> <Type> District" (e.g. "Broadway Theater District" ->
    // "Theater District", "Theatre District", "Broadway")
    final districtMatch = RegExp(
      r'^(.+?)\s+((?:theater|theatre|historic|financial|art|arts|design|fashion|meatpacking|garment|diamond|red\s+light)\s+district)$',
      caseSensitive: false,
    ).firstMatch(simplified);
    if (districtMatch != null) {
      final prefix = districtMatch.group(1)!.trim();
      final districtCore = districtMatch.group(2)!.trim();
      alternatives.add(districtCore);
      if (districtCore.toLowerCase().contains('theater')) {
        alternatives.add(
          districtCore.replaceAll(
            RegExp(r'theater', caseSensitive: false),
            'Theatre',
          ),
        );
      } else if (districtCore.toLowerCase().contains('theatre')) {
        alternatives.add(
          districtCore.replaceAll(
            RegExp(r'theatre', caseSensitive: false),
            'Theater',
          ),
        );
      }
      if (prefix.length >= 4) alternatives.add(prefix);
    }

    // 5. Global British <-> American & Saint/Mount spelling equivalents
    if (RegExp(r'\btheater\b', caseSensitive: false).hasMatch(simplified)) {
      alternatives.add(
        simplified.replaceAll(
          RegExp(r'\btheater\b', caseSensitive: false),
          'Theatre',
        ),
      );
    } else if (RegExp(r'\btheatre\b', caseSensitive: false).hasMatch(simplified)) {
      alternatives.add(
        simplified.replaceAll(
          RegExp(r'\btheatre\b', caseSensitive: false),
          'Theater',
        ),
      );
    }
    if (RegExp(r'\bcenter\b', caseSensitive: false).hasMatch(simplified)) {
      alternatives.add(
        simplified.replaceAll(
          RegExp(r'\bcenter\b', caseSensitive: false),
          'Centre',
        ),
      );
    } else if (RegExp(r'\bcentre\b', caseSensitive: false).hasMatch(simplified)) {
      alternatives.add(
        simplified.replaceAll(
          RegExp(r'\bcentre\b', caseSensitive: false),
          'Center',
        ),
      );
    }
    if (RegExp(r'\bst\.?\s+', caseSensitive: false).hasMatch(simplified)) {
      alternatives.add(
        simplified.replaceAll(
          RegExp(r'\bst\.?\s+', caseSensitive: false),
          'Saint ',
        ),
      );
    } else if (RegExp(r'\bsaint\s+', caseSensitive: false).hasMatch(simplified)) {
      alternatives.add(
        simplified.replaceAll(
          RegExp(r'\bsaint\s+', caseSensitive: false),
          'St. ',
        ),
      );
    }
    if (RegExp(r'\bmt\.?\s+', caseSensitive: false).hasMatch(simplified)) {
      alternatives.add(
        simplified.replaceAll(
          RegExp(r'\bmt\.?\s+', caseSensitive: false),
          'Mount ',
        ),
      );
    } else if (RegExp(r'\bmount\s+', caseSensitive: false).hasMatch(simplified)) {
      alternatives.add(
        simplified.replaceAll(
          RegExp(r'\bmount\s+', caseSensitive: false),
          'Mt ',
        ),
      );
    }

    // 6. "Phra That" <-> "Phrathat" (keep "Wat" attached)
    for (final base in <String>{simplified, withoutRoyalSuffix}) {
      if (RegExp(r'\bphra\s+that\b', caseSensitive: false).hasMatch(base)) {
        final merged = base
            .replaceAll(
          RegExp(r'\bphra\s+that\b', caseSensitive: false),
          'Phrathat',
        )
            .trim();
        alternatives.add(merged);

        final withoutPhraThat = base
            .replaceAll(RegExp(r'\bphra\s+that\s+', caseSensitive: false), '')
            .trim();
        if (withoutPhraThat.isNotEmpty) {
          alternatives.add(withoutPhraThat);
        }
      }
    }

    // 7. Singular / plural normalization for natural features
    // "<Name> Gallery" <-> "Galleria degli <Name>", "Galleria <Name>", "Galerie <Name>"
    final galleryMatch = RegExp(
      r'^(.+?)\s+gallery$',
      caseSensitive: false,
    ).firstMatch(simplified);
    if (galleryMatch != null) {
      final core = galleryMatch.group(1)!.trim();
      alternatives.add('Galleria degli $core');
      alternatives.add('Galleria $core');
      alternatives.add('Galerie $core');
      alternatives.add(core);
    }

    // Cathedrals / Duomo / Global Landmarks
    if (normalizedTarget.startsWith('duomo di ') ||
        normalizedTarget.endsWith(' cathedral') ||
        normalizedTarget.startsWith('cathedral of ')) {
      alternatives.addAll(const ['Piazza del Duomo', 'Cattedrale', 'Duomo']);
      if (normalizedTarget.contains('firenze') ||
          normalizedTarget.contains('florence')) {
        alternatives.add('Santa Maria del Fiore');
      }
    }
    if (normalizedTarget.contains('vatican museum')) {
      alternatives.addAll(const ['Musei Vaticani', 'Vatican Museums']);
    }
    if (normalizedTarget.contains('peter') &&
        normalizedTarget.contains('basilica')) {
      alternatives.addAll(const [
        'Basilica di San Pietro',
        'San Pietro in Vaticano',
        'Piazza San Pietro',
      ]);
    }
    if (normalizedTarget.contains('aventine keyhole')) {
      alternatives.addAll(const [
        'Piazza dei Cavalieri di Malta',
        'The Hole of Rome',
        'Aventine Hill',
      ]);
    }

    // Japanese temples & shrines ("Senso-ji Temple" -> "Senso-ji", "Sensoji";
    // "Fushimi Inari Shrine" -> "Fushimi Inari Taisha", "Fushimi Inari")
    if (RegExp(r'\b(temple|shrine|castle|park|market|crossing)$', caseSensitive: false)
        .hasMatch(simplified)) {
      final withoutKindWord = simplified
          .replaceFirst(
        RegExp(r'\s+(temple|shrine|castle|park|market|crossing)$', caseSensitive: false),
        '',
      )
          .trim();
      if (withoutKindWord.length >= 4) {
        alternatives.add(withoutKindWord);
        if (simplified.toLowerCase().endsWith(' shrine')) {
          alternatives.add('$withoutKindWord Taisha');
          alternatives.add('$withoutKindWord Jingu');
          alternatives.add('$withoutKindWord Jinja');
        }
      }
    }

    // 7. Singular / plural normalization for natural features & museums
    if (RegExp(
      r'\b(waterfalls|caves|islands|beaches|mountains|gardens|canals|springs|pools|museums)$',
      caseSensitive: false,
    ).hasMatch(simplified)) {
      final singular = simplified.substring(0, simplified.length - 1).trim();
      alternatives.add(singular);
      if (singular.toLowerCase().endsWith(' waterfall')) {
        final core =
        singular.substring(0, singular.length - ' waterfall'.length).trim();
        if (core.isNotEmpty) {
          alternatives.add('Nam Tok $core');
          alternatives.add('Namtok $core');
        }
      }
    }

    // 8. Common global & Southeast Asian transliteration equivalents
    if (normalizedTarget.contains('harlem jazz')) {
      alternatives.addAll(const [
        'National Jazz Museum in Harlem',
        'Harlem',
      ]);
    }
    if (normalizedTarget.contains('four islands') ||
        normalizedTarget.contains('four island') ||
        normalizedTarget.contains('4 islands') ||
        normalizedTarget.contains('4 island')) {
      alternatives.addAll(const [
        'Ko Poda',
        'Poda',
        'Ao Nang Beach',
        'Ko Thap',
      ]);
    }
    if (normalizedTarget.contains('seven islands') ||
        normalizedTarget.contains('7 islands')) {
      alternatives.addAll(const [
        'Ko Poda',
        'Ao Nang Beach',
      ]);
    }
    if (normalizedTarget.contains('hong islands') ||
        normalizedTarget.contains('hong island')) {
      alternatives.addAll(const [
        'Ko Hong',
        'Koh Hong',
      ]);
    }
    if (normalizedTarget.contains('bua thong') ||
        normalizedTarget.contains('bua tong') ||
        normalizedTarget.contains('buatong')) {
      alternatives.addAll(const [
        'Bua Thong Waterfall',
        'Buatong Waterfall',
        'Namtok Bua Thong',
        'Nam Tok Bua Thong',
        'Namtok Bua Thong-Nam Phu Chet Si National Park',
      ]);
    }
    if (normalizedTarget.contains('bor thor') ||
        normalizedTarget.contains('bo tho')) {
      alternatives.addAll(const [
        'Bo Tho',
        'Ban Bo Tho',
        'Ao Thalane',
        'Tha Lane Bay',
      ]);
    }
    if (normalizedTarget.contains('lok moli')) {
      alternatives.add(
        simplified.replaceAll(
          RegExp(r'lok\s+moli', caseSensitive: false),
          'Lok Molee',
        ),
      );
    }
    if (normalizedTarget.contains('phra phrom')) {
      final rest = simplified
          .replaceFirst(RegExp(r'^phra\s+phrom\s*', caseSensitive: false), '')
          .trim();
      if (rest.isNotEmpty) {
        alternatives.add('$rest Shrine');
        alternatives.add(rest);
      }
      alternatives.add('Erawan Shrine');
      alternatives.add('Thao Maha Phrom Shrine');
    }
    if (normalizedTarget == 'phra borom maha ratchawang') {
      alternatives.addAll(const ['The Grand Palace', 'Grand Palace']);
    }
    if (normalizedTarget == 'tham phaya nak' ||
        normalizedTarget == 'phaya nak cave') {
      alternatives.addAll(const ['Viking Cave', 'Tham Phaya Nak']);
    }
    if (normalizedTarget == 'ko phai' ||
        normalizedTarget == 'koh phai' ||
        normalizedTarget == 'ko mai phai' ||
        normalizedTarget == 'koh mai phai' ||
        normalizedTarget == 'bamboo island') {
      alternatives.addAll(const [
        'Bamboo Island',
        'Ko Mai Phai',
        'Ko Mai Pai',
        'Koh Mai Phai',
        'Ko Pai',
      ]);
    }
    if (normalizedTarget == 'emerald pool' ||
        normalizedTarget == 'sa morakot') {
      alternatives.addAll(const ['Sa Morakot', 'Emerald Pool']);
    }
    if (normalizedTarget == 'tiger cave temple' ||
        normalizedTarget == 'wat tham suea') {
      alternatives.addAll(const [
        'Wat Tham Suea',
        'Tiger Cave Mountain Temple',
      ]);
    }
    if (normalizedTarget == 'bhubing palace gardens') {
      alternatives.add('Bhubing Palace');
    }
    if (normalizedTarget.contains('promthep cape') ||
        normalizedTarget.contains('phromthep cape') ||
        normalizedTarget.contains('laem phrom thep')) {
      alternatives.addAll(const [
        'Phromthep Cape',
        'Laem Phrom Thep',
        'Laem Phromthep',
      ]);
    }
    if (normalizedTarget.contains('su dok gate') ||
        normalizedTarget.contains('suan dok gate')) {
      alternatives.add('Suan Dok Gate');
    }
    if (normalizedTarget == 'thonburi canals' ||
        normalizedTarget == 'thonburi canal') {
      alternatives.addAll(const [
        'Bangkok Yai Canal',
        'Khlong Bangkok Yai',
      ]);
    }

    // 9. Koh <-> Ko prefix variants
    for (final base in <String>{simplified, withoutDescriptorSuffix}) {
      final normBase = _normalise(base);
      if (RegExp(r'^koh\s+', caseSensitive: false).hasMatch(base)) {
        final tail =
        base.replaceFirst(RegExp(r'^koh\s+', caseSensitive: false), '').trim();
        alternatives.add('Ko $tail');
        alternatives.add(tail);
      } else if (RegExp(r'^ko\s+', caseSensitive: false).hasMatch(base)) {
        final tail =
        base.replaceFirst(RegExp(r'^ko\s+', caseSensitive: false), '').trim();
        alternatives.add('Koh $tail');
        alternatives.add(tail);
      } else if (normBase.startsWith('phi phi')) {
        alternatives.add('Ko $base');
        alternatives.add('Koh $base');
        if (normBase == 'phi phi') {
          alternatives.add('Ko Phi Phi Don');
        }
      }
    }

    final withoutArea = simplified
        .replaceFirst(
      RegExp(r'\s+(area|region)$', caseSensitive: false),
      '',
    )
        .trim();
    if (withoutArea.isNotEmpty &&
        _normalise(withoutArea) != normalizedTarget) {
      alternatives.add(withoutArea);
    }

    final withoutCave = simplified
        .replaceFirst(
      RegExp(r'\bcave\s+beach\b', caseSensitive: false),
      'Beach',
    )
        .trim();
    if (withoutCave.toLowerCase() != simplified.toLowerCase()) {
      alternatives.add(withoutCave);
    }

    final withoutViewpoint = simplified
        .replaceFirst(
      RegExp(r'\s+(view\s*point|viewpoint|lookout|promenade)$', caseSensitive: false),
      '',
    )
        .trim();
    if (withoutViewpoint.isNotEmpty &&
        withoutViewpoint.toLowerCase() != simplified.toLowerCase()) {
      alternatives.add(withoutViewpoint);
    }

    final oldCityMatch = RegExp(
      r'\b(old\s+city|old\s+town)\b',
      caseSensitive: false,
    ).firstMatch(simplified);
    if (oldCityMatch != null && oldCityMatch.start > 0) {
      final phrase = simplified.substring(oldCityMatch.start).trim();
      alternatives.add(phrase);
      alternatives.add('The $phrase');
    }

    return alternatives
        .map((v) => v.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  static _GeographicContext _extractGeographicContext(
      String query,
      String? countryCode,
      ) {
    final parts = query
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.length <= 1) {
      return const _GeographicContext(
        contextParts: [],
        localityParts: [],
      );
    }

    final targetName = _normalise(parts.first);
    final seenContextParts = <String>{};
    final contextParts = parts
        .skip(1)
        .where((part) => !_isCountryContextPart(part, countryCode))
        .where((part) => _normalise(part) != targetName)
        .where((part) => seenContextParts.add(_normalise(part)))
        .toList();
    final localityParts = contextParts
        .where((part) => !_isBroadAdministrativeContext(part))
        .toList();

    return _GeographicContext(
      contextParts: contextParts,
      localityParts: localityParts,
    );
  }

  static bool _isCountryContextPart(String part, String? countryCode) {
    final normalisedPart = _normalise(part);
    final expectedAliases =
    _countryAliasesByCode[countryCode?.trim().toLowerCase() ?? ''];

    if (expectedAliases != null &&
        expectedAliases.any((alias) => _normalise(alias) == normalisedPart)) {
      return true;
    }
    if (countryCode != null &&
        normalisedPart == _normalise(countryCode.trim())) {
      return true;
    }

    return _normalizedCountryAliases.contains(normalisedPart);
  }

  static bool _isBroadAdministrativeContext(String value) {
    var normalised = _normalise(value);
    normalised = normalised
        .replaceAll(RegExp(r'\b(city municipality|town municipality)\b'), ' ')
        .replaceAll(RegExp(r'\b(municipality of|municipality|city|town)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return RegExp(
      r'\b(district|subdistrict|province|state|region|county|prefecture|'
      r'governorate|department|territory|administrative area)\b',
    ).hasMatch(normalised);
  }

  static bool _candidateMatchesGeographicContext({
    required Map<String, dynamic> candidate,
    required LatLngResult result,
    required _GeographicContext context,
  }) {
    if (!context.hasContext) return true;

    final address = candidate['address'] is Map
        ? Map<String, dynamic>.from(candidate['address'] as Map)
        : <String, dynamic>{};
    final nameDetails = candidate['namedetails'];
    final nameDetailValues = nameDetails is Map
        ? nameDetails.values.whereType<String>().join(' ')
        : '';
    final locationText = _normalise(
      '${result.displayName ?? ''} ${result.name ?? ''} '
          '${address.values.join(' ')} $nameDetailValues',
    );

    final preferredLocality = context.anchorLocality;
    final referenceParts = <String>{
      if (preferredLocality != null) preferredLocality,
      ...context.localityParts,
      ...context.contextParts,
    };

    for (final part in referenceParts) {
      for (final alias in _localityNameVariants(part)) {
        if (_containsNormalizedPhrase(locationText, alias)) return true;
      }
    }
    return false;
  }

  /// Expands city/region names so "<Name> City" (e.g. "New York City",
  /// "Mexico City", "Ho Chi Minh City", "Taipei City") also matches "<Name>"
  /// in OpenStreetMap address fields.
  static List<String> _localityNameVariants(String locality) {
    final variants = <String>{locality.trim()};
    final normalised = _normalise(locality);
    variants.add(normalised);

    if (normalised.startsWith('koh ')) {
      variants.add(normalised.replaceFirst(RegExp(r'^koh\s+'), 'ko '));
    } else if (normalised.startsWith('ko ')) {
      variants.add(normalised.replaceFirst(RegExp(r'^ko\s+'), 'koh '));
    }

    final withoutAdminSuffix = normalised
        .replaceFirst(
      RegExp(
        r'\s+(city\s+municipality|town\s+municipality|metropolitan\s+area|'
        r'special\s+ward|municipality|province|prefecture|district|'
        r'subdistrict|county|island|city|town)$',
      ),
      '',
    )
        .trim();
    if (withoutAdminSuffix.isNotEmpty && withoutAdminSuffix.length >= 3) {
      variants.add(withoutAdminSuffix);
    }

    if (normalised == 'new york city' || normalised == 'nyc') {
      variants.addAll(const [
        'new york',
        'manhattan',
        'brooklyn',
        'queens',
        'bronx',
        'staten island',
      ]);
    }

    const bilingualCities = <String, List<String>>{
      'rome': ['roma', 'vatican', 'vaticano', 'citta del vaticano'],
      'roma': ['rome', 'vatican', 'vaticano', 'citta del vaticano'],
      'vatican city': ['vatican', 'vaticano', 'citta del vaticano', 'rome', 'roma'],
      'vatican': ['vatican city', 'vaticano', 'citta del vaticano', 'rome', 'roma'],
      'florence': ['firenze'],
      'firenze': ['florence'],
      'venice': ['venezia', 'murano', 'burano', 'lido'],
      'venezia': ['venice', 'murano', 'burano', 'lido'],
      'milan': ['milano'],
      'milano': ['milan'],
      'naples': ['napoli'],
      'napoli': ['naples'],
      'turin': ['torino'],
      'torino': ['turin'],
      'cinque terre': ['monterosso', 'vernazza', 'corniglia', 'manarola', 'riomaggiore', 'la spezia'],
      'vienna': ['wien'],
      'munich': ['muenchen', 'munchen'],
      'prague': ['praha'],
      'lisbon': ['lisboa'],
      'seville': ['sevilla'],
      'brussels': ['bruxelles'],
    };
    for (final key in <String>{normalised, withoutAdminSuffix}) {
      final matches = bilingualCities[key];
      if (matches != null) variants.addAll(matches);
    }

    return variants.where((v) => v.isNotEmpty).toList();
  }

  static const Map<String, List<String>> _countryAliasesByCode = {
    'ad': ['Andorra', 'Principality of Andorra'],
    'ae': ['United Arab Emirates', 'UAE'],
    'af': ['Afghanistan', 'Islamic Republic of Afghanistan'],
    'ag': ['Antigua and Barbuda'],
    'ai': ['Anguilla'],
    'al': ['Albania', 'Republic of Albania'],
    'am': ['Armenia', 'Republic of Armenia'],
    'ao': ['Angola', 'Republic of Angola'],
    'aq': ['Antarctica'],
    'ar': ['Argentina', 'Argentine Republic'],
    'as': ['American Samoa'],
    'at': ['Austria', 'Republic of Austria'],
    'au': ['Australia'],
    'aw': ['Aruba'],
    'ax': ['Åland Islands'],
    'az': ['Azerbaijan', 'Republic of Azerbaijan'],
    'ba': ['Bosnia and Herzegovina', 'Republic of Bosnia and Herzegovina'],
    'bb': ['Barbados'],
    'bd': ['Bangladesh', 'People\'s Republic of Bangladesh'],
    'be': ['Belgium', 'Kingdom of Belgium'],
    'bf': ['Burkina Faso'],
    'bg': ['Bulgaria', 'Republic of Bulgaria'],
    'bh': ['Bahrain', 'Kingdom of Bahrain'],
    'bi': ['Burundi', 'Republic of Burundi'],
    'bj': ['Benin', 'Republic of Benin'],
    'bl': ['Saint Barthélemy'],
    'bm': ['Bermuda'],
    'bn': ['Brunei Darussalam'],
    'bo': ['Bolivia, Plurinational State of', 'Bolivia', 'Plurinational State of Bolivia'],
    'bq': ['Bonaire, Sint Eustatius and Saba'],
    'br': ['Brazil', 'Federative Republic of Brazil'],
    'bs': ['Bahamas', 'Commonwealth of the Bahamas'],
    'bt': ['Bhutan', 'Kingdom of Bhutan'],
    'bv': ['Bouvet Island'],
    'bw': ['Botswana', 'Republic of Botswana'],
    'by': ['Belarus', 'Republic of Belarus'],
    'bz': ['Belize'],
    'ca': ['Canada'],
    'cc': ['Cocos (Keeling) Islands'],
    'cd': ['Congo, The Democratic Republic of the'],
    'cf': ['Central African Republic'],
    'cg': ['Congo', 'Republic of the Congo'],
    'ch': ['Switzerland', 'Swiss Confederation'],
    'ci': ['Côte d\'Ivoire', 'Republic of Côte d\'Ivoire'],
    'ck': ['Cook Islands'],
    'cl': ['Chile', 'Republic of Chile'],
    'cm': ['Cameroon', 'Republic of Cameroon'],
    'cn': ['China', 'People\'s Republic of China'],
    'co': ['Colombia', 'Republic of Colombia'],
    'cr': ['Costa Rica', 'Republic of Costa Rica'],
    'cu': ['Cuba', 'Republic of Cuba'],
    'cv': ['Cabo Verde', 'Republic of Cabo Verde'],
    'cw': ['Curaçao'],
    'cx': ['Christmas Island'],
    'cy': ['Cyprus', 'Republic of Cyprus'],
    'cz': ['Czechia', 'Czech Republic'],
    'de': ['Germany', 'Federal Republic of Germany'],
    'dj': ['Djibouti', 'Republic of Djibouti'],
    'dk': ['Denmark', 'Kingdom of Denmark'],
    'dm': ['Dominica', 'Commonwealth of Dominica'],
    'do': ['Dominican Republic'],
    'dz': ['Algeria', 'People\'s Democratic Republic of Algeria'],
    'ec': ['Ecuador', 'Republic of Ecuador'],
    'ee': ['Estonia', 'Republic of Estonia'],
    'eg': ['Egypt', 'Arab Republic of Egypt'],
    'eh': ['Western Sahara'],
    'er': ['Eritrea', 'the State of Eritrea'],
    'es': ['Spain', 'Kingdom of Spain'],
    'et': ['Ethiopia', 'Federal Democratic Republic of Ethiopia'],
    'fi': ['Finland', 'Republic of Finland'],
    'fj': ['Fiji', 'Republic of Fiji'],
    'fk': ['Falkland Islands (Malvinas)'],
    'fm': ['Micronesia, Federated States of', 'Federated States of Micronesia'],
    'fo': ['Faroe Islands'],
    'fr': ['France', 'French Republic'],
    'ga': ['Gabon', 'Gabonese Republic'],
    'gb': ['United Kingdom', 'United Kingdom of Great Britain and Northern Ireland', 'Great Britain', 'UK', 'England', 'Scotland'],
    'gd': ['Grenada'],
    'ge': ['Georgia'],
    'gf': ['French Guiana'],
    'gg': ['Guernsey'],
    'gh': ['Ghana', 'Republic of Ghana'],
    'gi': ['Gibraltar'],
    'gl': ['Greenland'],
    'gm': ['Gambia', 'Republic of the Gambia'],
    'gn': ['Guinea', 'Republic of Guinea'],
    'gp': ['Guadeloupe'],
    'gq': ['Equatorial Guinea', 'Republic of Equatorial Guinea'],
    'gr': ['Greece', 'Hellenic Republic'],
    'gs': ['South Georgia and the South Sandwich Islands'],
    'gt': ['Guatemala', 'Republic of Guatemala'],
    'gu': ['Guam'],
    'gw': ['Guinea-Bissau', 'Republic of Guinea-Bissau'],
    'gy': ['Guyana', 'Republic of Guyana'],
    'hk': ['Hong Kong', 'Hong Kong Special Administrative Region of China'],
    'hm': ['Heard Island and McDonald Islands'],
    'hn': ['Honduras', 'Republic of Honduras'],
    'hr': ['Croatia', 'Republic of Croatia'],
    'ht': ['Haiti', 'Republic of Haiti'],
    'hu': ['Hungary'],
    'id': ['Indonesia', 'Republic of Indonesia'],
    'ie': ['Ireland'],
    'il': ['Israel', 'State of Israel'],
    'im': ['Isle of Man'],
    'in': ['India', 'Republic of India'],
    'io': ['British Indian Ocean Territory'],
    'iq': ['Iraq', 'Republic of Iraq'],
    'ir': ['Iran, Islamic Republic of', 'Iran', 'Islamic Republic of Iran'],
    'is': ['Iceland', 'Republic of Iceland'],
    'it': ['Italy', 'Italian Republic'],
    'je': ['Jersey'],
    'jm': ['Jamaica'],
    'jo': ['Jordan', 'Hashemite Kingdom of Jordan'],
    'jp': ['Japan'],
    'ke': ['Kenya', 'Republic of Kenya'],
    'kg': ['Kyrgyzstan', 'Kyrgyz Republic'],
    'kh': ['Cambodia', 'Kingdom of Cambodia'],
    'ki': ['Kiribati', 'Republic of Kiribati'],
    'km': ['Comoros', 'Union of the Comoros'],
    'kn': ['Saint Kitts and Nevis'],
    'kp': ['Korea, Democratic People\'s Republic of', 'North Korea', 'Democratic People\'s Republic of Korea'],
    'kr': ['Korea, Republic of', 'South Korea', 'Republic of Korea'],
    'kw': ['Kuwait', 'State of Kuwait'],
    'ky': ['Cayman Islands'],
    'kz': ['Kazakhstan', 'Republic of Kazakhstan'],
    'la': ['Lao People\'s Democratic Republic', 'Laos'],
    'lb': ['Lebanon', 'Lebanese Republic'],
    'lc': ['Saint Lucia'],
    'li': ['Liechtenstein', 'Principality of Liechtenstein'],
    'lk': ['Sri Lanka', 'Democratic Socialist Republic of Sri Lanka'],
    'lr': ['Liberia', 'Republic of Liberia'],
    'ls': ['Lesotho', 'Kingdom of Lesotho'],
    'lt': ['Lithuania', 'Republic of Lithuania'],
    'lu': ['Luxembourg', 'Grand Duchy of Luxembourg'],
    'lv': ['Latvia', 'Republic of Latvia'],
    'ly': ['Libya'],
    'ma': ['Morocco', 'Kingdom of Morocco'],
    'mc': ['Monaco', 'Principality of Monaco'],
    'md': ['Moldova, Republic of', 'Moldova', 'Republic of Moldova'],
    'me': ['Montenegro'],
    'mf': ['Saint Martin (French part)'],
    'mg': ['Madagascar', 'Republic of Madagascar'],
    'mh': ['Marshall Islands', 'Republic of the Marshall Islands'],
    'mk': ['North Macedonia', 'Republic of North Macedonia'],
    'ml': ['Mali', 'Republic of Mali'],
    'mm': ['Myanmar', 'Republic of Myanmar'],
    'mn': ['Mongolia'],
    'mo': ['Macao', 'Macao Special Administrative Region of China'],
    'mp': ['Northern Mariana Islands', 'Commonwealth of the Northern Mariana Islands'],
    'mq': ['Martinique'],
    'mr': ['Mauritania', 'Islamic Republic of Mauritania'],
    'ms': ['Montserrat'],
    'mt': ['Malta', 'Republic of Malta'],
    'mu': ['Mauritius', 'Republic of Mauritius'],
    'mv': ['Maldives', 'Republic of Maldives'],
    'mw': ['Malawi', 'Republic of Malawi'],
    'mx': ['Mexico', 'United Mexican States'],
    'my': ['Malaysia'],
    'mz': ['Mozambique', 'Republic of Mozambique'],
    'na': ['Namibia', 'Republic of Namibia'],
    'nc': ['New Caledonia'],
    'ne': ['Niger', 'Republic of the Niger'],
    'nf': ['Norfolk Island'],
    'ng': ['Nigeria', 'Federal Republic of Nigeria'],
    'ni': ['Nicaragua', 'Republic of Nicaragua'],
    'nl': ['Netherlands', 'Kingdom of the Netherlands'],
    'no': ['Norway', 'Kingdom of Norway'],
    'np': ['Nepal', 'Federal Democratic Republic of Nepal'],
    'nr': ['Nauru', 'Republic of Nauru'],
    'nu': ['Niue'],
    'nz': ['New Zealand'],
    'om': ['Oman', 'Sultanate of Oman'],
    'pa': ['Panama', 'Republic of Panama'],
    'pe': ['Peru', 'Republic of Peru'],
    'pf': ['French Polynesia'],
    'pg': ['Papua New Guinea', 'Independent State of Papua New Guinea'],
    'ph': ['Philippines', 'Republic of the Philippines'],
    'pk': ['Pakistan', 'Islamic Republic of Pakistan'],
    'pl': ['Poland', 'Republic of Poland'],
    'pm': ['Saint Pierre and Miquelon'],
    'pn': ['Pitcairn'],
    'pr': ['Puerto Rico'],
    'ps': ['Palestine, State of', 'the State of Palestine'],
    'pt': ['Portugal', 'Portuguese Republic'],
    'pw': ['Palau', 'Republic of Palau'],
    'py': ['Paraguay', 'Republic of Paraguay'],
    'qa': ['Qatar', 'State of Qatar'],
    're': ['Réunion'],
    'ro': ['Romania'],
    'rs': ['Serbia', 'Republic of Serbia'],
    'ru': ['Russian Federation'],
    'rw': ['Rwanda', 'Rwandese Republic'],
    'sa': ['Saudi Arabia', 'Kingdom of Saudi Arabia'],
    'sb': ['Solomon Islands'],
    'sc': ['Seychelles', 'Republic of Seychelles'],
    'sd': ['Sudan', 'Republic of the Sudan'],
    'se': ['Sweden', 'Kingdom of Sweden'],
    'sg': ['Singapore', 'Republic of Singapore'],
    'sh': ['Saint Helena, Ascension and Tristan da Cunha'],
    'si': ['Slovenia', 'Republic of Slovenia'],
    'sj': ['Svalbard and Jan Mayen'],
    'sk': ['Slovakia', 'Slovak Republic'],
    'sl': ['Sierra Leone', 'Republic of Sierra Leone'],
    'sm': ['San Marino', 'Republic of San Marino'],
    'sn': ['Senegal', 'Republic of Senegal'],
    'so': ['Somalia', 'Federal Republic of Somalia'],
    'sr': ['Suriname', 'Republic of Suriname'],
    'ss': ['South Sudan', 'Republic of South Sudan'],
    'st': ['Sao Tome and Principe', 'Democratic Republic of Sao Tome and Principe'],
    'sv': ['El Salvador', 'Republic of El Salvador'],
    'sx': ['Sint Maarten (Dutch part)'],
    'sy': ['Syrian Arab Republic', 'Syria'],
    'sz': ['Eswatini', 'Kingdom of Eswatini'],
    'tc': ['Turks and Caicos Islands'],
    'td': ['Chad', 'Republic of Chad'],
    'tf': ['French Southern Territories'],
    'tg': ['Togo', 'Togolese Republic'],
    'th': ['Thailand', 'Kingdom of Thailand'],
    'tj': ['Tajikistan', 'Republic of Tajikistan'],
    'tk': ['Tokelau'],
    'tl': ['Timor-Leste', 'Democratic Republic of Timor-Leste'],
    'tm': ['Turkmenistan'],
    'tn': ['Tunisia', 'Republic of Tunisia'],
    'to': ['Tonga', 'Kingdom of Tonga'],
    'tr': ['Türkiye', 'Republic of Türkiye', 'Turkey'],
    'tt': ['Trinidad and Tobago', 'Republic of Trinidad and Tobago'],
    'tv': ['Tuvalu'],
    'tw': ['Taiwan, Province of China', 'Taiwan'],
    'tz': ['Tanzania, United Republic of', 'Tanzania', 'United Republic of Tanzania'],
    'ua': ['Ukraine'],
    'ug': ['Uganda', 'Republic of Uganda'],
    'um': ['United States Minor Outlying Islands'],
    'us': ['United States', 'United States of America', 'USA'],
    'uy': ['Uruguay', 'Eastern Republic of Uruguay'],
    'uz': ['Uzbekistan', 'Republic of Uzbekistan'],
    'va': ['Holy See (Vatican City State)'],
    'vc': ['Saint Vincent and the Grenadines'],
    've': ['Venezuela, Bolivarian Republic of', 'Venezuela', 'Bolivarian Republic of Venezuela'],
    'vg': ['Virgin Islands, British', 'British Virgin Islands'],
    'vi': ['Virgin Islands, U.S.', 'Virgin Islands of the United States'],
    'vn': ['Viet Nam', 'Vietnam', 'Socialist Republic of Viet Nam'],
    'vu': ['Vanuatu', 'Republic of Vanuatu'],
    'wf': ['Wallis and Futuna'],
    'ws': ['Samoa', 'Independent State of Samoa'],
    'ye': ['Yemen', 'Republic of Yemen'],
    'yt': ['Mayotte'],
    'za': ['South Africa', 'Republic of South Africa'],
    'zm': ['Zambia', 'Republic of Zambia'],
    'zw': ['Zimbabwe', 'Republic of Zimbabwe'],
  };

  static final Set<String> _normalizedCountryAliases =
  _countryAliasesByCode.values
      .expand((aliases) => aliases)
      .map(_normalise)
      .toSet();

  static Future<_ContextAnchor?> _getContextAnchor(
      String locality, {
        String? countryCode,
      }) {
    final key = '${countryCode ?? ''}:${_normalise(locality)}';
    return _contextAnchorCache.putIfAbsent(
      key,
          () => _fetchContextAnchor(locality, countryCode: countryCode),
    );
  }

  static final Map<String, Future<_ContextAnchor?>> _contextAnchorCache = {};

  static Future<_ContextAnchor?> _fetchContextAnchor(
      String locality, {
        String? countryCode,
      }) async {
    final countryName =
        _countryAliasesByCode[countryCode?.toLowerCase() ?? '']?.first;
    final anchorQuery =
    countryName == null ? locality : '$locality, $countryName';
    final candidates = await _searchCandidates(
      anchorQuery,
      countryCode: countryCode,
      preferOverpass: false,
    );
    if (candidates == null || candidates.isEmpty) return null;

    final expectedNames =
    _localityNameVariants(locality).map(_normalise).toSet();
    Map<String, dynamic>? bestCandidate;
    double bestScore = double.negativeInfinity;

    for (final candidate in candidates) {
      final result = _toLatLngResult(candidate);
      if (result == null) continue;

      final expectedCode = countryCode?.toLowerCase();
      final returnedCode = result.countryCode?.toLowerCase();
      if (expectedCode != null &&
          returnedCode != null &&
          returnedCode.isNotEmpty &&
          returnedCode != expectedCode) {
        continue;
      }

      final candidateName = _normalise(
        '${result.name ?? ''} ${result.displayName?.split(',').first ?? ''}',
      );
      var score = 0.0;
      if (expectedNames.any(
            (name) =>
        name.isNotEmpty && _containsNormalizedPhrase(candidateName, name),
      )) {
        score += 10.0;
      }
      if (_containsAny(
        '${result.category ?? ''} ${result.type ?? ''}',
        ['city', 'town', 'village', 'island', 'municipality', 'administrative'],
      )) {
        score += 2.0;
      }
      if (expectedCode != null && returnedCode == expectedCode) score += 2.0;

      if (score > bestScore) {
        bestScore = score;
        bestCandidate = candidate;
      }
    }

    if (bestCandidate == null || bestScore < 10.0) {
      return null;
    }

    final result = _toLatLngResult(bestCandidate);
    if (result == null) return null;

    return _ContextAnchor(
      latitude: result.latitude,
      longitude: result.longitude,
    );
  }

  static double _contextRadiusKm(
      String locality, {
        String? targetName,
      }) {
    final target = _normalise(targetName ?? '');
    final targetWords =
    target.split(' ').where((word) => word.isNotEmpty).toSet();
    const widerExcursionFeatures = {
      'island', 'islands', 'ko', 'koh', 'archipelago', 'bay', 'ao', 'reef',
      'cape', 'laem', 'coast', 'coastline', 'lagoon', 'beach', 'waterfall',
      'waterfalls', 'namtok', 'cave', 'tham', 'mangrove', 'pool', 'spring',
      'tour', 'tours', 'excursion', 'cruise',
    };
    if (targetWords.intersection(widerExcursionFeatures).isNotEmpty) {
      return 120.0;
    }

    const outdoorFeatures = {
      'river', 'mountain', 'peak', 'cliff', 'forest', 'hill',
      'volcano', 'national', 'park', 'reserve', 'doi',
    };
    if (targetWords.intersection(outdoorFeatures).isNotEmpty) {
      return 85.0;
    }

    final normalizedLocality = _normalise(locality);
    if (RegExp(
      r'\b(province|state|region|county|prefecture|governorate|department|territory)\b',
    ).hasMatch(normalizedLocality)) {
      return 95.0;
    }
    if (RegExp(r'\b(city|town|village|municipality)\b')
        .hasMatch(normalizedLocality)) {
      return 65.0;
    }

    return 50.0;
  }

  static double _distanceInKm(
      double latitude1,
      double longitude1,
      double latitude2,
      double longitude2,
      ) {
    const earthRadiusKm = 6371.0;
    double radians(double degrees) => degrees * math.pi / 180.0;

    final dLatitude = radians(latitude2 - latitude1);
    final dLongitude = radians(longitude2 - longitude1);
    final latitude1Radians = radians(latitude1);
    final latitude2Radians = radians(latitude2);

    final a = math.pow(math.sin(dLatitude / 2), 2) +
        math.cos(latitude1Radians) *
            math.cos(latitude2Radians) *
            math.pow(math.sin(dLongitude / 2), 2);
    final boundedA = a.clamp(0.0, 1.0).toDouble();
    return earthRadiusKm * 2 * math.asin(math.sqrt(boundedA));
  }

  static Future<List<Map<String, dynamic>>?> _searchCandidates(
      String query, {
        String? countryCode,
        bool preferOverpass = false,
        List<GeocodingAnchor> nearbyAnchors = const <GeocodingAnchor>[],
      }) async {
    if (preferOverpass) {
      final osmCandidates = await _searchOverpassCandidates(
        query,
        countryCode: countryCode,
      );
      if (osmCandidates != null && osmCandidates.isNotEmpty) {
        print(
          '🗺️ Overpass returned ${osmCandidates.length} mapped OSM candidate(s) for "$query".',
        );
        return osmCandidates;
      }
      print(
        '↪ No scoped Overpass candidates for "$query"; continuing with the existing Nominatim fallback.',
      );
    }

    List<Map<String, dynamic>> nominatimResults = const [];
    try {
      final queryParameters = <String, String>{
        'q': query.trim(),
        'format': 'jsonv2',
        'limit': '10',
        'addressdetails': '1',
        'namedetails': '1',
        'extratags': '1',
        'accept-language': 'en',
      };

      if (countryCode != null && countryCode.trim().isNotEmpty) {
        final code = countryCode.trim().toLowerCase();
        const enclaves = <String, String>{
          'it': 'it,va,sm',
          'fr': 'fr,mc,ad',
          'es': 'es,gi,ad',
          'ch': 'ch,li',
          'at': 'at,li',
          'cn': 'cn,hk,mo',
        };
        queryParameters['countrycodes'] = enclaves[code] ?? code;
      }

      // Bias Nominatim toward nearby same-day anchors using viewbox (bounded=0)
      if (nearbyAnchors.isNotEmpty) {
        final avgLat = nearbyAnchors
            .map((a) => a.latitude)
            .reduce((a, b) => a + b) /
            nearbyAnchors.length;
        final avgLon = nearbyAnchors
            .map((a) => a.longitude)
            .reduce((a, b) => a + b) /
            nearbyAnchors.length;
        const delta = 0.65; // ~70 km bias window
        queryParameters['viewbox'] =
        '${(avgLon - delta).toStringAsFixed(4)},'
            '${(avgLat + delta).toStringAsFixed(4)},'
            '${(avgLon + delta).toStringAsFixed(4)},'
            '${(avgLat - delta).toStringAsFixed(4)}';
        queryParameters['bounded'] = '0';
      }

      final uri = Uri.parse(_baseUrl).replace(
        queryParameters: queryParameters,
      );

      final response = await _rateLimitedGet(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          nominatimResults = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      } else {
        print('❌ Nominatim HTTP error ${response.statusCode} for "$query".');
      }
    } catch (e) {
      print('⚠️ Nominatim request failed for "$query": $e');
    }

    if (nominatimResults.isNotEmpty) {
      return nominatimResults;
    }

    // Fast fuzzy OSM fallback via Photon when Nominatim's strict token matching
    // returns 0 results.
    final photonResults = await _searchPhotonCandidates(
      query,
      countryCode: countryCode,
      nearbyAnchors: nearbyAnchors,
    );
    if (photonResults != null && photonResults.isNotEmpty) {
      print(
        '✨ Photon fallback returned ${photonResults.length} OSM candidate(s) for "$query".',
      );
      return photonResults;
    }

    return null;
  }

  static Future<List<Map<String, dynamic>>?> _searchPhotonCandidates(
      String query, {
        String? countryCode,
        List<GeocodingAnchor> nearbyAnchors = const <GeocodingAnchor>[],
      }) async {
    try {
      final params = <String, String>{
        'q': query.trim(),
        'limit': '8',
        'lang': 'en',
      };
      if (nearbyAnchors.isNotEmpty) {
        final avgLat = nearbyAnchors
            .map((a) => a.latitude)
            .reduce((a, b) => a + b) /
            nearbyAnchors.length;
        final avgLon = nearbyAnchors
            .map((a) => a.longitude)
            .reduce((a, b) => a + b) /
            nearbyAnchors.length;
        params['lat'] = avgLat.toStringAsFixed(5);
        params['lon'] = avgLon.toStringAsFixed(5);
      }

      final uri = Uri.parse(_photonUrl).replace(queryParameters: params);
      final response = await http
          .get(
        uri,
        headers: const {
          'User-Agent': 'journii-app/1.0 (contact@journii.app)',
          'Accept': 'application/json',
        },
      )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['features'] is! List) return null;

      final expectedCountry = countryCode?.trim().toLowerCase();
      final results = <Map<String, dynamic>>[];

      for (final rawFeature in decoded['features'] as List) {
        if (rawFeature is! Map) continue;
        final geometry = rawFeature['geometry'];
        final properties = rawFeature['properties'];
        if (geometry is! Map || properties is! Map) continue;

        final coords = geometry['coordinates'];
        if (coords is! List || coords.length < 2) continue;
        final lon = double.tryParse(coords[0].toString());
        final lat = double.tryParse(coords[1].toString());
        if (lat == null || lon == null) continue;

        final featCountryCode =
        properties['countrycode']?.toString().trim().toLowerCase();
        const enclaveMap = <String, Set<String>>{
          'it': {'it', 'va', 'sm'},
          'fr': {'fr', 'mc', 'ad'},
          'es': {'es', 'gi', 'ad'},
          'ch': {'ch', 'li'},
          'at': {'at', 'li'},
          'cn': {'cn', 'hk', 'mo'},
        };
        final allowedCountries = expectedCountry != null
            ? (enclaveMap[expectedCountry] ?? <String>{expectedCountry})
            : const <String>{};
        if (expectedCountry != null &&
            expectedCountry.isNotEmpty &&
            featCountryCode != null &&
            featCountryCode.isNotEmpty &&
            !allowedCountries.contains(featCountryCode)) {
          continue;
        }

        final name = properties['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;

        final city = properties['city']?.toString().trim();
        final state = properties['state']?.toString().trim();
        final district = properties['district']?.toString().trim();
        final county = properties['county']?.toString().trim();
        final country = properties['country']?.toString().trim();

        final displayParts = <String>[
          name,
          if (district != null && district.isNotEmpty) district,
          if (city != null && city.isNotEmpty) city,
          if (county != null && county.isNotEmpty) county,
          if (state != null && state.isNotEmpty) state,
          if (country != null && country.isNotEmpty) country,
        ];

        results.add(<String, dynamic>{
          'lat': lat.toString(),
          'lon': lon.toString(),
          'name': name,
          'display_name': displayParts.join(', '),
          'address': <String, dynamic>{
            if (city != null && city.isNotEmpty) 'city': city,
            if (state != null && state.isNotEmpty) 'state': state,
            if (county != null && county.isNotEmpty) 'county': county,
            if (country != null && country.isNotEmpty) 'country': country,
            if (featCountryCode != null && featCountryCode.isNotEmpty)
              'country_code': featCountryCode,
          },
          'namedetails': <String, dynamic>{'name': name},
          'category': properties['osm_key']?.toString().toLowerCase() ?? '',
          'type': properties['osm_value']?.toString().toLowerCase() ?? '',
          'importance': '0.5',
        });
      }

      return results;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> _searchOverpassCandidates(
      String query, {
        String? countryCode,
      }) async {
    final parts = query
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    final targetName = parts.first;
    final countryParts = parts
        .skip(1)
        .where((part) => _isCountryContextPart(part, countryCode))
        .toList();
    final countryName = countryParts.isEmpty ? null : countryParts.last;
    final rawContextParts = parts
        .skip(1)
        .where(
          (part) =>
      _normalise(part) != _normalise(targetName) &&
          !_isCountryContextPart(part, countryCode),
    )
        .toList();
    final locality = rawContextParts.isNotEmpty ? rawContextParts.last : null;

    if (locality == null || locality.trim().isEmpty) {
      return null;
    }

    final exactPattern = '^${RegExp.escape(targetName)}\$';
    final scopeSet = '.placeArea';
    final ql = StringBuffer('[out:json][timeout:10];\n');
    final localityPattern = '^${RegExp.escape(locality)}\$';

    ql.writeln('(');
    ql.writeln(
      'area["name"~"${_escapeOverpassValue(localityPattern)}",i]["boundary"="administrative"];',
    );
    ql.writeln(
      'area["name:en"~"${_escapeOverpassValue(localityPattern)}",i]["boundary"="administrative"];',
    );
    ql.writeln(')->$scopeSet;');

    ql.writeln('(');
    for (final key in const ['name', 'name:en', 'alt_name', 'short_name']) {
      ql.writeln(
        'nwr["$key"~"${_escapeOverpassValue(exactPattern)}",i](area$scopeSet);',
      );
    }
    ql.writeln(');\nout center tags;');

    try {
      final response = await _rateLimitedPost(
        Uri.parse(_overpassUrl),
        body: <String, String>{'data': ql.toString()},
      ).timeout(_overpassTimeout);
      if (response.statusCode != 200) {
        print('⚠️ Overpass HTTP ${response.statusCode} for "$query".');
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['elements'] is! List) return null;

      final candidateCountry = countryName ??
          (countryCode?.trim().isNotEmpty == true
              ? countryCode!.trim().toUpperCase()
              : null);
      final elements = (decoded['elements'] as List).whereType<Map>().toList();
      return elements
          .map(
            (element) => _overpassElementToCandidate(
          Map<String, dynamic>.from(element),
          locality: locality,
          countryName: candidateCountry,
          countryCode: countryCode,
        ),
      )
          .whereType<Map<String, dynamic>>()
          .toList();
    } on TimeoutException {
      print('⏱️ Overpass lookup timed out for "$query".');
      return null;
    } catch (error) {
      print('⚠️ Overpass lookup failed for "$query": $error');
      return null;
    }
  }

  static String _escapeOverpassValue(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ');

  static Map<String, dynamic>? _overpassElementToCandidate(
      Map<String, dynamic> element, {
        String? locality,
        String? countryName,
        String? countryCode,
      }) {
    final tags = element['tags'] is Map
        ? Map<String, dynamic>.from(element['tags'] as Map)
        : <String, dynamic>{};
    final latitude = double.tryParse(
      (element['lat'] ??
          (element['center'] is Map ? element['center']['lat'] : null))
          ?.toString() ??
          '',
    );
    final longitude = double.tryParse(
      (element['lon'] ??
          (element['center'] is Map ? element['center']['lon'] : null))
          ?.toString() ??
          '',
    );
    if (latitude == null || longitude == null) return null;

    final name = <String?>[
      tags['name']?.toString(),
      tags['name:en']?.toString(),
      tags['official_name']?.toString(),
      tags['int_name']?.toString(),
    ].whereType<String>().map((value) => value.trim()).firstWhere(
          (value) => value.isNotEmpty,
      orElse: () => '',
    );
    if (name.isEmpty) return null;

    const categoryKeys = <String>[
      'amenity', 'natural', 'waterway', 'tourism', 'historic', 'leisure',
      'shop', 'highway', 'aeroway', 'boundary', 'landuse', 'building',
      'place', 'railway', 'man_made', 'office',
    ];
    String? category;
    String? type;
    for (final key in categoryKeys) {
      final value = tags[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        category = key;
        type = value.toLowerCase();
        break;
      }
    }

    final nameDetails = <String, dynamic>{};
    for (final key in <String>[
      'name', 'name:en', 'official_name', 'official_name:en', 'int_name',
      'alt_name', 'alt_name:en', 'loc_name', 'loc_name:en', 'short_name', 'old_name',
    ]) {
      final value = tags[key]?.toString().trim();
      if (value != null && value.isNotEmpty) nameDetails[key] = value;
    }

    final address = <String, dynamic>{
      if (locality != null && locality.trim().isNotEmpty)
        'city': locality.trim(),
      if (countryName != null && countryName.trim().isNotEmpty)
        'country': countryName.trim(),
      if (countryCode != null && countryCode.trim().isNotEmpty)
        'country_code': countryCode.trim().toLowerCase(),
      if (tags['addr:city'] != null) 'addr:city': tags['addr:city'],
      if (tags['addr:state'] != null) 'state': tags['addr:state'],
      if (tags['addr:province'] != null) 'province': tags['addr:province'],
    };
    final displayParts = <String>[name];
    if (locality != null &&
        locality.trim().isNotEmpty &&
        _normalise(locality) != _normalise(name)) {
      displayParts.add(locality.trim());
    }
    if (countryName != null &&
        countryName.trim().isNotEmpty &&
        !_containsNormalizedPhrase(displayParts.join(', '), countryName)) {
      displayParts.add(countryName.trim());
    }

    return <String, dynamic>{
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'name': name,
      'display_name': displayParts.join(', '),
      'address': address,
      'namedetails': nameDetails,
      'category': category ?? '',
      'type': type ?? '',
      'importance': '0',
      'osm_type': element['type'],
      'osm_id': element['id'],
      'osm_tags': tags,
    };
  }

  static Future<http.Response> _rateLimitedPost(
      Uri uri, {
        required Map<String, String> body,
      }) async {
    final releaseQueueSlot = Completer<void>();
    final previousRequest = _requestQueue;
    _requestQueue = releaseQueueSlot.future;

    await previousRequest;
    try {
      final lastStarted = _lastRequestStartedAt;
      if (lastStarted != null) {
        final elapsed = DateTime.now().difference(lastStarted);
        final remaining = _minimumRequestInterval - elapsed;

        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
      }

      _lastRequestStartedAt = DateTime.now();
      return await http
          .post(
        uri,
        headers: const {
          'User-Agent': 'journii-app/1.0 (contact@journii.app)',
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: body,
      )
          .timeout(_overpassTimeout);
    } finally {
      releaseQueueSlot.complete();
    }
  }

  static Future<http.Response> _rateLimitedGet(Uri uri) async {
    final releaseQueueSlot = Completer<void>();
    final previousRequest = _requestQueue;
    _requestQueue = releaseQueueSlot.future;

    await previousRequest;
    try {
      final lastStarted = _lastRequestStartedAt;
      if (lastStarted != null) {
        final elapsed = DateTime.now().difference(lastStarted);
        final remaining = _minimumRequestInterval - elapsed;

        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
      }

      _lastRequestStartedAt = DateTime.now();
      return await http
          .get(
        uri,
        headers: const {
          'User-Agent': 'journii-app/1.0 (contact@journii.app)',
          'Accept': 'application/json',
        },
      )
          .timeout(const Duration(seconds: 20));
    } finally {
      releaseQueueSlot.complete();
    }
  }

  static LatLngResult? _toLatLngResult(Map<String, dynamic> candidate) {
    final latitude = double.tryParse(candidate['lat']?.toString() ?? '');
    final longitude = double.tryParse(candidate['lon']?.toString() ?? '');
    if (latitude == null || longitude == null) return null;

    final address = candidate['address'] is Map
        ? Map<String, dynamic>.from(candidate['address'] as Map)
        : <String, dynamic>{};

    final importance = double.tryParse(
      candidate['importance']?.toString() ?? '',
    );

    return LatLngResult(
      latitude: latitude,
      longitude: longitude,
      countryCode: const {'va': 'it', 'sm': 'it', 'mc': 'fr'}[
      address['country_code']?.toString().toLowerCase()] ??
          address['country_code']?.toString().toLowerCase(),
      countryName: address['country']?.toString(),
      locality: _bestLocality(address),
      region: _bestRegion(address),
      type: candidate['type']?.toString().toLowerCase(),
      displayName: candidate['display_name']?.toString(),
      category: candidate['category']?.toString().toLowerCase(),
      name: candidate['name']?.toString(),
      importance: importance,
    );
  }

  static String? _bestRegion(Map<String, dynamic> address) {
    const regionKeys = ['province', 'state', 'region'];
    for (final key in regionKeys) {
      final value = address[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Prioritizes broader city/province/district keys over tiny rural villages
  /// or hyper-local hamlets so same-day context queries for neighbouring
  /// attractions don't fail.
  static String? _bestLocality(Map<String, dynamic> address) {
    const primaryLocalityKeys = [
      'city',
      'municipality',
      'town',
      'borough',
      'island',
      'province',
      'state',
      'county',
      'state_district',
      'village',
    ];
    for (final key in primaryLocalityKeys) {
      final value = address[key]?.toString().trim();
      if (value == null || value.isEmpty) continue;
      if (key == 'village' &&
          RegExp(r'^(ban|kampung|desa)\s+', caseSensitive: false)
              .hasMatch(value)) {
        continue;
      }
      return value;
    }
    return address['village']?.toString().trim();
  }

  static bool _hasExactCandidateNameMatch(
      Map<String, dynamic> candidate,
      String targetName, {
        List<String> additionalNames = const <String>[],
      }) {
    final targets = <String>{
      _normalise(targetName),
      ...additionalNames.map(_normalise),
    }..removeWhere((e) => e.isEmpty);
    if (targets.isEmpty) return false;

    final names = <String>[];
    final primaryName = candidate['name']?.toString();
    if (primaryName != null && primaryName.trim().isNotEmpty) {
      names.add(primaryName.trim());
    }
    final nameDetails = candidate['namedetails'];
    if (nameDetails is Map) {
      names.addAll(nameDetails.values.whereType<String>());
    }
    final displayName = candidate['display_name']?.toString() ?? '';
    if (displayName.isNotEmpty) names.add(displayName.split(',').first.trim());

    return names.any((name) => targets.contains(_normalise(name)));
  }

  static bool _hasSufficientNameEvidence(
      Map<String, dynamic> candidate,
      String targetName, {
        List<String> additionalNames = const <String>[],
      }) {
    final target = _normalise(targetName);
    if (target.isEmpty) return false;

    final names = <String>[];
    final primaryName = candidate['name']?.toString();
    if (primaryName != null && primaryName.trim().isNotEmpty) {
      names.add(primaryName.trim());
    }
    final nameDetails = candidate['namedetails'];
    if (nameDetails is Map) {
      names.addAll(nameDetails.values.whereType<String>());
    }
    final displayName = candidate['display_name']?.toString() ?? '';
    if (displayName.isNotEmpty) {
      final segments = displayName.split(',');
      names.add(segments.first.trim());
      if (segments.length >= 2) {
        names.add('${segments[0].trim()} ${segments[1].trim()}');
      }
    }

    final normalisedNames = names
        .map(_normalise)
        .where((name) => name.isNotEmpty)
        .toSet();
    final directNameMatch = normalisedNames.any(
          (name) => name == target || name.startsWith('$target '),
    );

    final additionalNormalizedNames = additionalNames
        .map(_normalise)
        .where((name) => name.isNotEmpty)
        .toSet();
    final mappedAliasMatches = additionalNormalizedNames.any(
          (alias) => normalisedNames.any(
            (name) =>
        name == alias ||
            name.startsWith('$alias ') ||
            alias.startsWith('$name '),
      ),
    );

    final kind = _expectedKind(targetName);
    final words = target.split(' ').where((word) => word.isNotEmpty).toSet();
    const nonDistinctiveModifiers = {
      'weekend', 'famous', 'popular', 'iconic', 'scenic', 'historic',
      'historical', 'main', 'area', 'region', 'royal', 'ancient', 'national',
      'district', 'quarter', 'neighborhood', 'neighbourhood', 'brownstones',
      'brownstone', 'observation', 'deck', 'observatory', 'viewing',
    };
    const featureWords = {
      'nature': {
        'beach', 'playa', 'plage', 'pantai', 'cape', 'bay', 'baia', 'bahia',
        'island', 'islands', 'isla', 'ile', 'jima', 'shima', 'nusa', 'canal',
        'canals', 'river', 'rio', 'fleuve', 'waterfall', 'waterfalls',
        'cascada', 'cascata', 'mountain', 'mount', 'mt', 'monte', 'mont',
        'yama', 'san', 'gunung', 'jebel', 'peak', 'pinnacle', 'cliff', 'reef',
        'lagoon', 'coast', 'coastline', 'hill', 'colline', 'cave', 'grotta',
        'grotte', 'cueva', 'mangrove', 'forest', 'woods', 'pool', 'spring',
        'springs', 'onsen', 'peninsula', 'canyon', 'gorge', 'wadi', 'valley',
      },
      'religious': {
        'temple', 'wat', 'ji', 'dera', 'pagoda', 'shrine', 'jinja', 'taisha',
        'jingu', 'mosque', 'masjid', 'church', 'chiesa', 'eglise', 'iglesia',
        'kirche', 'cathedral', 'cattedrale', 'catedral', 'cathedrale',
        'monastery', 'abbey', 'abbazia', 'convento', 'sanctuary', 'santuario',
        'chedi', 'basilica', 'basilique', 'duomo', 'dom', 'synagogue',
        'mandir', 'gurudwara', 'dargah', 'pura', 'candi',
      },
      'museum': {
        'museum', 'museums', 'museo', 'musei', 'musee', 'museu', 'galerie',
        'gallery', 'galleries', 'galleria', 'gallerie', 'galeria', 'pinacoteca',
      },
      'airport': {'airport', 'airfield', 'aerodrome', 'terminal', 'aeroport', 'aeropuerto'},
      'green-space': {
        'park', 'parks', 'parco', 'parc', 'parque', 'koen', 'gyoen',
        'garden', 'gardens', 'giardino', 'giardini', 'jardin', 'jardines', 'bagh',
      },
      'market': {
        'market', 'markets', 'bazaar', 'bazar', 'souk', 'souq', 'floating',
        'mall', 'mercato', 'mercado', 'marche', 'markt', 'pasar',
      },
      'road': {
        'road', 'street', 'avenue', 'boulevard', 'soi', 'alley', 'square',
        'plaza', 'piazza', 'piazzale', 'place', 'platz', 'praca', 'promenade',
        'mile', 'bridge', 'ponte', 'pont', 'puente', 'brucke', 'crossing',
        'dori', 'via', 'rue', 'calle', 'strasse', 'ghat',
      },
      'food-business': {
        'restaurant', 'restaurants', 'ristorante', 'trattoria', 'osteria',
        'bistro', 'brasserie', 'cafe', 'cafes', 'coffee', 'bar', 'bars',
        'izakaya', 'dinner', 'lunch', 'brunch', 'breakfast', 'dining',
        'eatery', 'brewery', 'bakery', 'pasticceria', 'patisserie', 'gelateria',
      },
      'activity': {
        'cooking', 'class', 'school', 'course', 'workshop', 'sanctuary',
        'massage', 'spa', 'tour', 'tours', 'excursion', 'show', 'fire',
        'cruise', 'safari', 'club', 'stroll', 'walk', 'shopping', 'nightlife',
        'ride', 'gondola', 'tasting', 'experience',
      },
      'landmark': <String>{
        'palace', 'palazzo', 'palais', 'palacio', 'castle', 'castello',
        'chateau', 'alcazar', 'schloss', 'burg', 'jo', 'fort', 'fortress',
        'qila', 'mahal', 'tower', 'torre', 'tour', 'turm', 'gate', 'porta',
        'porte', 'puerta', 'monument', 'memorial', 'fountain', 'fontana',
        'fontaine', 'fuente', 'arch', 'arco', 'arc', 'statue', 'villa',
      },
    };

    final coreTokens = words
        .where((word) => !_isStopWord(word))
        .where((word) => !nonDistinctiveModifiers.contains(word))
        .where((word) => !(featureWords[kind] ?? <String>{}).contains(word))
        .toSet();
    final namesText = _normalise(names.join(' '));
    final nameTokens = namesText
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toSet();

    var allCoreTokensMatch = directNameMatch ||
        mappedAliasMatches ||
        (coreTokens.isNotEmpty && coreTokens.every(nameTokens.contains));

    // Match concatenated or transliterated compounds (e.g. "Bua Tong" <-> "Buatong" or "Bua Thong",
    // "Theater" <-> "Theatre", "Center" <-> "Centre")
    if (!allCoreTokensMatch && coreTokens.isNotEmpty) {
      String unifySpelling(String input) => input
          .replaceAll('thong', 'tong')
          .replaceAll('theatre', 'theater')
          .replaceAll('centre', 'center');
      final joinedCore = unifySpelling(coreTokens.join(''));
      final joinedCandidate = unifySpelling(namesText.replaceAll(' ', ''));
      if (joinedCore.length >= 5 && joinedCandidate.contains(joinedCore)) {
        allCoreTokensMatch = true;
      }
    }

    final category = (candidate['category'] ?? '').toString().toLowerCase();
    final type = (candidate['type'] ?? '').toString().toLowerCase();
    final fullLocationTokens =
    _normalise('$namesText $displayName').split(' ').toSet();

    if (!allCoreTokensMatch) {
      final nonStopWords = words.where((w) => !_isStopWord(w)).toSet();
      final allTokensInDisplay = nonStopWords.every(fullLocationTokens.contains);
      final sharedPrimaryTokens = nonStopWords.intersection(nameTokens);
      if (allTokensInDisplay &&
          (kind == 'nature' ||
              kind == 'activity' ||
              kind == 'food-business' ||
              sharedPrimaryTokens.length >= 2 ||
              (coreTokens.isNotEmpty &&
                  coreTokens.every(fullLocationTokens.contains)))) {
        allCoreTokensMatch = true;
      }
    }

    if (!allCoreTokensMatch) return false;

    const activityTerms = {
      'kayak', 'kayaking', 'canoe', 'canoeing', 'boat', 'tour', 'tours',
      'cruise', 'excursion', 'trip', 'rental', 'ticket', 'tickets', 'guide',
      'experience', 'adventure', 'transfer', 'transfers', 'transport',
      'booking', 'bookings', 'transfering',
    };
    const naturalFeatureTerms = {
      'beach', 'cape', 'bay', 'island', 'islands', 'canal', 'canals',
      'river', 'waterfall', 'waterfalls', 'mountain', 'peak', 'reef',
      'lagoon', 'cave', 'mangrove', 'forest', 'pool', 'spring', 'springs',
    };
    final primaryCandidateRawName = primaryName?.trim().isNotEmpty == true
        ? primaryName!.trim()
        : (displayName.isNotEmpty ? displayName.split(',').first : '');
    final primaryCandidateName = _normalise(primaryCandidateRawName);
    final primaryCandidateTokens = primaryCandidateName.split(' ').toSet();
    final targetActivityWords = words.intersection(activityTerms);
    if (kind == 'nature' &&
        words.intersection(naturalFeatureTerms).isNotEmpty &&
        primaryCandidateTokens.intersection(activityTerms).isNotEmpty &&
        !targetActivityWords.containsAll(
          primaryCandidateTokens.intersection(activityTerms),
        )) {
      print(
        '   🚫 Rejected activity/listing instead of natural feature: '
            '${primaryName ?? displayName.split(',').first}.',
      );
      return false;
    }

    if (kind == 'museum' &&
        nameTokens.intersection({
          'museum', 'museums', 'museo', 'musei', 'musee',
          'gallery', 'galleries', 'galleria', 'gallerie', 'galerie', 'galeria',
        }).isEmpty &&
        type != 'museum' &&
        type != 'gallery' &&
        type != 'arts_centre') {
      return false;
    }

    if ((directNameMatch || mappedAliasMatches) &&
        !_isCommercialService(category, type)) {
      return true;
    }

    final typeScore = _typeCompatibilityScore(
      expectedKind: kind,
      category: category,
      type: type,
    );
    final knownParentVenueAlias = _isKnownParentVenueAlias(
      targetName,
      normalisedNames,
      category,
      type,
    );
    if (kind != 'landmark' &&
        kind != 'activity' &&
        typeScore <= 0.0 &&
        !knownParentVenueAlias) {
      return false;
    }

    return true;
  }

  static bool _isKnownParentVenueAlias(
      String targetName,
      Set<String> candidateNames,
      String category,
      String type,
      ) {
    final normalizedTarget = _normalise(targetName);
    if (normalizedTarget == 'bhubing palace gardens') {
      final namesThemselvesMatch = candidateNames.any(
            (name) =>
        name == 'bhubing palace' || name.startsWith('bhubing palace '),
      );
      final parentVenueType = category == 'historic' ||
          category == 'tourism' ||
          type.contains('palace') ||
          type.contains('attraction');
      return namesThemselvesMatch && parentVenueType;
    }

    if (normalizedTarget == 'su dok gate flower market' ||
        normalizedTarget == 'suan dok gate flower market') {
      final gateNameMatch = candidateNames.any(
            (name) =>
        name == 'suan dok gate' ||
            name.startsWith('suan dok gate ') ||
            name == 'pratu suan dok',
      );
      final gateType = category == 'historic' ||
          type.contains('city_gate') ||
          type.contains('gate');
      return gateNameMatch && gateType;
    }

    return false;
  }

  static double _scoreCandidate({
    required Map<String, dynamic> candidate,
    required String targetName,
    required String query,
    required String? expectedCountryCode,
    List<String> additionalNames = const <String>[],
    List<GeocodingAnchor> nearbyAnchors = const <GeocodingAnchor>[],
  }) {
    final category = (candidate['category'] ?? '').toString().toLowerCase();
    final type = (candidate['type'] ?? '').toString().toLowerCase();
    final displayName = (candidate['display_name'] ?? '').toString();
    final address = candidate['address'] is Map
        ? Map<String, dynamic>.from(candidate['address'] as Map)
        : <String, dynamic>{};

    final expectedKind = _expectedKind(targetName);
    final target = _normalise(targetName);
    final targetTokens = target
        .split(' ')
        .where((token) => token.isNotEmpty && !_isStopWord(token))
        .toSet();

    final candidateNames = <String>[];
    final primaryName = candidate['name']?.toString();
    if (primaryName != null && primaryName.trim().isNotEmpty) {
      candidateNames.add(primaryName.trim());
    }

    final nameDetails = candidate['namedetails'];
    if (nameDetails is Map) {
      for (final value in nameDetails.values) {
        if (value is String && value.trim().isNotEmpty) {
          candidateNames.add(value.trim());
        }
      }
    }

    final displayFirstPart = displayName.split(',').first.trim();
    if (displayFirstPart.isNotEmpty) candidateNames.add(displayFirstPart);

    final normalisedNames = candidateNames.map((n) {
      final stripped = n.replaceAll(_thaiCeremonialSuffixes, '').trim();
      return _normalise(stripped.isEmpty ? n : stripped);
    }).toSet()
      ..addAll(candidateNames.map(_normalise));

    final candidateNameTokens = <String>{};
    for (final name in normalisedNames) {
      candidateNameTokens.addAll(
        name.split(' ').where((token) => token.isNotEmpty),
      );
    }

    var score = 0.0;
    final additionalNormalizedNames = additionalNames
        .map(_normalise)
        .where((name) => name.isNotEmpty)
        .toSet();
    final exactAliasMatch = additionalNormalizedNames.any(
      normalisedNames.contains,
    );
    final prefixAliasMatch = additionalNormalizedNames.any(
          (alias) => normalisedNames.any((name) => name.startsWith('$alias ')),
    );

    if (target.isNotEmpty && normalisedNames.contains(target)) {
      score += 10.0;
    } else if (exactAliasMatch) {
      score += 10.0;
    } else if ((target.isNotEmpty &&
        normalisedNames.any((name) => name.startsWith('$target '))) ||
        prefixAliasMatch) {
      score += 6.0;
    } else if (targetTokens.isNotEmpty) {
      final matchedTokens = targetTokens.intersection(candidateNameTokens);
      final overlap = matchedTokens.length / targetTokens.length;
      if (overlap >= 0.8) {
        score += 7.0;
      } else if (overlap >= 0.5) {
        score += 4.0;
      } else if (matchedTokens.isNotEmpty) {
        score += 2.0;
      } else {
        final joinedTarget =
        targetTokens.join('').replaceAll('thong', 'tong');
        final joinedCandidate =
        candidateNameTokens.join('').replaceAll('thong', 'tong');
        if (joinedTarget.length >= 5 &&
            joinedCandidate.contains(joinedTarget)) {
          score += 7.0;
        }
      }
    }

    final resultCountryCode = address['country_code']?.toString().toLowerCase();
    if (expectedCountryCode != null &&
        expectedCountryCode.isNotEmpty &&
        resultCountryCode == expectedCountryCode) {
      score += 2.0;
    }

    final addressCountry = _normalise(address['country']?.toString() ?? '');
    final contextParts = query
        .split(',')
        .skip(1)
        .map(_normalise)
        .where(
          (part) =>
      part.isNotEmpty &&
          part != target &&
          part != addressCountry &&
          !_isCountryContextPart(part, expectedCountryCode),
    )
        .toSet()
        .toList();
    final addressText = address.values.join(' ');
    final candidateLocationText = _normalise('$displayName $addressText');
    final matchedContextParts = contextParts
        .where(
          (part) => _localityNameVariants(part).any(
            (variant) =>
            _containsNormalizedPhrase(candidateLocationText, variant),
      ),
    )
        .length;
    if (matchedContextParts > 0) {
      score += 3.0;
      if (contextParts.length > 1 &&
          matchedContextParts == contextParts.length) {
        score += 1.0;
      }
    }

    score += _typeCompatibilityScore(
      expectedKind: expectedKind,
      category: category,
      type: type,
    );

    score += _nearbyAnchorScore(candidate, nearbyAnchors);

    final importance =
    double.tryParse(candidate['importance']?.toString() ?? '');
    if (importance != null && importance > 0.7) score += 0.25;

    return score;
  }

  static double _nearbyAnchorScore(
      Map<String, dynamic> candidate,
      List<GeocodingAnchor> anchors,
      ) {
    if (anchors.isEmpty) return 0.0;

    final latitude = double.tryParse(candidate['lat']?.toString() ?? '');
    final longitude = double.tryParse(candidate['lon']?.toString() ?? '');
    if (latitude == null || longitude == null) return 0.0;

    var nearestDistance = double.infinity;
    for (final anchor in anchors) {
      final distance = _distanceInKm(
        latitude,
        longitude,
        anchor.latitude,
        anchor.longitude,
      );
      if (distance < nearestDistance) nearestDistance = distance;
    }

    if (nearestDistance <= 5) return 6.0;
    if (nearestDistance <= 15) return 5.0;
    if (nearestDistance <= 35) return 3.0;
    if (nearestDistance <= 65) return 1.0;
    if (nearestDistance <= 100) return 0.0;
    if (nearestDistance <= 180) return -3.0;
    return -7.0;
  }

  static String _expectedKind(String placeName) {
    final text = _normalise(placeName);
    final words = text.split(' ').toSet();

    // Check excursion, neighborhood walk, and entertainment terms FIRST
    if (words.intersection({
      'cooking', 'class', 'classes', 'course', 'workshop', 'tour', 'tours',
      'excursion', 'show', 'cruise', 'safari', 'club', 'brownstones',
      'brownstone', 'stroll', 'walk', 'shopping', 'nightlife',
    }).isNotEmpty) {
      return 'activity';
    }
    if (words.intersection({
      'beach', 'cape', 'bay', 'island', 'islands', 'canal', 'canals',
      'river', 'waterfall', 'waterfalls', 'mountain', 'peak', 'pinnacle',
      'cliff', 'reef', 'lagoon', 'coast', 'coastline', 'hill', 'cave',
      'tham', 'namtok', 'mangrove', 'forest', 'pool', 'spring', 'springs',
    }).isNotEmpty ||
        text.startsWith('ko ') ||
        text.startsWith('koh ') ||
        text.startsWith('ao ') ||
        text.startsWith('doi ')) {
      return 'nature';
    }
    if (words.intersection({'airport', 'airfield', 'aerodrome'}).isNotEmpty) {
      return 'airport';
    }
    if (text.startsWith('wat ') ||
        words.intersection({
          'temple', 'pagoda', 'shrine', 'mosque', 'church',
          'cathedral', 'monastery', 'sanctuary', 'chedi', 'basilica',
          'duomo', 'synagogue',
        }).isNotEmpty) {
      return 'religious';
    }
    if (words.intersection({
      'museum', 'museums', 'museo', 'musei', 'musee',
      'gallery', 'galleries', 'galleria', 'galerie', 'galeria',
    }).isNotEmpty) {
      return 'museum';
    }
    if (words.intersection({'park', 'garden', 'gardens'}).isNotEmpty) {
      return 'green-space';
    }
    if (words.intersection({'market', 'bazaar', 'souk', 'talat'}).isNotEmpty) {
      return 'market';
    }
    if (words.intersection({'road', 'street', 'avenue', 'boulevard'}).isNotEmpty) {
      return 'road';
    }
    if (words.intersection({
      'restaurant', 'cafe', 'coffee', 'bar', 'dinner', 'lunch', 'brunch',
      'breakfast', 'dining', 'eatery', 'brewery',
    }).isNotEmpty) {
      return 'food-business';
    }
    return 'landmark';
  }

  static double _typeCompatibilityScore({
    required String expectedKind,
    required String category,
    required String type,
  }) {
    final combined = '$category $type';
    final commercialService = _isCommercialService(category, type);

    switch (expectedKind) {
      case 'nature':
        if (commercialService ||
            type == 'swimming_pool' ||
            type == 'resort' ||
            type == 'village') {
          return -10.0;
        }
        if (_containsAny(combined, [
          'natural', 'waterway', 'beach', 'bay', 'cape', 'island', 'islet',
          'peak', 'cliff', 'river', 'canal', 'mountain', 'reef', 'coastline',
          'cave', 'waterfall', 'strait', 'archipelago', 'water', 'pond',
          'national_park', 'nature_reserve', 'viewpoint', 'peninsula',
        ])) {
          return 4.0;
        }
        if (category == 'tourism' || category == 'leisure') return 1.5;
        if (category == 'place') return 1.0;
        if (category == 'amenity' || category == 'shop' || category == 'office') {
          return -10.0;
        }
        return 0.0;

      case 'religious':
        if (_containsAny(combined, [
          'place_of_worship', 'temple', 'shrine', 'monastery', 'church',
          'mosque', 'cathedral', 'pagoda',
        ])) {
          return 4.0;
        }
        if (commercialService) return -12.0;
        if (_containsAny(combined, ['historic', 'building', 'attraction', 'tourism'])) {
          return 2.0;
        }
        return -1.0;

      case 'museum':
        if (type == 'museum' || combined.contains(' museum')) return 4.0;
        if (commercialService) return -10.0;
        if (_containsAny(combined, ['historic', 'building', 'attraction'])) {
          return 1.0;
        }
        return -2.0;

      case 'airport':
        if (category == 'aeroway' ||
            _containsAny(combined, ['aerodrome', 'airport', 'terminal'])) {
          return 4.0;
        }
        return -10.0;

      case 'green-space':
        if (commercialService) return -10.0;
        if (_containsAny(combined, ['park', 'garden', 'nature_reserve', 'national_park'])) {
          return 4.0;
        }
        if (category == 'natural' || category == 'tourism') return 2.0;
        return 0.0;

      case 'market':
        if (_containsAny(combined, ['marketplace', 'market', 'bazaar', 'retail', 'mall'])) {
          return 4.0;
        }
        if (category == 'tourism' || category == 'shop' || category == 'amenity') {
          return 1.5;
        }
        return 0.0;

      case 'road':
        if (category == 'highway' ||
            _containsAny(combined, ['road', 'street', 'avenue', 'boulevard', 'pedestrian', 'square'])) {
          return 4.0;
        }
        if (category == 'place' || category == 'tourism') return 2.0;
        if (commercialService) return -6.0;
        return 0.0;

      case 'food-business':
        if (commercialService ||
            category == 'tourism' ||
            category == 'amenity' ||
            category == 'place' ||
            category == 'craft') {
          return 4.0;
        }
        return -1.0;

      case 'activity':
        if (_containsAny(combined, ['hotel', 'hostel', 'guest_house'])) {
          return -6.0;
        }
        return 3.0;

      default:
        if (_containsAny(combined, ['hotel', 'hostel', 'guest_house', 'apartment', 'motel'])) {
          return -8.0;
        }
        if (_containsAny(category, [
          'tourism', 'historic', 'leisure', 'natural', 'waterway',
          'building', 'amenity', 'boundary', 'place', 'shop', 'craft',
          'man_made', 'office', 'highway',
        ])) {
          return 2.0;
        }
        return 0.0;
    }
  }

  static bool _isCommercialService(String category, String type) {
    const serviceTypes = {
      'restaurant', 'cafe', 'fast_food', 'bar', 'pub', 'massage',
      'beauty', 'spa', 'shop', 'supermarket', 'convenience', 'hotel',
      'guest_house', 'hostel', 'office', 'travel_agency', 'car_rental',
    };

    return serviceTypes.contains(type) ||
        (category == 'shop' && type != 'mall') ||
        (category == 'office' && type != 'yes') ||
        (category == 'tourism' &&
            const {'hotel', 'hostel', 'guest_house', 'motel', 'apartment'}
                .contains(type)) ||
        (category == 'amenity' &&
            serviceTypes.contains(type) &&
            type != 'place_of_worship' &&
            type != 'theatre' &&
            type != 'library');
  }

  static bool _containsAny(String source, List<String> values) {
    return values.any((value) => source.contains(value));
  }

  static final RegExp _nonLetterOrDigit =
  RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Normalizes case, folds common international diacritics/accents, and strips
  /// apostrophes cleanly so European, Latin American, and Asian transliterations
  /// match regardless of accent marks.
  static String _normalise(String value) {
    var text = value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r"['’`´]"), '');

    const diacritics = <String, String>{
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ō': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
      'ñ': 'n', 'ç': 'c', 'ß': 'ss', 'ł': 'l',
    };
    diacritics.forEach((accented, plain) {
      if (text.contains(accented)) {
        text = text.replaceAll(accented, plain);
      }
    });

    return text
        .replaceAll(_nonLetterOrDigit, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _containsNormalizedPhrase(String source, String phrase) {
    final normalizedSource = _normalise(source);
    final normalizedPhrase = _normalise(phrase);
    if (normalizedSource.isEmpty || normalizedPhrase.isEmpty) return false;
    return normalizedSource == normalizedPhrase ||
        normalizedSource.startsWith('$normalizedPhrase ') ||
        normalizedSource.endsWith(' $normalizedPhrase') ||
        normalizedSource.contains(' $normalizedPhrase ');
  }

  static bool _isStopWord(String token) => const {
    'the', 'of', 'and', 'at', 'in', 'on', 'for', 'a', 'an', 'to',
    'di', 'del', 'della', 'dei', 'degli', 'delle', 'da', 'dal', 'dalla',
    'al', 'il', 'lo', 'la', 'le', 'gli', 'de', 'du', 'des', 'el', 'las', 'los',
  }.contains(token);
}

class LatLngResult {
  final double latitude;
  final double longitude;
  final String? countryCode;
  final String? countryName;
  final String? locality;
  final String? region;
  final String? type;
  final String? displayName;
  final String? category;
  final String? name;
  final double? importance;

  LatLngResult({
    required this.latitude,
    required this.longitude,
    this.countryCode,
    this.countryName,
    this.locality,
    this.region,
    this.type,
    this.displayName,
    this.category,
    this.name,
    this.importance,
  });
}

class _GeographicContext {
  final List<String> contextParts;
  final List<String> localityParts;

  const _GeographicContext({
    required this.contextParts,
    required this.localityParts,
  });

  bool get hasContext => contextParts.isNotEmpty;

  String? get anchorLocality {
    if (localityParts.isEmpty) return null;
    final locality = localityParts.last.trim();

    final parent = locality
        .replaceFirst(
      RegExp(
        r'\s+(old city|old town|historic center|historical center|'
        r'city center|city centre|downtown)$',
        caseSensitive: false,
      ),
      '',
    )
        .trim();
    if (parent.isNotEmpty && parent != locality) return parent;
    return locality;
  }
}

class _ContextAnchor {
  final double latitude;
  final double longitude;

  const _ContextAnchor({
    required this.latitude,
    required this.longitude,
  });
}