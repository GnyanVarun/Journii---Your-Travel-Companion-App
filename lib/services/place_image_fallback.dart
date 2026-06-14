class PlaceImageFallback {
  static String forCategory(String? category) {
    switch (category) {
      case 'historic':
        return 'assets/place_placeholders/historic.png';
      case 'attraction':
        return 'assets/place_placeholders/attraction.png';
      case 'museum':
        return 'assets/place_placeholders/museum.png';
      case 'restaurant':
      case 'cafe':
        return 'assets/place_placeholders/restaurant.png';
      case 'park':
        return 'assets/place_placeholders/park.png';
      default:
        return 'assets/place_placeholders/remove.png';
    }
  }
}
