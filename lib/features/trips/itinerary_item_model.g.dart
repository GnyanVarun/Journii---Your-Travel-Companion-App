// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'itinerary_item_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ItineraryItemAdapter extends TypeAdapter<ItineraryItem> {
  @override
  final int typeId = 2;

  @override
  ItineraryItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ItineraryItem(
      id: fields[0] as String,
      tripId: fields[1] as String,
      title: fields[2] as String,
      description: fields[3] as String,
      day: fields[4] as int,
      isAiGenerated: fields[5] as bool,
      isLocked: fields[6] as bool,
      latitude: fields[7] as double?,
      longitude: fields[8] as double?,
      status: fields[9] as ItineraryStatus,
      visitTip: fields[10] as String?,
      preferredVisitTime: fields[11] as VisitTime?,
      category: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ItineraryItem obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.tripId)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.day)
      ..writeByte(5)
      ..write(obj.isAiGenerated)
      ..writeByte(6)
      ..write(obj.isLocked)
      ..writeByte(7)
      ..write(obj.latitude)
      ..writeByte(8)
      ..write(obj.longitude)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.visitTip)
      ..writeByte(11)
      ..write(obj.preferredVisitTime)
      ..writeByte(12)
      ..write(obj.category);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItineraryItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ItineraryStatusAdapter extends TypeAdapter<ItineraryStatus> {
  @override
  final int typeId = 3;

  @override
  ItineraryStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ItineraryStatus.planned;
      case 1:
        return ItineraryStatus.skipped;
      case 2:
        return ItineraryStatus.completed;
      default:
        return ItineraryStatus.planned;
    }
  }

  @override
  void write(BinaryWriter writer, ItineraryStatus obj) {
    switch (obj) {
      case ItineraryStatus.planned:
        writer.writeByte(0);
        break;
      case ItineraryStatus.skipped:
        writer.writeByte(1);
        break;
      case ItineraryStatus.completed:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItineraryStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class VisitTimeAdapter extends TypeAdapter<VisitTime> {
  @override
  final int typeId = 4;

  @override
  VisitTime read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return VisitTime.morning;
      case 1:
        return VisitTime.afternoon;
      case 2:
        return VisitTime.evening;
      case 3:
        return VisitTime.night;
      default:
        return VisitTime.morning;
    }
  }

  @override
  void write(BinaryWriter writer, VisitTime obj) {
    switch (obj) {
      case VisitTime.morning:
        writer.writeByte(0);
        break;
      case VisitTime.afternoon:
        writer.writeByte(1);
        break;
      case VisitTime.evening:
        writer.writeByte(2);
        break;
      case VisitTime.night:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VisitTimeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
