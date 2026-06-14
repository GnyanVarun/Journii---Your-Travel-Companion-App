import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ReviewsService {
  static const String _baseUrl = 'https://api.yelp.com/v3/businesses';

  /// Fetches just the rating and review count
  static Future<ReviewSummary?> fetchReviewSummary(
      String name, double lat, double lng) async {

    final apiKey = dotenv.env['YELP_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) return null;

    try {
      final searchUri = Uri.parse(
          '$_baseUrl/search?term=$name&latitude=$lat&longitude=$lng&limit=1&radius=2000&sort_by=review_count');

      final response = await http.get(
        searchUri,
        headers: {'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final businesses = data['businesses'] as List?;

      if (businesses == null || businesses.isEmpty) return null;

      final business = businesses[0];
      return ReviewSummary(
        rating: (business['rating'] ?? 0).toDouble(),
        reviewCount: business['review_count'] ?? 0,
        url: business['url'] ?? '',
      );
    } catch (e) {
      print("Error fetching review summary: $e");
      return null;
    }
  }
}

class ReviewSummary {
  final double rating;
  final int reviewCount;
  final String url;

  ReviewSummary({
    required this.rating,
    required this.reviewCount,
    required this.url,
  });
}