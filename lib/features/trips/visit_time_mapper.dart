import 'itinerary_item_model.dart';

VisitTime? mapBestTime(String? bestTime) {
  if (bestTime == null) return null;

  switch (bestTime.toLowerCase()) {
    case 'morning':
      return VisitTime.morning;
    case 'afternoon':
      return VisitTime.afternoon;
    case 'evening':
      return VisitTime.evening;
    case 'night':
      return VisitTime.night;
    default:
      return null;
  }
}

String? defaultVisitTip(VisitTime? time) {
  switch (time) {
    case VisitTime.morning:
      return 'Best visited in the morning to avoid crowds.';
    case VisitTime.afternoon:
      return 'Great for a relaxed afternoon visit.';
    case VisitTime.evening:
      return 'Looks especially beautiful in the evening.';
    case VisitTime.night:
      return 'Best experienced at night for atmosphere.';
    default:
      return null;
  }
}
