import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/trade.dart';
import '../models/candle.dart';

/// طبقة تخزين محلي بسيطة (Offline-first) باستخدام sqflite.
/// لا تحتاج build_runner أو أي توليد كود، وتعمل مباشرة بعد flutter pub get.
class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  static Database? _db;

  // إصدار 3: جدول candles أصبح يحتوي exchange/timeframe/confirmed
  // + قيد UNIQUE(exchange, symbol, timeframe, timestampMs) لمنع تكرار
  // نفس الشمعة عند إعادة الاتصال أو إعادة الاشتراك بالـ WebSocket.
  // إصدار 4: جدول trades أصبح يحتوي حقول محرك المخاطرة الاحترافي
  // (رافعة، رسوم، انزلاق، هامش مطلوب...) - المرحلة 2.
  static const int _dbVersion = 4;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'trading_risk_calculator.db');

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createTradesTable(db);
        await _createCandlesTableV3(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // لم يكن هناك جدول candles بعد (تثبيت قديم جداً) - ننشئه مباشرة بالبنية الجديدة
          await _createCandlesTableV3(db);
        } else if (oldVersion == 2) {
          // كان هناك جدول candles بالبنية القديمة (بدون timeframe/exchange وبدون قيد فريد)
          await _migrateCandlesV2ToV3(db);
        }
        if (oldVersion < 4) {
          await _addRiskEngineColumnsToTrades(db);
        }
      },
    );
  }

  Future<void> _createTradesTable(Database db) async {
    await db.execute('''
      CREATE TABLE trades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        symbol TEXT NOT NULL,
        direction TEXT NOT NULL,
        accountBalance REAL NOT NULL,
        riskPercent REAL NOT NULL,
        entryPrice REAL NOT NULL,
        stopLossPrice REAL NOT NULL,
        riskRewardRatio REAL NOT NULL,
        positionSize REAL NOT NULL,
        riskAmount REAL NOT NULL,
        takeProfitPrice REAL NOT NULL,
        createdAt TEXT NOT NULL,
        notes TEXT,
        marketType TEXT NOT NULL DEFAULT 'spot',
        leverage REAL NOT NULL DEFAULT 1,
        feePercent REAL NOT NULL DEFAULT 0,
        slippagePercent REAL NOT NULL DEFAULT 0,
        requiredMargin REAL NOT NULL DEFAULT 0,
        estimatedFee REAL NOT NULL DEFAULT 0,
        estimatedSlippage REAL NOT NULL DEFAULT 0,
        maxLoss REAL NOT NULL DEFAULT 0,
        netRiskRewardRatio REAL
      )
    ''');
  }

  /// يضيف أعمدة محرك المخاطرة الاحترافي لجدول trades القديم (قبل v4).
  /// نستخدم ALTER TABLE ADD COLUMN لأنها آمنة على البيانات الموجودة
  /// (بعكس إعادة إنشاء الجدول التي احتجناها لجدول candles بسبب القيد الفريد).
  Future<void> _addRiskEngineColumnsToTrades(Database db) async {
    final existingColumns = (await db.rawQuery('PRAGMA table_info(trades)'))
        .map((row) => row['name'] as String)
        .toSet();

    final columnsToAdd = <String, String>{
      'marketType': "TEXT NOT NULL DEFAULT 'spot'",
      'leverage': 'REAL NOT NULL DEFAULT 1',
      'feePercent': 'REAL NOT NULL DEFAULT 0',
      'slippagePercent': 'REAL NOT NULL DEFAULT 0',
      'requiredMargin': 'REAL NOT NULL DEFAULT 0',
      'estimatedFee': 'REAL NOT NULL DEFAULT 0',
      'estimatedSlippage': 'REAL NOT NULL DEFAULT 0',
      'maxLoss': 'REAL NOT NULL DEFAULT 0',
      'netRiskRewardRatio': 'REAL',
    };

    for (final entry in columnsToAdd.entries) {
      if (!existingColumns.contains(entry.key)) {
        await db.execute('ALTER TABLE trades ADD COLUMN ${entry.key} ${entry.value}');
      }
    }
  }

  Future<void> _createCandlesTableV3(Database db) async {
    await db.execute('''
      CREATE TABLE candles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exchange TEXT NOT NULL DEFAULT 'OKX',
        symbol TEXT NOT NULL,
        timeframe TEXT NOT NULL DEFAULT '1m',
        timestampMs INTEGER NOT NULL,
        time TEXT NOT NULL,
        open REAL NOT NULL,
        high REAL NOT NULL,
        low REAL NOT NULL,
        close REAL NOT NULL,
        volume REAL,
        confirmed INTEGER NOT NULL DEFAULT 1,
        UNIQUE(exchange, symbol, timeframe, timestampMs)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_candles_lookup ON candles(exchange, symbol, timeframe, timestampMs)',
    );
  }

  /// يهاجر بيانات جدول candles القديم (v2) إلى البنية الجديدة (v3).
  /// نفترض timeframe='1m' للبيانات القديمة لأنها لم تكن تُسجَّل أصلاً،
  /// ونستخدم INSERT OR IGNORE لتفادي أي تكرار موجود مسبقاً في البيانات القديمة.
  Future<void> _migrateCandlesV2ToV3(Database db) async {
    await db.execute('ALTER TABLE candles RENAME TO candles_old');
    await _createCandlesTableV3(db);
    try {
      await db.execute('''
        INSERT OR IGNORE INTO candles
          (exchange, symbol, timeframe, timestampMs, time, open, high, low, close, volume, confirmed)
        SELECT
          'OKX', symbol, '1m',
          CAST(strftime('%s', time) AS INTEGER) * 1000,
          time, open, high, low, close, volume, 1
        FROM candles_old
      ''');
    } finally {
      await db.execute('DROP TABLE candles_old');
    }
  }

  // ---------------- Trades ----------------

  Future<int> insertTrade(Trade trade) async {
    final db = await database;
    return db.insert('trades', trade.toMap()..remove('id'));
  }

  Future<List<Trade>> getAllTrades() async {
    final db = await database;
    final maps = await db.query('trades', orderBy: 'createdAt DESC');
    return maps.map((m) => Trade.fromMap(m)).toList();
  }

  Future<int> deleteTrade(int id) async {
    final db = await database;
    return db.delete('trades', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete('trades');
  }

  // ---------------- Candles ----------------

  /// إدخال شمعة واحدة. يستخدم ConflictAlgorithm.replace حتى لو وصلت نفس
  /// الشمعة (نفس exchange/symbol/timeframe/timestampMs) أكثر من مرة بسبب
  /// إعادة اتصال WebSocket، يتم تحديثها بدلاً من تكرارها.
  Future<int> insertCandle(Candle candle) async {
    final db = await database;
    return db.insert(
      'candles',
      candle.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// إدخال عدة شموع دفعة واحدة (مثلاً بعد لصق بيانات من المنصة)
  Future<void> insertCandles(List<Candle> candles) async {
    final db = await database;
    final batch = db.batch();
    for (final c in candles) {
      batch.insert(
        'candles',
        c.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// يرجع الشموع مرتبة تصاعدياً بالوقت (الأقدم أولاً) - وهو الترتيب
  /// الذي تحتاجه خدمات التحليل (الأنماط والمؤشرات).
  ///
  /// [timeframe] و[exchange] اختياريان: عند تمريرهما يتم تصفية النتائج
  /// عليهما، لأن نفس الرمز يمكن أن يملك شموعاً على أكثر من فريم زمني
  /// الآن بعد إضافة عمود timeframe.
  Future<List<Candle>> getCandles(
    String symbol, {
    String? timeframe,
    String? exchange,
    int? limit,
  }) async {
    final db = await database;
    final where = StringBuffer('symbol = ?');
    final whereArgs = <Object?>[symbol];
    if (timeframe != null) {
      where.write(' AND timeframe = ?');
      whereArgs.add(timeframe);
    }
    if (exchange != null) {
      where.write(' AND exchange = ?');
      whereArgs.add(exchange);
    }

    // عند تحديد limit، نريد أحدث N شمعة (وليس أقدم N شمعة) - لذلك نرتب
    // تنازلياً أولاً لأخذ الأحدث ضمن الحد، ثم نعكس الترتيب لصعودي زمنياً
    // قبل الإرجاع. بدون هذا العكس، كانت الاستدعاءات التي تراكم فيها آلاف
    // الشموع بمرور الوقت (بعد عدة جلسات) تحصل دائماً على أقدم N شمعة
    // فقط (بيانات قديمة جامدة) بدل النافذة الأحدث الفعلية - وهذا يؤثر
    // مباشرة على استئناف "السوق المباشر" وعلى دقة الباك-تيست.
    final maps = await db.query(
      'candles',
      where: where.toString(),
      whereArgs: whereArgs,
      orderBy: limit != null ? 'timestampMs DESC' : 'timestampMs ASC',
      limit: limit,
    );
    final candles = maps.map((m) => Candle.fromMap(m)).toList();
    if (limit != null) {
      return candles.reversed.toList();
    }
    return candles;
  }

  Future<List<String>> getSymbolsWithCandles() async {
    final db = await database;
    final result = await db.rawQuery('SELECT DISTINCT symbol FROM candles ORDER BY symbol');
    return result.map((r) => r['symbol'] as String).toList();
  }

  Future<int> deleteCandle(int id) async {
    final db = await database;
    return db.delete('candles', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCandlesForSymbol(String symbol) async {
    final db = await database;
    await db.delete('candles', where: 'symbol = ?', whereArgs: [symbol]);
  }
}
