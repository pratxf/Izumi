import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'offline_job.dart';

class OfflineJobStore {
  OfflineJobStore._();

  static final OfflineJobStore instance = OfflineJobStore._();

  static const tableName = 'offline_jobs';

  Future<Database> get _database async => AppDatabase.instance.database;

  Future<void> upsertJob(OfflineJob job) async {
    final db = await _database;
    await db.insert(
      tableName,
      job.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Inserts a job only if no existing job has the same [idempotencyKey].
  /// Returns `true` if the row was inserted, `false` if it was skipped.
  Future<bool> insertIfAbsent(OfflineJob job) async {
    final db = await _database;
    final rows = await db.insert(
      tableName,
      job.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return rows != 0;
  }

  Future<OfflineJob?> getJobById(String id) async {
    final db = await _database;
    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : OfflineJob.fromMap(rows.first);
  }

  Future<List<OfflineJob>> getAllJobs() async {
    final db = await _database;
    final rows = await db.query(
      tableName,
      orderBy: 'created_at_ms ASC',
    );
    return rows.map(OfflineJob.fromMap).toList();
  }

  Future<List<OfflineJob>> getJobsByStatuses(
    List<OfflineJobStatus> statuses,
  ) async {
    if (statuses.isEmpty) {
      return const [];
    }

    final db = await _database;
    final placeholders = List.filled(statuses.length, '?').join(', ');
    final rows = await db.query(
      tableName,
      where: 'status IN ($placeholders)',
      whereArgs: statuses.map((status) => status.name).toList(),
      orderBy: 'created_at_ms ASC',
    );
    return rows.map(OfflineJob.fromMap).toList();
  }

  Future<int> countJobsByStatuses(List<OfflineJobStatus> statuses) async {
    if (statuses.isEmpty) {
      return 0;
    }

    final db = await _database;
    final placeholders = List.filled(statuses.length, '?').join(', ');
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $tableName WHERE status IN ($placeholders)',
      statuses.map((status) => status.name).toList(),
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteJob(String id) async {
    final db = await _database;
    await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
