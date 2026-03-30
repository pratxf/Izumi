import 'package:cloud_firestore/cloud_firestore.dart';

class SessionLocationModel {
  final String id;
  final double latitude;
  final double longitude;
  final String address;
  final DateTime timestamp;
  final String type; // 'check_in' | 'visit' | 'check_out'
  final String title;

  const SessionLocationModel({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.timestamp,
    required this.type,
    required this.title,
  });

  bool get isCheckIn => type == 'check_in';
  bool get isVisit => type == 'visit';
  bool get isCheckOut => type == 'check_out';
  bool get isLocationUpdate => type == 'location_update';
  bool get isLocationLost => type == 'location_lost';
  bool get isLocationRecovered => type == 'location_recovered';
  bool get isAutoEnd => type == 'auto_end';

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  factory SessionLocationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SessionLocationModel(
      id: doc.id,
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      address: data['address'] ?? '',
      timestamp:
          (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type: data['type'] ?? 'visit',
      title: data['title'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type,
      'title': title,
    };
  }

  SessionLocationModel copyWith({
    String? id,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? timestamp,
    String? type,
    String? title,
  }) {
    return SessionLocationModel(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      title: title ?? this.title,
    );
  }
}
