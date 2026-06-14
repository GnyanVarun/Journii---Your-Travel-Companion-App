// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TripAdapter extends TypeAdapter<Trip> {
  @override
  final int typeId = 0;

  @override
  Trip read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Trip(
      id: fields[0] as String,
      title: fields[1] as String,
      description: fields[2] as String,
      createdAt: fields[3] as DateTime,
      durationDays: fields[4] as int?,
      style: fields[5] as TripStyle?,
      startDate: fields[6] as DateTime?,
      endDate: fields[7] as DateTime?,
      userId: fields[8] as String?,
      destination: fields[9] as String?,
      curiosityLevel: fields[10] == null ? 2 : fields[10] as int,
      badgeImageUrl: fields[11] as String?,
      badgeSlogan: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Trip obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.durationDays)
      ..writeByte(5)
      ..write(obj.style)
      ..writeByte(6)
      ..write(obj.startDate)
      ..writeByte(7)
      ..write(obj.endDate)
      ..writeByte(8)
      ..write(obj.userId)
      ..writeByte(9)
      ..write(obj.destination)
      ..writeByte(10)
      ..write(obj.curiosityLevel)
      ..writeByte(11)
      ..write(obj.badgeImageUrl)
      ..writeByte(12)
      ..write(obj.badgeSlogan);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
