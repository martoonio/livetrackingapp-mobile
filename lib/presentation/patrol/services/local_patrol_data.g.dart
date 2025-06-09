// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_patrol_data.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalPatrolDataAdapter extends TypeAdapter<LocalPatrolData> {
  @override
  final int typeId = 0;

  @override
  LocalPatrolData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalPatrolData(
      taskId: fields[0] as String,
      userId: fields[1] as String,
      status: fields[2] as String,
      startTime: fields[3] as String?,
      endTime: fields[4] as String?,
      distance: fields[5] as double,
      elapsedTimeSeconds: fields[6] as int,
      initialReportPhotoUrl: fields[7] as String?,
      finalReportPhotoUrl: fields[8] as String?,
      initialNote: fields[9] as String?,
      finalNote: fields[10] as String?,
      routePath: (fields[11] as Map).cast<String, dynamic>(),
      isSynced: fields[12] as bool,
      lastUpdated: fields[13] as String,
      mockLocationDetected: fields[14] as bool,
      mockLocationCount: fields[15] as int,
    );
  }

  @override
  void write(BinaryWriter writer, LocalPatrolData obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.taskId)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.status)
      ..writeByte(3)
      ..write(obj.startTime)
      ..writeByte(4)
      ..write(obj.endTime)
      ..writeByte(5)
      ..write(obj.distance)
      ..writeByte(6)
      ..write(obj.elapsedTimeSeconds)
      ..writeByte(7)
      ..write(obj.initialReportPhotoUrl)
      ..writeByte(8)
      ..write(obj.finalReportPhotoUrl)
      ..writeByte(9)
      ..write(obj.initialNote)
      ..writeByte(10)
      ..write(obj.finalNote)
      ..writeByte(11)
      ..write(obj.routePath)
      ..writeByte(12)
      ..write(obj.isSynced)
      ..writeByte(13)
      ..write(obj.lastUpdated)
      ..writeByte(14)
      ..write(obj.mockLocationDetected)
      ..writeByte(15)
      ..write(obj.mockLocationCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalPatrolDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
