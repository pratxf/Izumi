import 'package:cloud_firestore/cloud_firestore.dart';

class LeaveModel {
  final String id;
  final String employeeId;
  final String enterpriseId;
  final String date; // YYYY-MM-DD
  final DateTime markedAt;

  const LeaveModel({
    required this.id,
    required this.employeeId,
    required this.enterpriseId,
    required this.date,
    required this.markedAt,
  });

  factory LeaveModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LeaveModel(
      id: doc.id,
      employeeId: data['employeeId'] as String? ?? '',
      enterpriseId: data['enterpriseId'] as String? ?? '',
      date: data['date'] as String? ?? '',
      markedAt: (data['markedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'employeeId': employeeId,
        'enterpriseId': enterpriseId,
        'date': date,
        'markedAt': Timestamp.fromDate(markedAt),
      };
}
