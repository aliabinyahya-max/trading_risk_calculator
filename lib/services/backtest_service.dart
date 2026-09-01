import '../models/candle.dart';
import '../models/trade.dart';
import 'risk_service.dart';
import 'strategy_engine.dart';

enum BacktestOutcome { win, loss, timeout }

class BacktestTradeOutcome {
  final DateTime entryTime;
  final SignalDirection direction;
  final double entryPrice;
  final double stopLossPrice;
  final double takeProfitPrice;
  final BacktestOutcome outcome;
  final double rMultiple; // موجب = ربح بمضاعفات R (المخاطرة الأصلية)، -1 = خسارة كاملة، 0 = لم تُغلَق بعد
  final DateTime? exitTime;

  BacktestTradeOutcome({
    required this.entryTime,
    required this.direction,
    required this.entryPrice,
    required this.stopLossPrice,
    required this.takeProfitPrice,
    required this.outcome,
    required this.rMultiple,
    required this.exitTime,
  });
}

class BacktestSummary {
  /// الصفقات التي وصلت لنتيجة حاسمة فقط (ربح أو خسارة) - تُستبعد صفقات
  /// انتهاء المهلة (timeout) من حساب نسبة الفوز والمتوسط لأنها لم تُحسَم بعد.
  final int totalTrades;
  final int wins;
  final int losses;
  final int timeouts;
  final double winRatePercent;
  final double avgRMultiple; // "التوقع" (Expectancy) بمضاعفات R لكل صفقة
  final double totalRMultiple;
  final List<BacktestTradeOutcome> trades;

  BacktestSummary({
    required this.totalTrades,
    required this.wins,
    required this.losses,
    required this.timeouts,
    required this.winRatePercent,
    required this.avgRMultiple,
    required this.totalRMultiple,
    required this.trades,
  });
}

class BacktestRequest {
  final List<Map<String, dynamic>> candleMaps;
  final int emaFastPeriod;
  final int emaSlowPeriod;
  final double riskRewardRatio;
  final double atrMultiplier;
  final int maxHoldingCandles;

  BacktestRequest({
    required this.candleMaps,
    required this.emaFastPeriod,
    required this.emaSlowPeriod,
    this.riskRewardRatio = 2,
    this.atrMultiplier = 1.5,
    this.maxHoldingCandles = 100,
  });
}

/// يشغّل الاستراتيجية (نفس منطق [analyzeCandlesForSignals] المستخدم في
/// السوق المباشر تماماً - حتى تكون نتيجة الباك-تيست ممثلة فعلاً لما كان
/// سيحدث لو كان المستخدم يتابع نفس الإشارات وقتها) على بيانات تاريخية،
/// ثم يحاكي تنفيذ صفقة واحدة في كل مرة بوقف خسارة مبني على ATR ونسبة R:R
/// محددة، ويسجّل هل كانت لتصل للهدف أو للوقف أولاً.
///
/// ⚠️ قيد منهجي مهم: بيانات الشموع (OHLC) لا تخبرنا بترتيب حركة السعر
/// *داخل* الشمعة نفسها. إذا لامست شمعة واحدة كلاً من الوقف والهدف، نفترض
/// دائماً أن الوقف أُصيب أولاً (السيناريو الأسوأ) بدل افتراض تفاؤلي - هذا
/// يجعل نتائج الباك-تيست متحفظة عمداً بدل مُتفائلة زيادة عن الواقع.
BacktestSummary runBacktest(BacktestRequest request) {
  final allCandles = request.candleMaps.map((m) => Candle.fromMap(m)).toList();
  final trades = <BacktestTradeOutcome>[];

  final minCandlesForSignal = request.emaSlowPeriod + 2;
  if (allCandles.length < minCandlesForSignal + 5) {
    return BacktestSummary(
      totalTrades: 0,
      wins: 0,
      losses: 0,
      timeouts: 0,
      winRatePercent: 0,
      avgRMultiple: 0,
      totalRMultiple: 0,
      trades: trades,
    );
  }

  int i = minCandlesForSignal;
  while (i < allCandles.length) {
    // نمرر فقط الشموع المتوفرة "حتى تلك اللحظة" - نفس ما كان المستخدم
    // سيراه فعلياً وقتها، بدون أي تسريب لبيانات مستقبلية (Look-ahead Bias).
    final windowCandles = allCandles.sublist(0, i + 1);
    final analysisRequest = AnalysisRequest(
      candleMaps: windowCandles.map((c) => c.toMap()).toList(),
      emaFastPeriod: request.emaFastPeriod,
      emaSlowPeriod: request.emaSlowPeriod,
    );
    final result = analyzeCandlesForSignals(analysisRequest);

    if (result.signals.isEmpty) {
      i++;
      continue;
    }

    // نأخذ أول إشارة فقط في هذه اللحظة - نمذجة لمتداول واحد يفتح صفقة
    // واحدة كل مرة، بدل فتح عدة صفقات متعارضة الاتجاه في نفس اللحظة.
    final signal = result.signals.first;
    final entryCandle = allCandles[i];
    final entryPrice = entryCandle.close;
    final direction = signal.direction == SignalDirection.buy ? TradeDirection.long : TradeDirection.short;

    final stopLoss = RiskService.suggestStopLossFromAtr(
      candles: windowCandles,
      entryPrice: entryPrice,
      direction: direction,
      multiplier: request.atrMultiplier,
    );

    if (stopLoss == null) {
      // بيانات ATR غير كافية بعد عند هذه النقطة - نتجاهل هذه الإشارة تحديداً
      i++;
      continue;
    }

    final distance = (entryPrice - stopLoss).abs();
    final takeProfit = direction == TradeDirection.long
        ? entryPrice + distance * request.riskRewardRatio
        : entryPrice - distance * request.riskRewardRatio;

    BacktestOutcome outcome = BacktestOutcome.timeout;
    DateTime? exitTime;
    final searchEnd = (i + 1 + request.maxHoldingCandles).clamp(0, allCandles.length);
    int j = i + 1;
    for (; j < searchEnd; j++) {
      final c = allCandles[j];
      final hitSl = direction == TradeDirection.long ? c.low <= stopLoss : c.high >= stopLoss;
      final hitTp = direction == TradeDirection.long ? c.high >= takeProfit : c.low <= takeProfit;

      if (hitSl) {
        // السيناريو الأسوأ إذا لامست الشمعة الهدف والوقف معاً (راجع التنويه أعلى الدالة)
        outcome = BacktestOutcome.loss;
        exitTime = c.time;
        break;
      } else if (hitTp) {
        outcome = BacktestOutcome.win;
        exitTime = c.time;
        break;
      }
    }

    final rMultiple = switch (outcome) {
      BacktestOutcome.win => request.riskRewardRatio,
      BacktestOutcome.loss => -1.0,
      BacktestOutcome.timeout => 0.0,
    };

    trades.add(BacktestTradeOutcome(
      entryTime: entryCandle.time,
      direction: signal.direction,
      entryPrice: entryPrice,
      stopLossPrice: stopLoss,
      takeProfitPrice: takeProfit,
      outcome: outcome,
      rMultiple: rMultiple,
      exitTime: exitTime,
    ));

    // نتقدّم إلى ما بعد إغلاق هذه الصفقة (أو بعد انتهاء مهلة البحث إن لم
    // تُغلَق) بدل فتح صفقة جديدة كل شمعة - محاكاة لمتداول واحد بلا تراكم.
    i = exitTime != null ? j + 1 : searchEnd;
  }

  final concluded = trades.where((t) => t.outcome != BacktestOutcome.timeout).toList();
  final wins = concluded.where((t) => t.outcome == BacktestOutcome.win).length;
  final losses = concluded.where((t) => t.outcome == BacktestOutcome.loss).length;
  final timeouts = trades.length - concluded.length;
  final winRate = concluded.isEmpty ? 0.0 : (wins / concluded.length) * 100;
  final totalR = concluded.fold<double>(0, (sum, t) => sum + t.rMultiple);
  final avgR = concluded.isEmpty ? 0.0 : totalR / concluded.length;

  return BacktestSummary(
    totalTrades: concluded.length,
    wins: wins,
    losses: losses,
    timeouts: timeouts,
    winRatePercent: winRate,
    avgRMultiple: avgR,
    totalRMultiple: totalR,
    trades: trades,
  );
}
