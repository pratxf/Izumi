import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

class UserRepository {
  final FirestoreService _firestoreService = FirestoreService();
  static const String _collection = 'users';

  Future<UserModel?> getUser(String userId) async {
    final doc = await _firestoreService.getDocument(_collection, userId);
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  Future<List<UserModel>> getUsersByEnterprise(String enterpriseId) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
      ],
    );
    return snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
  }

  Future<void> createUser(UserModel user) async {
    await _firestoreService.setDocument(_collection, user.id, user.toFirestore());
  }

  Future<void> updateUser(UserModel user) async {
    await _firestoreService.updateDocument(
      _collection,
      user.id,
      user.copyWith(updatedAt: DateTime.now()).toFirestore(),
    );
  }

  Future<void> deleteUser(String userId) async {
    await _firestoreService.deleteDocument(_collection, userId);
  }

  Future<void> updateFcmToken(String userId, String token) async {
    await _firestoreService.updateDocument(_collection, userId, {
      'fcmToken': token,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Stream<UserModel?> streamUser(String userId) {
    return _firestoreService
        .streamDocument(_collection, userId)
        .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
  }

  Stream<List<UserModel>> streamUsersByEnterprise(String enterpriseId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
          ],
        )
        .map((snapshot) =>
            snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
  }
}
