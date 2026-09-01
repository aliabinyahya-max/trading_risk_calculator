import '../models/candle.dart';
import 'candlestick_pattern_service.dart';
import 'indicator_service.dart';

/// إعدادات ثابتة لفترات EMA حسب نوع الاستراتيجية.
/// سابقاً كانت الفترات تتغير تلقائياً (10/30 ثم 50/200) حسب عدد الشموع
/// المتوفرة، وهذا كان يجعل الإشارة في بداية الجلسة مختلفة تماماً عن
/// الإشارة بعد تجميع بيانات كافية. الآن المستخدم يختار استراتيجية ثابتة
/// ولا تتغير الفترات تلقائياً أثناء الجلسة.
enum TradingStrategyPreset { scalping, intraday, swing }

extension TradingStrategyPresetX on TradingStrategyPreset {
  int get emaFastPeriod {
    switch (this) {
      case TradingStrategyPreset.scalping:
        return 9;
      case TradingStrategyPreset.intraday:
        return 20;
      case TradingStrategyPreset.swing:
        return 50;
    }
  }

  int get emaSlowPeriod {
    switch (this) {
      case TradingStrategyPreset.scalping:
        return 21;
      case TradingStrategyPreset.intraday:
        return 50;
      case TradingStrategyPreset.swing:
        return 200;
    }
  }

  String get label {
    switch (this) {
      case TradingStrategyPreset.scalping:
        return 'سكالبينغ (EMA 9/21)';
      case TradingStrategyPreset.intraday:
        return 'يومي (EMA 20/50)';
      case TradingStrategyPreset.swing:
        return 'سوينغ (EMA 50/200)';
    }
  }
}

enum SignalDirection { buy, sell }

class TradingSignal {
  final SignalDirection direction;
  final String reason;
  final DateTime detectedAt;

  TradingSignal({
    required this.direction,
    required this.reason,
    required this.detectedAt,
  });

  Map<String, dynamic> toMap() => {
        'direction': direction.name,
        'reason': reason,
        'detectedAt': detectedAt.toIso8601String(),
      };

  factory TradingSignal.fromMap(Map<String, dynamic> map) => TradingSignal(
        direction: SignalDirection.values.firstWhere((e) => e.name == map['direction']),
        reason: map['reason'] as String,
        detectedAt: DateTime.parse(map['detectedAt'] as String),
      );
}

/// نظام السوق الحالي المُستنتَج من ADX - اتجاهي أم عرضي.
enum MarketRegime { trending, ranging, unknown }

/// لقطة سريعة عن حالة السوق (بمعزل عن الإشارات نفسها) حتى تظهر واجهة
/// "السوق المباشر" سياقاً مستمراً (قوة الاتجاه، تأكيد الحجم) وليس فقط
/// الإشارات المتقطعة.
class MarketSnapshot {
  final MarketRegime regime;
  final double? adxValue;
  final String regimeInterpretation;
  final String? obvInterpretation;

  MarketSnapshot({
    required this.regime,
    required this.adxValue,
    required this.regimeInterpretation,
    required this.obvInterpretation,
  });
}

class AnalysisResult {
  final List<TradingSignal> signals;
  final MarketSnapshot? snapshot;

  AnalysisResult({required this.signals, required this.snapshot});
}

class AnalysisRequest {
  final List<Map<String, dynamic>> candleMaps;
  final int emaFastPeriod;
  final int emaSlowPeriod;

  AnalysisRequest({
    required this.candleMaps,
    this.emaFastPeriod = 50,
    this.emaSlowPeriod = 200,
  });
}

/// نقطة الدخول المستخدمة مباشرة عبر compute() في market_data_service وعبر
/// محرك الباك-تيست. تبقى دالة نقية (Pure Function) بلا حالة داخلية حتى تصلح
/// للتشغيل داخل Isolate منفصل ولإعادة الاستخدام في الباك-تيست دون فروقات.
AnalysisResult analyzeCandlesForSignals(AnalysisRequest request) {
  final candles = request.candleMaps.map((m) => Candle.fromMap(m)).toList();
  final List<TradingSignal> signals = [];

  if (candles.length < request.emaSlowPeriod + 2) {
    return AnalysisResult(signals: signals, snapshot: null);
  }

  final emaFast = IndicatorService.ema(candles, request.emaFastPeriod);
  final emaSlow = IndicatorService.ema(candles, request.emaSlowPeriod);
  final rsi = IndicatorService.rsi(candles);
  final patterns = CandlestickPatternService.detectAll(candles);

  final adxResult = IndicatorService.adx(candles);
  final adxValue = adxResult['adx']!.latestValue;
  final obvResult = IndicatorService.obv(candles);

  MarketRegime regime;
  if (adxValue == null) {
    regime = MarketRegime.unknown;
  } else if (adxValue >= 25) {
    regime = MarketRegime.trending;
  } else if (adxValue <= 20) {
    regime = MarketRegime.ranging;
  } else {
    regime = MarketRegime.unknown;
  }

  final snapshot = MarketSnapshot(
    regime: regime,
    adxValue: adxValue,
    regimeInterpretation: adxResult['adx']!.interpretation,
    obvInterpretation: obvResult?.interpretation,
  );

  final lastIndex = candles.length - 1;
  final prevIndex = lastIndex - 1;

  final fastNow = emaFast[lastIndex];
  final slowNow = emaSlow[lastIndex];
  final fastPrev = emaFast[prevIndex];
  final slowPrev = emaSlow[prevIndex];

  // فحص أنماط الشموع المتكونة في آخر شمعتين (الآن أو التأكيد السابق)
  final recentPatterns = patterns.where((p) => p.candleIndex >= prevIndex).toList();
  final bullishPattern = recentPatterns.where((p) => p.signal == PatternSignal.bullish).firstOrNull;
  final bearishPattern = recentPatterns.where((p) => p.signal == PatternSignal.bearish).firstOrNull;

  final rsiValue = rsi.latestValue;
  final now = DateTime.now();

  bool buyTriggered = false;
  bool sellTriggered = false;

  // نمنع إشارات تقاطع EMA فقط عندما يكون ADX يؤكد صراحة سوقاً عرضياً
  // (Ranging) - وهي الحالة التي يكثر فيها تذبذب EMA حول بعضه (Whipsaw).
  // إذا كانت بيانات ADX غير كافية بعد (unknown) نسمح بالإشارة كالسابق
  // بدل حجبها بسبب نقص بيانات وحسب.
  final crossoverAllowed = regime != MarketRegime.ranging;

  if (crossoverAllowed && fastNow != null && slowNow != null && fastPrev != null && slowPrev != null) {
    final bullishCross = fastPrev <= slowPrev && fastNow > slowNow;
    final bearishCross = fastPrev >= slowPrev && fastNow < slowNow;

    if (bullishCross) {
      buyTriggered = true;
      final extraPattern = bullishPattern != null ? ' مدعوم بنمط (${bullishPattern.nameAr})' : '';
      final extraRsi = (rsiValue != null && rsiValue < 70) ? ' و RSI آمن (${rsiValue.toStringAsFixed(1)})' : '';
      final obvNote = _obvNote(obvResult, bullish: true);
      signals.add(TradingSignal(
        direction: SignalDirection.buy,
        reason: 'تقاطع EMA${request.emaFastPeriod} صعودياً فوق EMA${request.emaSlowPeriod}$extraPattern$extraRsi$obvNote',
        detectedAt: now,
      ));
    }

    if (bearishCross) {
      sellTriggered = true;
      final extraPattern = bearishPattern != null ? ' مدعوم بنمط (${bearishPattern.nameAr})' : '';
      final extraRsi = (rsiValue != null && rsiValue > 30) ? ' و RSI آمن (${rsiValue.toStringAsFixed(1)})' : '';
      final obvNote = _obvNote(obvResult, bullish: false);
      signals.add(TradingSignal(
        direction: SignalDirection.sell,
        reason: 'تقاطع EMA${request.emaFastPeriod} هبوطياً تحت EMA${request.emaSlowPeriod}$extraPattern$extraRsi$obvNote',
        detectedAt: now,
      ));
    }
  }

  // تشبع بيعي مع نمط انعكاسي صعودي (إذا لم تصدر إشارة شراء مسبقاً)
  // إشارات الارتداد من التشبع هذه تبقى مسموحة في كل الأنظمة (بما فيها
  // السوق العرضي) لأنها أصلاً الإشارة الأنسب للسوق العرضي، بعكس تقاطع EMA.
  if (!buyTriggered && rsiValue != null && rsiValue <= 30 && bullishPattern != null) {
    final obvNote = _obvNote(obvResult, bullish: true);
    signals.add(TradingSignal(
      direction: SignalDirection.buy,
      reason: 'تشبع بيعي (RSI ${rsiValue.toStringAsFixed(1)}) مدعوم بنمط (${bullishPattern.nameAr})$obvNote',
      detectedAt: now,
    ));
  }

  // تشبع شرائي مع نمط انعكاسي هبوطي (إذا لم تصدر إشارة بيع مسبقاً)
  if (!sellTriggered && rsiValue != null && rsiValue >= 70 && bearishPattern != null) {
    final obvNote = _obvNote(obvResult, bullish: false);
    signals.add(TradingSignal(
      direction: SignalDirection.sell,
      reason: 'تشبع شرائي (RSI ${rsiValue.toStringAsFixed(1)}) مدعوم بنمط (${bearishPattern.nameAr})$obvNote',
      detectedAt: now,
    ));
  }

  return AnalysisResult(signals: signals, snapshot: snapshot);
}

/// يضيف ملاحظة قصيرة عن تأكيد/تباعد حجم التداول (OBV) لنص سبب الإشارة.
/// [bullish] يمثل اتجاه الإشارة المُراد التحقق من تأكيد الحجم لها.
/// يرجع نصاً فارغاً إذا لم تتوفر بيانات حجم (مثل الشموع المُدخلة يدوياً).
String _obvNote(IndicatorResult? obvResult, {required bool bullish}) {
  if (obvResult == null) return '';
  final interpretation = obvResult.interpretation;
  final confirms = bullish ? interpretation.contains('يؤكد الاتجاه الصعودي') : interpretation.contains('يؤكد الاتجاه الهبوطي');
  final diverges = interpretation.contains('تباعد');
  if (confirms) return ' ومؤكد بحجم التداول (OBV)';
  if (diverges) return ' ⚠️ لكن حجم التداول يُظهر تباعداً';
  return '';
}
