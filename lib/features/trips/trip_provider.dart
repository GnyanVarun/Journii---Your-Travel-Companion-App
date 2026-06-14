import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/auth_provider.dart';
import 'trip_model.dart';
import 'trip_repository.dart';
import 'trip_style.dart';

final tripProvider = StateNotifierProvider<TripNotifier, List<Trip>>((ref) {
  final userState = ref.watch(userProvider);
  return TripNotifier(userState.value);
});

class TripNotifier extends StateNotifier<List<Trip>> {
  final Box<Trip> box = Hive.box<Trip>('trips');
  final _supabase = Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSubscription;
  ValueListenable<Box<Trip>>? _hiveListenable;
  final User? currentUser;

  TripNotifier(this.currentUser) : super([]) {
    if (currentUser != null) {
      _initSafeLoad();
    }
  }

  Future<void> _initSafeLoad() async {
    await Future.delayed(Duration.zero);
    if (!mounted || currentUser == null) return;

    final keysToDelete = box.values
        .where((trip) => trip.userId != currentUser!.id)
        .map((trip) => trip.id)
        .toList();

    if (keysToDelete.isNotEmpty) {
      await box.deleteAll(keysToDelete);
    }

    if (mounted) {
      state = box.values.toList();
    }

    _startListeners();
  }

  void _startListeners() {
    _hiveListenable = box.listenable();
    _hiveListenable!.addListener(_onHiveChanged);
    _startSupabaseSync();
  }

  void _onHiveChanged() {
    if (!mounted) return;
    if (currentUser != null) {
      state = box.values
          .where((t) => t.userId == currentUser!.id)
          .toList();
    }
  }

  void _startSupabaseSync() {
    if (currentUser == null) return;

    _realtimeSubscription = _supabase
        .from('trips')
        .stream(primaryKey: ['id'])
        .eq('user_id', currentUser!.id)
        .listen((data) async {

      final cloudTrips = data.map((json) {
        final start = DateTime.parse(json['start_date']);
        final end = DateTime.parse(json['end_date']);
        final days = end.difference(start).inDays + 1;

        // ✅ SAFE PARSING
        TripStyle style = TripStyle.values.first;
        if (json['trip_style'] != null) {
          try {
            style = TripStyle.values.firstWhere(
                    (e) => e.name.toLowerCase() == json['trip_style'].toString().toLowerCase(),
                orElse: () => TripStyle.values.first
            );
          } catch (_) {}
        }

        return Trip(
          id: json['id'],
          title: json['title'],
          description: json['description'] ?? '',
          createdAt: DateTime.now(),
          startDate: start,
          endDate: end,
          durationDays: days,
          destination: json['destination'],
          userId: json['user_id'],
          curiosityLevel: json['curiosity_level'] ?? 2,
          style: style,
        );
      }).toList();

      for (final trip in cloudTrips) {
        await box.put(trip.id, trip);
      }
    }, onError: (error) {
      print("⚠️ Supabase Sync Error: $error");
    });
  }

  Future<void> addTrip(Trip trip) async {
    if (currentUser == null) return;
    final secureTrip = trip.copyWith(userId: currentUser!.id);
    await TripRepository().createTrip(secureTrip);
  }

  Future<void> updateTrip(Trip trip) async {
    await addTrip(trip);
  }

  Future<void> deleteTrip(String id) async {
    await TripRepository().deleteTrip(id);
  }

  // Fetch events specific to a tripId
  final tripItineraryProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, tripId) async {
    final response = await Supabase.instance.client
        .from('itinerary_events')
        .select('*')
        .eq('trip_id', tripId);

    return List<Map<String, dynamic>>.from(response);
  });

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _hiveListenable?.removeListener(_onHiveChanged);
    super.dispose();
  }
}