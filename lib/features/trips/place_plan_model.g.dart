// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'place_plan_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlacePlanAdapter extends TypeAdapter<PlacePlan> {
  @override
  final int typeId = 13;

  @override
  PlacePlan read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlacePlan(
      name: fields[0] as String,
      description: fields[1] as String,
      timeSlot: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, PlacePlan obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.description)
      ..writeByte(2)
      ..write(obj.timeSlot);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlacePlanAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
