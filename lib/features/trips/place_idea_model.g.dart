// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'place_idea_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlaceIdeaAdapter extends TypeAdapter<PlaceIdea> {
  @override
  final int typeId = 1;

  @override
  PlaceIdea read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlaceIdea(
      id: fields[0] as String,
      tripId: fields[1] as String,
      name: fields[2] as String,
      notes: fields[3] as String,
      priority: fields[4] as int,
      createdAt: fields[5] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, PlaceIdea obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.tripId)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.notes)
      ..writeByte(4)
      ..write(obj.priority)
      ..writeByte(5)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaceIdeaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
