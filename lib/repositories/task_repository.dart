import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';
import '../services/firestore_service.dart';

class TaskRepository {
  final FirestoreService _firestoreService = FirestoreService();
  static const String _collection = 'tasks';

  Future<String> createTask(TaskModel task) async {
    final docRef =
        await _firestoreService.addDocument(_collection, task.toFirestore());
    return docRef.id;
  }

  Future<TaskModel?> getTask(String taskId) async {
    final doc = await _firestoreService.getDocument(_collection, taskId);
    if (!doc.exists) return null;
    return TaskModel.fromFirestore(doc);
  }

  Future<void> updateTask(String taskId, Map<String, dynamic> data) async {
    data['updatedAt'] = Timestamp.fromDate(DateTime.now());
    await _firestoreService.updateDocument(_collection, taskId, data);
  }

  Future<void> completeTask(String taskId) async {
    await _firestoreService.updateDocument(_collection, taskId, {
      'status': 'completed',
      'completedAt': Timestamp.fromDate(DateTime.now()),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> deleteTask(String taskId) async {
    await _firestoreService.deleteDocument(_collection, taskId);
  }

  Future<List<TaskModel>> getTasksByEmployee(
    String employeeId, {
    String? status,
    String? type,
  }) async {
    final filters = <QueryFilter>[
      QueryFilter('assignedTo', FilterOp.isEqualTo, employeeId),
    ];

    if (status != null) {
      filters.add(QueryFilter('status', FilterOp.isEqualTo, status));
    }

    if (type != null) {
      filters.add(QueryFilter('type', FilterOp.isEqualTo, type));
    }

    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: filters,
      orderBy: 'createdAt',
      descending: true,
    );

    return snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList();
  }

  Future<List<TaskModel>> getTasksByEnterprise(
    String enterpriseId, {
    String? status,
  }) async {
    final filters = <QueryFilter>[
      QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
    ];

    if (status != null) {
      filters.add(QueryFilter('status', FilterOp.isEqualTo, status));
    }

    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: filters,
      orderBy: 'createdAt',
      descending: true,
    );

    return snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList();
  }

  Stream<List<TaskModel>> streamTasksByEmployee(String employeeId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('assignedTo', FilterOp.isEqualTo, employeeId),
          ],
          orderBy: 'createdAt',
          descending: true,
        )
        .map((snapshot) =>
            snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList());
  }

  Stream<List<TaskModel>> streamTasksByEnterprise(String enterpriseId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
          ],
          orderBy: 'createdAt',
          descending: true,
        )
        .map((snapshot) =>
            snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList());
  }
}
