class LocationData {
  final int id;
  final double threshold;
  final double latitude;
  final double longitude;

  LocationData({
    required this.id,
    required this.threshold,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'threshold': threshold,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      id: json['id'] ?? 1,
           threshold: _parseDouble(json['threshold'] ?? json['attendance_range']),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
    );
  }

  static double _parseDouble(dynamic value) {
    if (value is String) return double.tryParse(value) ?? 0;
    if (value is num) return value.toDouble();
    return 0;
  }
  }
