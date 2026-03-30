import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _databaseName = 'izumi_tracking.db';
  static const _databaseVersion = 3;

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _databaseName);
    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await _createPendingLocationsTable(db);
        await _createOfflineJobsTable(db);
        await _createSessionStateTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createPendingLocationsTable(db);
          await _createOfflineJobsTable(db);
        }
        if (oldVersion < 3) {
          await _createSessionStateTable(db);
          await _addIdempotencyKeyColumn(db);
        }
      },
    );
    return _database!;
  }

  Future<void> _createPendingLocationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        enterprise_id TEXT NOT NULL,
        employee_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        speed REAL,
        heading REAL,
        activity_type TEXT NOT NULL,
        activity_confidence INTEGER,
        cumulative_distance_km REAL NOT NULL,
        captured_at_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createOfflineJobsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_jobs (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        local_file_path TEXT,
        status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        last_attempt_at_ms INTEGER,
        next_attempt_at_ms INTEGER
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_offline_jobs_status_created_at
      ON offline_jobs(status, created_at_ms)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_offline_jobs_next_attempt
      ON offline_jobs(next_attempt_at_ms, created_at_ms)
    ''');
  }

  Future<void> _createSessionStateTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_state (
        id INTEGER PRIMARY KEY,
        session_id TEXT,
        employee_id TEXT,
        enterprise_id TEXT,
        org_id TEXT,
        start_time_ms INTEGER,
        total_distance_km REAL DEFAULT 0,
        last_synced_at_ms INTEGER,
        last_lat REAL,
        last_lng REAL,
        status TEXT DEFAULT 'active'
      )
    ''');
  }

  Future<void> _addIdempotencyKeyColumn(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE offline_jobs ADD COLUMN idempotency_key TEXT',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_offline_jobs_idempotency '
        'ON offline_jobs(idempotency_key)',
      );
    } catch (_) {
      // Column may already exist from a previous partial migration.
    }
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
