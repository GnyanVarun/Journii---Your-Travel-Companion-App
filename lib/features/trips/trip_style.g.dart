// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip_style.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TripStyleAdapter extends TypeAdapter<TripStyle> {
  @override
  final int typeId = 5;

  @override
  TripStyle read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TripStyle.leisure;
      case 1:
        return TripStyle.adventure;
      case 2:
        return TripStyle.cultural;
      case 3:
        return TripStyle.luxury;
      case 4:
        return TripStyle.backpacking;
      default:
        return TripStyle.leisure;
    }
  }

  @override
  void write(BinaryWriter writer, TripStyle obj) {
    switch (obj) {
      case TripStyle.leisure:
        writer.writeByte(0);
        break;
      case TripStyle.adventure:
        writer.writeByte(1);
        break;
      case TripStyle.cultural:
        writer.writeByte(2);
        break;
      case TripStyle.luxury:
        writer.writeByte(3);
        break;
      case TripStyle.backpacking:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripStyleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
