import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group_model.dart';
import '../services/firestore_service.dart';

class GroupRepository {
  final FirestoreService _firestoreService = FirestoreService();
  static const String _collection = 'groups';

  Future<String> createGroup(GroupModel group) async {
    final docRef =
        await _firestoreService.addDocument(_collection, group.toFirestore());
    return docRef.id;
  }

  Future<GroupModel?> getGroup(String groupId) async {
    final doc = await _firestoreService.getDocument(_collection, groupId);
    if (!doc.exists) return null;
    return GroupModel.fromFirestore(doc);
  }

  Future<void> updateGroup(String groupId, Map<String, dynamic> data) async {
    data['updatedAt'] = Timestamp.fromDate(DateTime.now());
    await _firestoreService.updateDocument(_collection, groupId, data);
  }

  Future<void> deleteGroup(String groupId) async {
    await _firestoreService.deleteDocument(_collection, groupId);
  }

  Future<List<GroupModel>> getGroupsByEnterprise(
    String enterpriseId, {
    Source? source,
  }) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
      ],
      source: source,
    );

    return snapshot.docs.map((doc) => GroupModel.fromFirestore(doc)).toList();
  }

  Future<void> addMember(String groupId, String userId) async {
    await _firestoreService.updateDocument(_collection, groupId, {
      'memberIds': FieldValue.arrayUnion([userId]),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> removeMember(String groupId, String userId) async {
    await _firestoreService.updateDocument(_collection, groupId, {
      'memberIds': FieldValue.arrayRemove([userId]),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Stream<List<GroupModel>> streamGroupsByEnterprise(String enterpriseId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
          ],
        )
        .map((snapshot) =>
            snapshot.docs.map((doc) => GroupModel.fromFirestore(doc)).toList());
  }
}
