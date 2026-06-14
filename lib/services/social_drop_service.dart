import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';

class SocialDropService {
  static final _supabase = Supabase.instance.client;

  // 1. Leave a Drop
  static Future<bool> createDrop({
    required LatLng location,
    required String message,
    String userName = "Me",
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    String finalName = userName;
    final meta = user.userMetadata;
    if (meta != null && meta.containsKey('display_name')) {
      final name = meta['display_name'];
      if (name != null && name.toString().trim().isNotEmpty) {
        finalName = name;
      }
    }

    try {
      await _supabase.from('geo_memories').insert({
        'user_id': user.id,
        'content': message, // Note: You use 'content' here
        'username': finalName, // Note: You use 'username' here
        'latitude': location.latitude,
        'longitude': location.longitude,
      });
      return true;
    } catch (e) {
      print("⚠️ Create Drop Error: $e");
      return false;
    }
  }

  // 2. Scan for Drops
  static Future<List<SocialDrop>> scanNearby(LatLng location) async {
    const range = 0.05;

    try {
      final response = await _supabase
          .from('geo_memories')
          .select()
          .gt('latitude', location.latitude - range)
          .lt('latitude', location.latitude + range)
          .gt('longitude', location.longitude - range)
          .lt('longitude', location.longitude + range)
          .limit(50);

      return (response as List)
          .map((json) => SocialDrop.fromJson(json)) // 🟢 NOW CALLING FROMJSON
          .toList();
    } catch (e) {
      print("⚠️ Scan Drops Error: $e");
      return [];
    }
  }

  // 3. COLLECT A MEMORY
  static Future<bool> collectMemory(String memoryId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _supabase.from('collected_memories').insert({
        'user_id': user.id,
        'memory_id': memoryId,
      });
      return true;
    } catch (e) {
      if (e.toString().contains('23505')) return true;
      print("⚠️ Collect Error: $e");
      return false;
    }
  }

  // 4. FETCH MY COLLECTION
  static Future<List<SocialDrop>> fetchMyCollection() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await _supabase
          .from('collected_memories')
          .select('*, geo_memories(*)')
          .eq('user_id', user.id)
          .order('collected_at', ascending: false);

      return (response as List).map((item) {
        final memoryData = item['geo_memories'];
        return SocialDrop.fromJson(memoryData); // 🟢 NOW CALLING FROMJSON
      }).toList();
    } catch (e) {
      print("⚠️ Fetch Collection Error: $e");
      return [];
    }
  }

  // 5. GET COLLECTED IDS
  static Future<List<String>> getCollectedDropIds() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await Supabase.instance.client
          .from('collected_memories')
          .select('memory_id')
          .eq('user_id', user.id);

      final List<String> ids = (response as List)
          .map((item) => item['memory_id'] as String)
          .toList();

      return ids;
    } catch (e) {
      debugPrint('⚠️ Error fetching collected memories: $e');
      return [];
    }
  }
}

// 🟢 THE FIXED MODEL
class SocialDrop {
  final String id;
  final String message;
  final String userName;
  final LatLng location;
  final String userId;

  SocialDrop({
    required this.id,
    required this.message,
    required this.userName,
    required this.location,
    required this.userId,
  });

  // 🟢 Renamed to fromJson to match how you call it!
  // Also updated the map keys to match what you insert in 'createDrop'
  factory SocialDrop.fromJson(Map<String, dynamic> json) {
    return SocialDrop(
      id: json['id'].toString(),
      message: json['content'] ?? '', // Match your 'content' insert key
      location: LatLng((json['latitude'] as num).toDouble(), (json['longitude'] as num).toDouble()),
      userName: json['username'] ?? 'Unknown Traveler', // Match your 'username' insert key
      userId: json['user_id']?.toString() ?? '', // Match your 'user_id' insert key
    );
  }
}