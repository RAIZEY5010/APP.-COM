import 'dart:convert';

class ClientDevice {
  final String id;
  String deviceName;
  final DateTime startTime;
  int durationHours;
  bool isPaused;
  int remainingSecondsWhenPaused;

  ClientDevice({
    required this.id,
    required this.deviceName,
    required this.startTime,
    required this.durationHours,
    this.isPaused = false,
    this.remainingSecondsWhenPaused = 0,
  });

  // حساب وقت الانتهاء المستهدف
  DateTime get endTime => startTime.add(Duration(hours: durationHours));

  // حساب الثواني المتبقية
  int get remainingSeconds {
    if (isPaused) return remainingSecondsWhenPaused;
    final diff = endTime.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  // تنسيق الوقت المتبقي كنص (ساعة:دقيقة:ثانية)
  String get remainingFormatted {
    final totalSec = remainingSeconds;
    if (totalSec <= 0) return 'منتهي';
    final hours = totalSec ~/ 3600;
    final minutes = (totalSec % 3600) ~/ 60;
    final seconds = totalSec % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deviceName': deviceName,
      'startTime': startTime.toIso8601String(),
      'durationHours': durationHours,
      'isPaused': isPaused,
      'remainingSecondsWhenPaused': remainingSecondsWhenPaused,
    };
  }

  factory ClientDevice.fromMap(Map<String, dynamic> map) {
    return ClientDevice(
      id: map['id'],
      deviceName: map['deviceName'],
      startTime: DateTime.parse(map['startTime']),
      durationHours: map['durationHours'],
      isPaused: map['isPaused'] ?? false,
      remainingSecondsWhenPaused: map['remainingSecondsWhenPaused'] ?? 0,
    );
  }

  String toJson() => json.encode(toMap());
  factory ClientDevice.fromJson(String source) => ClientDevice.fromMap(json.decode(source));
}
