import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import your existing models and providers
import '../features/trips/itinerary_item_model.dart';
import '../features/trips/itinerary_provider.dart';
//import '../features/trips/nhost_trip_repository.dart'; // You will add this later!

class NhostSyncService {

  // 🔄 SYNC EVERYTHING FROM NHOST
  // We pass the GraphQLClient in so it can talk to your configured Nhost backend
  static Future<void> syncAll(WidgetRef ref, GraphQLClient gqlClient) async {
    print("☁️ STARTING NHOST MASTER SYNC...");

    // 1. Sync TRIPS
    // TODO: Create an Nhost version of TripRepository to parallel your Supabase one
    // await NhostTripRepository().syncFromCloud(gqlClient);

    // 2. Sync ITINERARY ITEMS from Nhost
    // Notice how we don't need to pass a user_id here!
    // Because of the Hasura Permissions we set up, Nhost automatically filters this for the logged-in user.
    const String getItineraryQuery = """
      query GetMyItineraryItems {
        itinerary_items {
          id
          trip_id
          user_id
          day_number
          title
          description
          ai_insight
          category
          latitude
          longitude
          visit_time
          status
        }
      }
    """;

    // Configure the query to ensure it pulls fresh data from the cloud
    final QueryOptions options = QueryOptions(
      document: gql(getItineraryQuery),
      fetchPolicy: FetchPolicy.networkOnly,
    );

    // Execute the query
    final QueryResult result = await gqlClient.query(options);

    // Handle any connection or permission errors
    if (result.hasException) {
      print("⚠️ NHOST SYNC ERROR: \${result.exception.toString()}");
      return;
    }

    // Extract the list of items from the JSON response
    final List<dynamic>? data = result.data?['itinerary_items'];

    if (data != null && data.isNotEmpty) {
      // Convert the Nhost JSON into your existing Dart models
      final cloudItems = data.map((json) => ItineraryItem.fromJson(json)).toList();

      // Update the Riverpod Provider locally
      final notifier = ref.read(itineraryProvider.notifier);
      for (var item in cloudItems) {
        // syncToCloud: false ensures we don't accidentally re-upload what we just downloaded
        await notifier.addItem(item, syncToCloud: false);
      }
    }

    print("✅ NHOST MASTER SYNC COMPLETE: Itineraries loaded.");
  }
}