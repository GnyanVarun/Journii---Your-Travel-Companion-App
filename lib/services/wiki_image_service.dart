import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WikiImageService {
  static final Map<String, String?> _cache = {};

  static Future<String?> fetchImageUrl(String title) async {
    if (_cache.containsKey(title)) return _cache[title];

    try {
      final uri = Uri.parse(
        'https://en.wikipedia.org/w/api.php',
      ).replace(queryParameters: {
        'action': 'query',
        'titles': title,
        'prop': 'pageimages',
        'format': 'json',
        'pithumbsize': '800',
      });

      final res = await http.get(uri);

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final pages = data['query']['pages'] as Map;

      for (final page in pages.values) {
        if (page['thumbnail'] != null) {
          final url = page['thumbnail']['source'];
          _cache[title] = url;
          return url;
        }
      }

      _cache[title] = null;
      return null;
    } catch (e) {
      debugPrint('Wiki image error: $e');
      return null;
    }
  }
}
