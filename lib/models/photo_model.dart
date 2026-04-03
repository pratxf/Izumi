import 'package:cloud_firestore/cloud_firestore.dart';
import 'upload_status.dart';

class PhotoModel {
  final String id;
  final String? clientRequestId;
  final String enterpriseId;
  final String employeeId;
  final String sessionId;
  final String imageUrl;
  final String? thumbnailUrl;
  final String? localFilePath;
  final DateTime timestamp;
  final String location;
  final double latitude;
  final double longitude;
  final Map<String, String> geotagData; // {date, time, coordinates}
  final String? category; // 'distributor' | 'farmer'
  final String? customerType; // 'new' | 'old'
  final String? customerName;
  final String? customerPhone;
  final String? notes;
  final String? groupId;
  final bool hasFollowUp;
  final DateTime createdAt;
  final UploadStatus uploadStatus;

  const PhotoModel({
    required this.id,
    this.clientRequestId,
    required this.enterpriseId,
    required this.employeeId,
    required this.sessionId,
    required this.imageUrl,
    this.thumbnailUrl,
    this.localFilePath,
    required this.timestamp,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.geotagData,
    this.category,
    this.customerType,
    this.customerName,
    this.customerPhone,
    this.notes,
    this.groupId,
    this.hasFollowUp = false,
    required this.createdAt,
    this.uploadStatus = UploadStatus.success,
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
      clientRequestId: data['clientRequestId'] as String?,
      enterpriseId: data['enterpriseId'] ?? '',
      employeeId: data['employeeId'] ?? '',
      sessionId: data['sessionId'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      thumbnailUrl: data['thumbnailUrl'] as String?,
      localFilePath: null,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      location: data['location'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      geotagData: geotagRaw.map((k, v) => MapEntry(k, v.toString())),
      category: data['category'] as String?,
      customerType: data['customerType'] as String?,
      customerName: data['customerName'] as String?,
      customerPhone: data['customerPhone'] as String?,
      notes: data['notes'] as String?,
      groupId: data['groupId'] as String?,
      hasFollowUp: data['hasFollowUp'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      uploadStatus: UploadStatus.success,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (clientRequestId != null) 'clientRequestId': clientRequestId,
      'enterpriseId': enterpriseId,
      'employeeId': employeeId,
      'sessionId': sessionId,
      'imageUrl': imageUrl,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      'timestamp': Timestamp.fromDate(timestamp),
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'geotagData': geotagData,
      if (category != null) 'category': category,
      if (customerType != null) 'customerType': customerType,
      if (customerName != null) 'customerName': customerName,
      if (customerPhone != null) 'customerPhone': customerPhone,
      if (notes != null) 'notes': notes,
      if (groupId != null) 'groupId': groupId,
      'hasFollowUp': hasFollowUp,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  PhotoModel copyWith({
    String? id,
    String? clientRequestId,
    String? enterpriseId,
    String? employeeId,
    String? sessionId,
    String? imageUrl,
    String? thumbnailUrl,
    String? localFilePath,
    DateTime? timestamp,
    String? location,
    double? latitude,
    double? longitude,
    Map<String, String>? geotagData,
    String? category,
    String? customerType,
    String? customerName,
    String? customerPhone,
    String? notes,
    String? groupId,
    bool? hasFollowUp,
    DateTime? createdAt,
    UploadStatus? uploadStatus,
  }) {
    return PhotoModel(
      id: id ?? this.id,
      clientRequestId: clientRequestId ?? this.clientRequestId,
      enterpriseId: enterpriseId ?? this.enterpriseId,
      employeeId: employeeId ?? this.employeeId,
      sessionId: sessionId ?? this.sessionId,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      localFilePath: localFilePath ?? this.localFilePath,
      timestamp: timestamp ?? this.timestamp,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geotagData: geotagData ?? this.geotagData,
      category: category ?? this.category,
      customerType: customerType ?? this.customerType,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      notes: notes ?? this.notes,
      groupId: groupId ?? this.groupId,
      hasFollowUp: hasFollowUp ?? this.hasFollowUp,
      createdAt: createdAt ?? this.createdAt,
      uploadStatus: uploadStatus ?? this.uploadStatus,
    );
  }
}
