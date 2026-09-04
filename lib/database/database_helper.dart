import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/poker_record.dart';
import '../models/exchange_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'poker_tracker.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE poker_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_time INTEGER NOT NULL,
        duration REAL NOT NULL DEFAULT 0,
        location TEXT NOT NULL,
        currency TEXT NOT NULL,
        amount REAL NOT NULL,
        blind_level TEXT NOT NULL,
        remark TEXT,
        table_type TEXT,
        hand_notes TEXT,
        trip_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    // 预设澳门主流赌场（保留四家常用）
    final presetLocations = [
      '威尼斯人 (Venetian)',
      '永利 (Wynn)',
      '美狮美高梅 (MGM)',
      '上葡京 (Lisboa Palace)',
    ];

    for (final loc in presetLocations) {
      await db.insert('locations', {'name': loc});
    }

    // 港币存取兑换流水表
    await db.execute('''
      CREATE TABLE exchange_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        create_time INTEGER NOT NULL,
        hkd_cash REAL NOT NULL,
        bank_cny REAL NOT NULL,
        actual_rate REAL NOT NULL,
        fee_hkd REAL NOT NULL DEFAULT 0,
        remark TEXT
      )
    ''');
  }

  // ========== 账目记录操作 ==========

  Future<int> insertRecord(PokerRecord record) async {
    final db = await database;
    return await db.insert('poker_records', record.toMap()..remove('id'));
  }

  Future<int> updateRecord(PokerRecord record) async {
    final db = await database;
    return await db.update(
      'poker_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<int> deleteRecord(int id) async {
    final db = await database;
    return await db.delete(
      'poker_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PokerRecord>> getAllRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'poker_records',
      orderBy: 'record_time DESC',
    );
    return maps.map((map) => PokerRecord.fromMap(map)).toList();
  }

  /// 按月份筛选记录
  Future<List<PokerRecord>> getRecordsByMonth(int year, int month) async {
    final db = await database;
    final startOfMonth = DateTime(year, month, 1).millisecondsSinceEpoch;
    final endOfMonth = DateTime(year, month + 1, 1).millisecondsSinceEpoch;

    final List<Map<String, dynamic>> maps = await db.query(
      'poker_records',
      where: 'record_time >= ? AND record_time < ?',
      whereArgs: [startOfMonth, endOfMonth],
      orderBy: 'record_time DESC',
    );
    return maps.map((map) => PokerRecord.fromMap(map)).toList();
  }

  Future<void> insertRecords(List<PokerRecord> records) async {
    final db = await database;
    final batch = db.batch();
    for (final r in records) {
      batch.insert('poker_records', r.toMap()..remove('id'));
    }
    await batch.commit(continueOnError: false);
  }

  // ========== 地点管理 ==========

  Future<List<String>> getAllLocations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'locations',
      orderBy: 'name ASC',
    );
    return maps.map((map) => map['name'] as String).toList();
  }

  /// 数据库升级回调（预留，便于后续加字段/改表结构）
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE poker_records ADD COLUMN table_type TEXT');
      await db.execute('ALTER TABLE poker_records ADD COLUMN hand_notes TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE poker_records ADD COLUMN cny_amount REAL');
    }
    if (oldVersion < 4) {
      // 老库（v1/v2 直升）可能没有 exchange_records，先补建再迁移
      await db.execute('''
        CREATE TABLE IF NOT EXISTS exchange_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          create_time INTEGER NOT NULL,
          hkd_cash REAL NOT NULL,
          bank_cny REAL NOT NULL,
          actual_rate REAL NOT NULL,
          fee_hkd REAL NOT NULL DEFAULT 0,
          remark TEXT
        )
      ''');
      await db.execute('ALTER TABLE poker_records ADD COLUMN trip_id INTEGER');
    }
  }

  Future<int> addLocation(String name) async {
    final db = await database;
    try {
      return await db.insert('locations', {'name': name});
    } catch (_) {
      return 0; // 已存在则忽略
    }
  }

  // ========== 港币存取兑换流水操作 ==========

  Future<int> insertExchangeRecord(ExchangeRecord record) async {
    final db = await database;
    return await db.insert('exchange_records', record.toMap()..remove('id'));
  }

  Future<int> updateExchangeRecord(ExchangeRecord record) async {
    final db = await database;
    return await db.update(
      'exchange_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<int> deleteExchangeRecord(int id) async {
    final db = await database;
    return await db.delete(
      'exchange_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ExchangeRecord>> getAllExchangeRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'exchange_records',
      orderBy: 'create_time DESC',
    );
    return maps.map((map) => ExchangeRecord.fromMap(map)).toList();
  }

  // ========== 行程分界操作 ==========

  /// 批量设置记录的行程归属（tripId 为 null 表示归入未分组）
  Future<void> assignTrip(List<int> ids, int? tripId) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      'poker_records',
      {'trip_id': tripId},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// 当前最大行程 id（无则 0）
  Future<int> maxTripId() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT MAX(trip_id) AS m FROM poker_records');
    return (rows.first['m'] as int?) ?? 0;
  }
}
