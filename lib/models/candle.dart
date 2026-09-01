class Candle {
  final int? id;
  final String exchange;
  final String symbol;
  final String timeframe;
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double? volume;
  final bool confirmed;

  Candle({
    this.id,
    this.exchange = 'OKX',
    required this.symbol,
    this.timeframe = '1m',
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
    this.confirmed = true,
  });

  bool get isBullish => close > open;
  bool get isBearish => close < open;
  double get body => (close - open).abs();
  double get range => high - low;
  double get upperWick => high - (isBullish ? close : open);
  double get lowerWick => (isBullish ? open : close) - low;

  Map<String, dynamic> toMap() => {
        'id': id,
        'exchange': exchange,
        'symbol': symbol,
        'timeframe': timeframe,
        'time': time.toIso8601String(),
        // نخزن الطابع الزمني كـ epoch ms أيضاً لتسهيل فهرسة/فرز رقمي دقيق
        'timestampMs': time.millisecondsSinceEpoch,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
        'confirmed': confirmed ? 1 : 0,
      };

  factory Candle.fromMap(Map<String, dynamic> map) => Candle(
        id: map['id'] as int?,
        exchange: (map['exchange'] as String?) ?? 'OKX',
        symbol: map['symbol'] as String,
        timeframe: (map['timeframe'] as String?) ?? '1m',
        time: DateTime.parse(map['time'] as String),
        open: (map['open'] as num).toDouble(),
        high: (map['high'] as num).toDouble(),
        low: (map['low'] as num).toDouble(),
        close: (map['close'] as num).toDouble(),
        volume: map['volume'] == null ? null : (map['volume'] as num).toDouble(),
        confirmed: map['confirmed'] == null ? true : (map['confirmed'] as int) == 1,
      );
}
