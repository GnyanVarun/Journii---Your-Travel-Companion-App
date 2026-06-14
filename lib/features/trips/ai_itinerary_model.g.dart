// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_itinerary_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AIPlaceAdapter extends TypeAdapter<AIPlace> {
  @override
  final int typeId = 22;

  @override
  AIPlace read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AIPlace(
      name: fields[0] as String,
      description: fields[1] as String,
      day: fields[2] as int,
      bestTime: fields[3] as String,
      visitTip: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, AIPlace obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.description)
      ..writeByte(2)
      ..write(obj.day)
      ..writeByte(3)
      ..write(obj.bestTime)
      ..writeByte(4)
      ..write(obj.visitTip);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AIPlaceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
