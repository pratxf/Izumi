import 'dart:convert';

enum OfflineJobType { chat, photo, locationSync, activityLog, sessionEvent, taskEvent }

enum OfflineJobStatus { pending, processing, error, done, failed }

class OfflineJob {
  const OfflineJob({
    required this.id,
    required this.type,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.createdAtMs,
    this.localFilePath,
    this.lastAttemptAtMs,
    this.nextAttemptAtMs,
    this.idempotencyKey,
  });

  final String id;
  final OfflineJobType type;
  final Map<String, dynamic> payload;
  final String? localFilePath;
  final OfflineJobStatus status;
  final int retryCount;
  final int createdAtMs;
  final int? lastAttemptAtMs;
  final int? nextAttemptAtMs;
  final String? idempotencyKey;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'payload': jsonEncode(payload),
      'local_file_path': localFilePath,
      'status': status.name,
      'retry_count': retryCount,
      'created_at_ms': createdAtMs,
      'last_attempt_at_ms': lastAttemptAtMs,
      'next_attempt_at_ms': nextAttemptAtMs,
      'idempotency_key': idempotencyKey,
    };
  }

  factory OfflineJob.fromMap(Map<String, dynamic> map) {
    return OfflineJob(
      id: map['id'] as String,
      type: OfflineJobType.values.firstWhere(
        (value) => value.name == map['type'],
        orElse: () => OfflineJobType.chat,
      ),
      payload: _decodePayload(map['payload']),
      localFilePath: map['local_file_path'] as String?,
      status: OfflineJobStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => OfflineJobStatus.pending,
      ),
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      createdAtMs: (map['created_at_ms'] as num).toInt(),
      lastAttemptAtMs: (map['last_attempt_at_ms'] as num?)?.toInt(),
      nextAttemptAtMs: (map['next_attempt_at_ms'] as num?)?.toInt(),
      idempotencyKey: map['idempotency_key'] as String?,
    );
  }

  OfflineJob copyWith({
    String? id,
    OfflineJobType? type,
    Map<String, dynamic>? payload,
    String? localFilePath,
    bool clearLocalFilePath = false,
    OfflineJobStatus? status,
    int? retryCount,
    int? createdAtMs,
    int? lastAttemptAtMs,
    bool clearLastAttemptAtMs = false,
    int? nextAttemptAtMs,
    bool clearNextAttemptAtMs = false,
    String? idempotencyKey,
  }) {
    return OfflineJob(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      localFilePath:
          clearLocalFilePath ? null : (localFilePath ?? this.localFilePath),
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      lastAttemptAtMs: clearLastAttemptAtMs
          ? null
          : (lastAttemptAtMs ?? this.lastAttemptAtMs),
      nextAttemptAtMs: clearNextAttemptAtMs
          ? null
          : (nextAttemptAtMs ?? this.nextAttemptAtMs),
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }

  static Map<String, dynamic> _decodePayload(Object? rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }
    if (rawValue is String && rawValue.isNotEmpty) {
      final decoded = jsonDecode(rawValue);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }
    return const <String, dynamic>{};
  }
}
