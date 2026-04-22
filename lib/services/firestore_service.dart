import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  FirebaseFirestore get instance => _db;

  // Get a single document
  Future<DocumentSnapshot> getDocument(String collection, String docId) {
    return _db.collection(collection).doc(docId).get();
  }

  // Get a collection with optional query
  Future<QuerySnapshot> getCollection(
    String collection, {
    List<QueryFilter>? filters,
    String? orderBy,
    bool descending = false,
    int? limit,
    Source? source,
  }) {
    Query query = _db.collection(collection);

    if (filters != null) {
      for (final filter in filters) {
        query = _applyFilter(query, filter);
      }
    }

    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    if (source != null) {
      return query.get(GetOptions(source: source));
    }
    return query.get();
  }

  // Add a document (auto-generated ID)
  Future<DocumentReference> addDocument(
    String collection,
    Map<String, dynamic> data,
  ) {
    return _db.collection(collection).add(data);
  }

  // Set a document (specific ID)
  Future<void> setDocument(
    String collection,
    String docId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) {
    return _db
        .collection(collection)
        .doc(docId)
        .set(data, SetOptions(merge: merge));
  }

  // Update a document
  Future<void> updateDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) {
    return _db.collection(collection).doc(docId).update(data);
  }

  // Delete a document
  Future<void> deleteDocument(String collection, String docId) {
    return _db.collection(collection).doc(docId).delete();
  }

  // Stream a single document
  Stream<DocumentSnapshot> streamDocument(String collection, String docId) {
    return _db.collection(collection).doc(docId).snapshots();
  }

  // Stream a collection with optional query
  Stream<QuerySnapshot> streamCollection(
    String collection, {
    List<QueryFilter>? filters,
    String? orderBy,
    bool descending = false,
    int? limit,
  }) {
    Query query = _db.collection(collection);

    if (filters != null) {
      for (final filter in filters) {
        query = _applyFilter(query, filter);
      }
    }

    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots();
  }

  // Subcollection operations
  Future<DocumentReference> addToSubcollection(
    String parentCollection,
    String parentDocId,
    String subcollection,
    Map<String, dynamic> data,
  ) {
    return _db
        .collection(parentCollection)
        .doc(parentDocId)
        .collection(subcollection)
        .add(data);
  }

  Future<QuerySnapshot> getSubcollection(
    String parentCollection,
    String parentDocId,
    String subcollection, {
    String? orderBy,
    bool descending = false,
  }) {
    Query query = _db
        .collection(parentCollection)
        .doc(parentDocId)
        .collection(subcollection);

    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    return query.get();
  }

  Stream<QuerySnapshot> streamSubcollection(
    String parentCollection,
    String parentDocId,
    String subcollection, {
    String? orderBy,
    bool descending = false,
  }) {
    Query query = _db
        .collection(parentCollection)
        .doc(parentDocId)
        .collection(subcollection);

    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    return query.snapshots();
  }

  // Batch write
  Future<void> batchWrite(
      List<BatchOperation> operations) async {
    final batch = _db.batch();

    for (final op in operations) {
      final ref = _db.collection(op.collection).doc(op.docId);
      switch (op.type) {
        case BatchType.set:
          batch.set(ref, op.data!);
          break;
        case BatchType.update:
          batch.update(ref, op.data!);
          break;
        case BatchType.delete:
          batch.delete(ref);
          break;
      }
    }

    await batch.commit();
  }

  Query _applyFilter(Query query, QueryFilter filter) {
    switch (filter.operator) {
      case FilterOp.isEqualTo:
        return query.where(filter.field, isEqualTo: filter.value);
      case FilterOp.isNotEqualTo:
        return query.where(filter.field, isNotEqualTo: filter.value);
      case FilterOp.isLessThan:
        return query.where(filter.field, isLessThan: filter.value);
      case FilterOp.isGreaterThan:
        return query.where(filter.field, isGreaterThan: filter.value);
      case FilterOp.isLessThanOrEqualTo:
        return query.where(filter.field, isLessThanOrEqualTo: filter.value);
      case FilterOp.isGreaterThanOrEqualTo:
        return query.where(filter.field, isGreaterThanOrEqualTo: filter.value);
      case FilterOp.arrayContains:
        return query.where(filter.field, arrayContains: filter.value);
      case FilterOp.whereIn:
        return query.where(filter.field, whereIn: filter.value as List);
    }
  }
}

class QueryFilter {
  final String field;
  final FilterOp operator;
  final dynamic value;

  const QueryFilter(this.field, this.operator, this.value);
}

enum FilterOp {
  isEqualTo,
  isNotEqualTo,
  isLessThan,
  isGreaterThan,
  isLessThanOrEqualTo,
  isGreaterThanOrEqualTo,
  arrayContains,
  whereIn,
}

class BatchOperation {
  final String collection;
  final String docId;
  final BatchType type;
  final Map<String, dynamic>? data;

  const BatchOperation({
    required this.collection,
    required this.docId,
    required this.type,
    this.data,
  });
}

enum BatchType { set, update, delete }
