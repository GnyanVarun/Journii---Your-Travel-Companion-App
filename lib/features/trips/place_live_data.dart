class PlaceLiveData {
  final String category;
  final String? address;
  final String? openingHours;
  final String? website;

  // 🟢 NEW FIELDS!
  final String? phone;
  final String? cuisine;
  final String? wheelchair;

  PlaceLiveData({
    required this.category,
    this.address,
    this.openingHours,
    this.website,
    this.phone,
    this.cuisine,
    this.wheelchair,
  });
}