import 'trip_model.dart';

class TripDateMapper {
  /// Returns the calendar date for a given trip day (1-based)
  static DateTime? dateForDay({
    required Trip trip,
    required int day,
  }) {
    if (trip.startDate == null) return null;
    if (day < 1) return null;

    return DateTime(
      trip.startDate!.year,
      trip.startDate!.month,
      trip.startDate!.day + (day - 1),
    );
  }

  /// Returns the trip day number for a given calendar date
  /// Example: startDate = Mar 10, today = Mar 12 → Day 3
  static int? dayForDate({
    required Trip trip,
    required DateTime date,
  }) {
    if (trip.startDate == null) return null;

    final start = _dateOnly(trip.startDate!);
    final target = _dateOnly(date);

    final diff = target.difference(start).inDays;

    if (diff < 0) return null;
    if (trip.durationDays != null && diff >= trip.durationDays!) return null;

    return diff + 1; // 1-based
  }

  /// Checks if a calendar date falls within the trip
  static bool isDateWithinTrip({
    required Trip trip,
    required DateTime date,
  }) {
    if (trip.startDate == null || trip.endDate == null) return false;

    final d = _dateOnly(date);
    final start = _dateOnly(trip.startDate!);
    final end = _dateOnly(trip.endDate!);

    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// Returns today's trip day, if applicable
  static int? todayTripDay(Trip trip) {
    return dayForDate(
      trip: trip,
      date: DateTime.now(),
    );
  }

  /// --- Helpers ---
  static DateTime _dateOnly(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }
}
