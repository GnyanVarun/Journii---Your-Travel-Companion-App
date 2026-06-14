import 'package:hive/hive.dart';

part 'trip_style.g.dart';

// ✅ CHANGE THIS to 5 (or any unique number not used by other models)
@HiveType(typeId: 5)
enum TripStyle {
  @HiveField(0)
  leisure,

  @HiveField(1)
  adventure,

  @HiveField(2)
  cultural,

  @HiveField(3)
  luxury,

  @HiveField(4)
  backpacking,
}

extension TripStyleLabel on TripStyle {
  String get label {
    switch (this) {
      case TripStyle.leisure: return 'Leisure';
      case TripStyle.adventure: return 'Adventure';
      case TripStyle.cultural: return 'Cultural';
      case TripStyle.luxury: return 'Luxury';
      case TripStyle.backpacking: return 'Backpacking';
    }
  }
}