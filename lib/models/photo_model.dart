import 'package:cloud_firestore/cloud_firestore.dart';

class PhotoModel {
  final String id;
  final String enterpriseId;
  final String employeeId;
  final String sessionId;
  final String imageUrl;
  final String thumbnailUrl;
  final DateTime timestamp;
  final String location;
  final double latitude;
  final double longitude;
  final Map<String, String> geotagData; // {date, time, coordinates}
  final DateTime createdAt;

  const PhotoModel({
    required this.id,
    required this.enterpriseId,
    required this.employeeId,
    required this.sessionId,
    required this.imageUrl,
    this.thumbnailUrl = '',
    required this.timestamp,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.geotagData,
    required this.createdAt,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  factory PhotoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final geotagRaw = data['geotagData'] as Map<String, dynamic>? ?? {};
    return PhotoModel(
      id: doc.id,
      enterpriseId: data['enterpriseId'] ?? '',
      employeeId: data['employeeId'] ?? '',
      sessionId: data['sessionId'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      thumbnailUrl: data['thumbnailUrl'] ?? '',
      timestamp:
          (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      location: data['location'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      geotagData: geotagRaw.map((k, v) => MapEntry(k, v.toString())),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enterpriseId': enterpriseId,
      'employeeId': employeeId,
      'sessionId': sessionId,
      'imageUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'timestamp': Timestamp.fromDate(timestamp),
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'geotagData': geotagData,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  PhotoModel copyWith({
    String? id,
    String? enterpriseId,
    String? employeeId,
    String? sessionId,
    String? imageUrl,
    String? thumbnailUrl,
    DateTime? timestamp,
    String? location,
    double? latitude,
    double? longitude,
    Map<String, String>? geotagData,
    DateTime? createdAt,
  }) {
    return PhotoModel(
      id: id ?? this.id,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      employeeId: employeeId ?? this.employeeId,
      sessionId: sessionId ?? this.sessionId,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      timestamp: timestamp ?? this.timestamp,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geotagData: geotagData ?? this.geotagData,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
