import 'package:cloud_firestore/cloud_firestore.dart';
import 'upload_status.dart';

class ChatMessageModel {
  final String id;
  final String? clientRequestId;
  final String senderId;
  final String senderName;
  final String type; // "text", "image", "location"
  final String? text;
  final String? imageUrl;
  final String? thumbnailUrl;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? caption;
  final DateTime createdAt;
  final bool isDeleted;

  // Reply fields
  final String? replyToId;
  final String? replyToSenderName;
  final String? replyToText;
  final String? replyToType;
  final String? replyToImageUrl;
  final UploadStatus uploadStatus;
  final String? errorMessage;

  const ChatMessageModel({
    required this.id,
    this.clientRequestId,
    required this.senderId,
    required this.senderName,
    this.type = 'text',
    this.text,
    this.imageUrl,
    this.thumbnailUrl,
    this.latitude,
    this.longitude,
    this.address,
    this.caption,
    required this.createdAt,
    this.isDeleted = false,
    this.replyToId,
    this.replyToSenderName,
    this.replyToText,
    this.replyToType,
    this.replyToImageUrl,
    this.uploadStatus = UploadStatus.success,
    this.errorMessage,
  });

  bool get isText => type == 'text';
  bool get isImage => type == 'image';
  bool get isLocation => type == 'location';
  bool get hasReply => replyToId != null;

  bool isMe(String userId) => senderId == userId;

  factory ChatMessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessageModel(
      id: doc.id,
      clientRequestId: data['clientRequestId'] as String?,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      text: data['text'] as String?,
      imageUrl: data['imageUrl'] as String?,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      address: data['address'] as String?,
      caption: data['caption'] as String?,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      isDeleted: data['isDeleted'] as bool? ?? false,
      replyToId: data['replyToId'] as String?,
      replyToSenderName: data['replyToSenderName'] as String?,
      replyToText: data['replyToText'] as String?,
      replyToType: data['replyToType'] as String?,
      replyToImageUrl: data['replyToImageUrl'] as String?,
      uploadStatus: UploadStatus.success,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (clientRequestId != null) 'clientRequestId': clientRequestId,
      'senderId': senderId,
      'senderName': senderName,
      'type': type,
      if (text != null) 'text': text,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (address != null) 'address': address,
      if (caption != null) 'caption': caption,
      'createdAt': Timestamp.fromDate(createdAt),
      if (isDeleted) 'isDeleted': true,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToType != null) 'replyToType': replyToType,
      if (replyToImageUrl != null) 'replyToImageUrl': replyToImageUrl,
    };
  }

  ChatMessageModel copyWith({
    String? id,
    String? clientRequestId,
    String? senderId,
    String? senderName,
    String? type,
    String? text,
    String? imageUrl,
    String? thumbnailUrl,
    double? latitude,
    double? longitude,
    String? address,
    String? caption,
    DateTime? createdAt,
    bool? isDeleted,
    String? replyToId,
    String? replyToSenderName,
    String? replyToText,
    String? replyToType,
    String? replyToImageUrl,
    UploadStatus? uploadStatus,
    String? errorMessage,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      clientRequestId: clientRequestId ?? this.clientRequestId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      type: type ?? this.type,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      caption: caption ?? this.caption,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
      replyToId: replyToId ?? this.replyToId,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      replyToText: replyToText ?? this.replyToText,
      replyToType: replyToType ?? this.replyToType,
      replyToImageUrl: replyToImageUrl ?? this.replyToImageUrl,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
