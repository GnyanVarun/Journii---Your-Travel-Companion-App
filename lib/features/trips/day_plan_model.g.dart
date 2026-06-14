// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'day_plan_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DayPlanAdapter extends TypeAdapter<DayPlan> {
  @override
  final int typeId = 12;

  @override
  DayPlan read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DayPlan(
      dayNumber: fields[0] as int,
      places: (fields[1] as List).cast<PlacePlan>(),
    );
  }

  @override
  void write(BinaryWriter writer, DayPlan obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.dayNumber)
      ..writeByte(1)
      ..write(obj.places);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayPlanAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
