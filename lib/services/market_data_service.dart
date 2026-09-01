import "../database/app_database.dart";
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/candle.dart';
import 'strategy_engine.dart';
import 'notification_service.dart';

/// حالة اتصال WebSocket بشكل صريح - لا نعتمد فقط على كون _channel != null
/// لأن وجود channel لا يعني أن الاتصال حي فعلاً.
enum ConnectionStatus { disconnected, connecting, connected, reconnecting, error, stopped }

/// يتصل ببيانات السوق العامة (Public) من OKX عبر WebSocket - لا يحتاج
/// تسجيل دخول ولا مفاتيح API، فقط رمز التداول (مثل BTC-USDT) والفريم
/// الزمني. هذا يحافظ على مبدأ "فصل تام عن محفظة المستخدم".
///
/// راجع توثيق OKX الرسمي إذا تغيّر شكل القناة أو الرابط مستقبلاً:
/// https://www.okx.com/docs-v5/en/#public-data-websocket-candlesticks-channel
class MarketDataService {
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  DateTime? _lastNotifiedCandleTime;

  MarketDataService({
    required this.instId,
    this.timeframe = '1m',
    this.exchange = 'OKX',
    this.strategy = TradingStrategyPreset.intraday,
  });

  final String instId; // مثال: BTC-USDT
  final String timeframe; // مثال: 1m, 5m, 15m, 1H
  final String exchange;
  final TradingStrategyPreset strategy;

  WebSocketChannel? _channel;
  final List<Candle> _closedCandles = [];
  final StreamController<List<Candle>> _candlesController = StreamController.broadcast();
  final StreamController<List<TradingSignal>> _signalsController = StreamController.broadcast();
  final StreamController<double> _priceController = StreamController.broadcast();
  final StreamController<ConnectionStatus> _statusController = StreamController.broadcast();
  final StreamController<MarketSnapshot> _snapshotController = StreamController.broadcast();

  Stream<List<Candle>> get candlesStream => _candlesController.stream;
  Stream<List<TradingSignal>> get signalsStream => _signalsController.stream;
  Stream<double> get priceStream => _priceController.stream;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  /// لقطة قوة الاتجاه (ADX) وتأكيد الحجم (OBV) - تُبَث حتى عند عدم وجود
  /// إشارة تداول جديدة، حتى تعرض الواجهة سياق السوق الحالي باستمرار.
  Stream<MarketSnapshot> get snapshotStream => _snapshotController.stream;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;

  /// للتوافق مع الشاشات القديمة: نعتبره متصلاً فقط في حالة connected الفعلية.
  bool get isConnected => _status == ConnectionStatus.connected;

  bool _manuallyStopped = false;
  int _reconnectAttempt = 0;

  // تدرّج زمني للمحاولة (Exponential Backoff) بدل محاولة ثابتة كل 5 ثوانٍ:
  // 1s, 2s, 4s, 8s, 16s ثم تبقى عند 30s حتى ينجح الاتصال أو يوقفه المستخدم.
  static const List<int> _backoffSeconds = [1, 2, 4, 8, 16, 30];

  static const Map<String, String> _channelMap = {
    '1m': 'candle1m',
    '5m': 'candle5m',
    '15m': 'candle15m',
    '1H': 'candle1H',
    '4H': 'candle4H',
  };

  void _setStatus(ConnectionStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  void connect() {
    // منع فتح اتصال/اشتراك مكرر إذا كان هناك اتصال جارٍ بالفعل
    if (_status == ConnectionStatus.connecting || _status == ConnectionStatus.connected) {
      return;
    }

    _manuallyStopped = false;
    _reconnectTimer?.cancel();
    _setStatus(_reconnectAttempt > 0 ? ConnectionStatus.reconnecting : ConnectionStatus.connecting);

    AppDatabase.instance
        .getCandles(instId, timeframe: timeframe, exchange: exchange, limit: 300)
        .then((saved) {
      if (saved.isNotEmpty && _closedCandles.isEmpty) {
        _closedCandles.addAll(saved);
        _candlesController.add(List.unmodifiable(_closedCandles));
        _runAnalysis();
      }
    });

    final uri = Uri.parse('wss://ws.okx.com:8443/ws/v5/business');
    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (_) {
      _setStatus(ConnectionStatus.error);
      _scheduleReconnect();
      return;
    }

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      try {
        _channel?.sink.add("ping");
      } catch (e) {
        // سيتم اكتشاف الانقطاع عبر onError/onDone على أي حال
      }
    });

    final channelName = _channelMap[timeframe] ?? 'candle1m';
    try {
      _channel!.sink.add(jsonEncode({
        'op': 'subscribe',
        'args': [
          {'channel': channelName, 'instId': instId}
        ],
      }));
    } catch (_) {
      _setStatus(ConnectionStatus.error);
      _scheduleReconnect();
      return;
    }

    _channel!.stream.listen(
      _handleMessage,
      onError: (e) {
        _setStatus(ConnectionStatus.error);
        _channel = null;
        _scheduleReconnect();
      },
      onDone: () {
        _channel = null;
        if (!_manuallyStopped) {
          // انقطاع غير متوقع (وليس نتيجة استدعاء disconnect() من المستخدم)
          _setStatus(ConnectionStatus.error);
          _scheduleReconnect();
        }
      },
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    if (_manuallyStopped) return;
    _reconnectTimer?.cancel();
    final delayIndex = _reconnectAttempt.clamp(0, _backoffSeconds.length - 1);
    final delay = Duration(seconds: _backoffSeconds[delayIndex]);
    _reconnectAttempt++;
    _setStatus(ConnectionStatus.reconnecting);
    _reconnectTimer = Timer(delay, () {
      if (!_manuallyStopped) connect();
    });
  }

  void _handleMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      if (decoded['event'] != null) {
        // رسالة تأكيد الاشتراك أو خطأ من الخادم
        if (decoded['event'] == 'subscribe') {
          _reconnectAttempt = 0; // نجاح الاتصال يعيد ضبط عداد إعادة المحاولة
          _setStatus(ConnectionStatus.connected);
        } else if (decoded['event'] == 'error') {
          _setStatus(ConnectionStatus.error);
        }
        return;
      }
      final data = decoded['data'] as List?;
      if (data == null || data.isEmpty) return;

      // أي بيانات فعلية تصل تعني أن الاتصال حي وناجح، حتى لو فاتتنا رسالة subscribe
      if (_status != ConnectionStatus.connected) {
        _reconnectAttempt = 0;
        _setStatus(ConnectionStatus.connected);
      }

      for (final row in data) {
        // شكل الصف من OKX: [ts, open, high, low, close, vol, volCcy, volCcyQuote, confirm]
        final ts = int.parse(row[0] as String);
        final open = double.parse(row[1] as String);
        final high = double.parse(row[2] as String);
        final low = double.parse(row[3] as String);
        final close = double.parse(row[4] as String);
        // row[5] = حجم التداول بوحدة الأصل الأساسي (مثال: BTC في BTC-USDT).
        // كانت هذه القيمة تُهمَل سابقاً فيبقى Candle.volume دائماً null، مما
        // يمنع مؤشر OBV من العمل مطلقاً على بيانات السوق الحية.
        final volume = double.tryParse(row[5] as String? ?? '');
        final confirm = row[8] as String; // "1" = الشمعة أُغلقت فعلياً

        if (![open, high, low, close].every((v) => v.isFinite)) continue;

        _priceController.add(close);

        if (confirm == '1') {
          final candle = Candle(
            exchange: exchange,
            symbol: instId,
            timeframe: timeframe,
            time: DateTime.fromMillisecondsSinceEpoch(ts),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: (volume != null && volume.isFinite) ? volume : null,
            confirmed: true,
          );
          // نستبدل آخر شمعة محلياً إن كانت لنفس اللحظة الزمنية بدل إضافة نسخة مكررة
          final existingIndex = _closedCandles.indexWhere((c) => c.time.isAtSameMomentAs(candle.time));
          if (existingIndex >= 0) {
            _closedCandles[existingIndex] = candle;
          } else {
            _closedCandles.add(candle);
          }
          AppDatabase.instance.insertCandle(candle); // upsert بفضل ConflictAlgorithm.replace + القيد الفريد
          // نحتفظ بآخر 300 شمعة فقط لتفادي استهلاك ذاكرة زائد
          if (_closedCandles.length > 300) _closedCandles.removeAt(0);
          _candlesController.add(List.unmodifiable(_closedCandles));
          _runAnalysis();
        }
      }
    } catch (_) {
      // تجاهل أي رسالة لا يمكن تفسيرها (مثل رسائل pong)
    }
  }

  bool _analysisRunning = false;
  bool _analysisPending = false;

  Future<void> _runAnalysis() async {
    if (_closedCandles.length < 30) return; // بيانات غير كافية بعد

    // منع تراكم عمليات تحليل متوازية (Isolates) إذا وصلت شموع بسرعة
    if (_analysisRunning) {
      _analysisPending = true;
      return;
    }
    _analysisRunning = true;

    try {
      final request = AnalysisRequest(
        candleMaps: _closedCandles.map((c) => c.toMap()).toList(),
        emaFastPeriod: strategy.emaFastPeriod,
        emaSlowPeriod: strategy.emaSlowPeriod,
      );

      // تشغيل التحليل في Isolate منفصل حتى لا تتجمد واجهة المستخدم
      final result = await compute(analyzeCandlesForSignals, request);
      final signals = result.signals;

      if (result.snapshot != null && !_snapshotController.isClosed) {
        _snapshotController.add(result.snapshot!);
      }

      if (signals.isNotEmpty) {
        final latestTime = _closedCandles.last.time;
        if (_lastNotifiedCandleTime != null && _lastNotifiedCandleTime!.isAtSameMomentAs(latestTime)) {
          return;
        }
        _lastNotifiedCandleTime = latestTime;
        _signalsController.add(signals);
        for (final s in signals) {
          await NotificationService.showSignalNotification(instId, s);
        }
      }
    } finally {
      _analysisRunning = false;
      if (_analysisPending) {
        _analysisPending = false;
        // شمعة جديدة وصلت أثناء التحليل - نعيد التشغيل مرة واحدة فقط بدل تراكم الطلبات
        unawaited(_runAnalysis());
      }
    }
  }

  void disconnect() {
    _manuallyStopped = true;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.stopped);
  }

  void dispose() {
    disconnect();
    _candlesController.close();
    _signalsController.close();
    _priceController.close();
    _statusController.close();
    _snapshotController.close();
  }
}
