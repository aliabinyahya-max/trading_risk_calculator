import 'dart:math' as math;
import '../models/candle.dart';

class IndicatorResult {
  final String name;
  final double? latestValue;
  final List<double?> series;
  final String interpretation;

  IndicatorResult({
    required this.name,
    required this.latestValue,
    required this.series,
    required this.interpretation,
  });
}

class IndicatorService {
  static List<double?> sma(List<Candle> candles, int period) {
    final closes = candles.map((c) => c.close).toList();
    final List<double?> out = List.filled(closes.length, null);
    for (int i = period - 1; i < closes.length; i++) {
      final window = closes.sublist(i - period + 1, i + 1);
      out[i] = window.reduce((a, b) => a + b) / period;
    }
    return out;
  }

  static List<double?> ema(List<Candle> candles, int period) {
    final closes = candles.map((c) => c.close).toList();
    final List<double?> out = List.filled(closes.length, null);
    if (closes.length < period) return out;

    final k = 2 / (period + 1);
    double emaPrev = closes.sublist(0, period).reduce((a, b) => a + b) / period;
    out[period - 1] = emaPrev;
    for (int i = period; i < closes.length; i++) {
      emaPrev = closes[i] * k + emaPrev * (1 - k);
      out[i] = emaPrev;
    }
    return out;
  }

  static IndicatorResult rsi(List<Candle> candles, {int period = 14}) {
    final closes = candles.map((c) => c.close).toList();
    final List<double?> out = List.filled(closes.length, null);

    if (closes.length <= period) {
      return IndicatorResult(name: 'RSI', latestValue: null, series: out, interpretation: 'بيانات غير كافية (يحتاج ${period + 1} شمعة على الأقل)');
    }

    double gainSum = 0;
    double lossSum = 0;
    for (int i = 1; i <= period; i++) {
      final change = closes[i] - closes[i - 1];
      if (change >= 0) {
        gainSum += change;
      } else {
        lossSum += -change;
      }
    }
    double avgGain = gainSum / period;
    double avgLoss = lossSum / period;
    out[period] = _rsiFromAvg(avgGain, avgLoss);

    for (int i = period + 1; i < closes.length; i++) {
      final change = closes[i] - closes[i - 1];
      final gain = change > 0 ? change : 0.0;
      final loss = change < 0 ? -change : 0.0;
      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;
      out[i] = _rsiFromAvg(avgGain, avgLoss);
    }

    final latest = out.last;
    String interpretation;
    if (latest == null) {
      interpretation = 'بيانات غير كافية';
    } else if (latest >= 70) {
      interpretation = 'تشبع شرائي (Overbought) - احتمال تصحيح هبوطي';
    } else if (latest <= 30) {
      interpretation = 'تشبع بيعي (Oversold) - احتمال ارتداد صعودي';
    } else {
      interpretation = 'منطقة محايدة';
    }

    return IndicatorResult(name: 'RSI ($period)', latestValue: latest, series: out, interpretation: interpretation);
  }

  static double _rsiFromAvg(double avgGain, double avgLoss) {
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  static Map<String, IndicatorResult> macd(
    List<Candle> candles, {
    int fastPeriod = 12,
    int slowPeriod = 26,
    int signalPeriod = 9,
  }) {
    final fastEma = ema(candles, fastPeriod);
    final slowEma = ema(candles, slowPeriod);

    final List<double?> macdLine = List.filled(candles.length, null);
    for (int i = 0; i < candles.length; i++) {
      if (fastEma[i] != null && slowEma[i] != null) {
        macdLine[i] = fastEma[i]! - slowEma[i]!;
      }
    }

    final List<double?> signalLine = List.filled(candles.length, null);
    final validIndices = <int>[];
    for (int i = 0; i < macdLine.length; i++) {
      if (macdLine[i] != null) validIndices.add(i);
    }
    if (validIndices.length >= signalPeriod) {
      final k = 2 / (signalPeriod + 1);
      final firstWindow = validIndices.sublist(0, signalPeriod).map((idx) => macdLine[idx]!).toList();
      double emaPrev = firstWindow.reduce((a, b) => a + b) / signalPeriod;
      signalLine[validIndices[signalPeriod - 1]] = emaPrev;
      for (int j = signalPeriod; j < validIndices.length; j++) {
        final idx = validIndices[j];
        emaPrev = macdLine[idx]! * k + emaPrev * (1 - k);
        signalLine[idx] = emaPrev;
      }
    }

    final List<double?> histogram = List.filled(candles.length, null);
    for (int i = 0; i < candles.length; i++) {
      if (macdLine[i] != null && signalLine[i] != null) {
        histogram[i] = macdLine[i]! - signalLine[i]!;
      }
    }

    final latestHist = histogram.lastWhere((v) => v != null, orElse: () => null);
    String interpretation;
    if (latestHist == null) {
      interpretation = 'بيانات غير كافية';
    } else if (latestHist > 0) {
      interpretation = 'زخم صعودي (MACD فوق خط الإشارة)';
    } else {
      interpretation = 'زخم هبوطي (MACD تحت خط الإشارة)';
    }

    return {
      'macd': IndicatorResult(name: 'MACD', latestValue: macdLine.isNotEmpty ? macdLine.last : null, series: macdLine, interpretation: interpretation),
      'signal': IndicatorResult(name: 'Signal', latestValue: signalLine.isNotEmpty ? signalLine.last : null, series: signalLine, interpretation: interpretation),
      'histogram': IndicatorResult(name: 'Histogram', latestValue: latestHist, series: histogram, interpretation: interpretation),
    };
  }

  /// Average True Range - يقيس تقلب السعر، يُستخدم لاقتراح مسافة وقف
  /// خسارة منطقية بدل أن يخمّنها المستخدم يدوياً.
  static List<double?> atr(List<Candle> candles, {int period = 14}) {
    final n = candles.length;
    final List<double?> trueRanges = List.filled(n, null);
    for (int i = 0; i < n; i++) {
      if (i == 0) {
        trueRanges[i] = candles[i].high - candles[i].low;
      } else {
        final prevClose = candles[i - 1].close;
        final hl = candles[i].high - candles[i].low;
        final hc = (candles[i].high - prevClose).abs();
        final lc = (candles[i].low - prevClose).abs();
        trueRanges[i] = math.max(hl, math.max(hc, lc));
      }
    }

    final List<double?> out = List.filled(n, null);
    if (n < period) return out;

    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += trueRanges[i]!;
    }
    double atrPrev = sum / period;
    out[period - 1] = atrPrev;
    for (int i = period; i < n; i++) {
      atrPrev = (atrPrev * (period - 1) + trueRanges[i]!) / period;
      out[i] = atrPrev;
    }
    return out;
  }

  /// On-Balance Volume - يراكم الحجم مع اتجاه السعر لقياس ما إذا كان
  /// حجم التداول "يؤكد" الاتجاه الحالي أو "يتباعد" عنه (إشارة تحذير مبكرة
  /// شائعة قبل انعكاسات الأسعار). يرجع null إذا لم تتوفر بيانات حجم إطلاقاً
  /// (مثل الشموع المُدخلة يدوياً في شاشة التحليل).
  static IndicatorResult? obv(List<Candle> candles) {
    final hasVolume = candles.any((c) => c.volume != null && c.volume! > 0);
    if (!hasVolume) return null;

    final n = candles.length;
    final List<double?> out = List.filled(n, null);
    double running = 0;
    out[0] = running;
    for (int i = 1; i < n; i++) {
      final vol = candles[i].volume ?? 0;
      if (candles[i].close > candles[i - 1].close) {
        running += vol;
      } else if (candles[i].close < candles[i - 1].close) {
        running -= vol;
      }
      out[i] = running;
    }

    String interpretation = 'بيانات غير كافية لتحديد اتجاه الحجم';
    if (n >= 11) {
      final latest = out[n - 1]!;
      final past = out[n - 11]!;
      final priceNow = candles[n - 1].close;
      final pricePast = candles[n - 11].close;
      final obvRising = latest > past;
      final priceRising = priceNow > pricePast;

      if (obvRising == priceRising) {
        interpretation = obvRising
            ? 'حجم التداول يؤكد الاتجاه الصعودي (تراكم شرائي)'
            : 'حجم التداول يؤكد الاتجاه الهبوطي (تصريف بيعي)';
      } else {
        interpretation = priceRising
            ? 'تباعد سلبي: السعر يرتفع لكن حجم التداول يتراجع - قد يكون الصعود ضعيفاً'
            : 'تباعد إيجابي: السعر ينخفض لكن حجم التداول يتراجع - قد يكون الهبوط ضعيفاً';
      }
    }

    return IndicatorResult(name: 'OBV', latestValue: out[n - 1], series: out, interpretation: interpretation);
  }

  /// Average Directional Index (Wilder) - يقيس قوة الاتجاه (وليس اتجاهه).
  /// يُستخدم لتصنيف نظام السوق الحالي: اتجاهي (Trending) حيث تفيد استراتيجيات
  /// تتبع الاتجاه (تقاطع EMA)، أو عرضي (Ranging) حيث تكثر الإشارات الزائفة
  /// لتقاطع EMA ويُفضّل الاعتماد على الارتداد من التشبع (RSI) بدلاً منه.
  static Map<String, IndicatorResult> adx(List<Candle> candles, {int period = 14}) {
    final n = candles.length;
    final List<double?> plusDIout = List.filled(n, null);
    final List<double?> minusDIout = List.filled(n, null);
    final List<double?> adxOut = List.filled(n, null);

    if (n < period * 2 + 1) {
      const msg = 'بيانات غير كافية لحساب قوة الاتجاه';
      return {
        'plusDI': IndicatorResult(name: '+DI', latestValue: null, series: plusDIout, interpretation: msg),
        'minusDI': IndicatorResult(name: '-DI', latestValue: null, series: minusDIout, interpretation: msg),
        'adx': IndicatorResult(name: 'ADX', latestValue: null, series: adxOut, interpretation: msg),
      };
    }

    final List<double> tr = List.filled(n, 0);
    final List<double> plusDM = List.filled(n, 0);
    final List<double> minusDM = List.filled(n, 0);

    for (int i = 1; i < n; i++) {
      final upMove = candles[i].high - candles[i - 1].high;
      final downMove = candles[i - 1].low - candles[i].low;
      plusDM[i] = (upMove > downMove && upMove > 0) ? upMove : 0;
      minusDM[i] = (downMove > upMove && downMove > 0) ? downMove : 0;

      final hl = candles[i].high - candles[i].low;
      final hc = (candles[i].high - candles[i - 1].close).abs();
      final lc = (candles[i].low - candles[i - 1].close).abs();
      tr[i] = math.max(hl, math.max(hc, lc));
    }

    double smoothedTR = 0, smoothedPlusDM = 0, smoothedMinusDM = 0;
    for (int i = 1; i <= period; i++) {
      smoothedTR += tr[i];
      smoothedPlusDM += plusDM[i];
      smoothedMinusDM += minusDM[i];
    }

    final List<double?> dx = List.filled(n, null);

    double? computeDI(double sDM, double sTR) => sTR == 0 ? null : 100 * sDM / sTR;

    double? pDI = computeDI(smoothedPlusDM, smoothedTR);
    double? mDI = computeDI(smoothedMinusDM, smoothedTR);
    plusDIout[period] = pDI;
    minusDIout[period] = mDI;
    if (pDI != null && mDI != null && (pDI + mDI) != 0) {
      dx[period] = 100 * (pDI - mDI).abs() / (pDI + mDI);
    }

    for (int i = period + 1; i < n; i++) {
      smoothedTR = smoothedTR - (smoothedTR / period) + tr[i];
      smoothedPlusDM = smoothedPlusDM - (smoothedPlusDM / period) + plusDM[i];
      smoothedMinusDM = smoothedMinusDM - (smoothedMinusDM / period) + minusDM[i];

      pDI = computeDI(smoothedPlusDM, smoothedTR);
      mDI = computeDI(smoothedMinusDM, smoothedTR);
      plusDIout[i] = pDI;
      minusDIout[i] = mDI;
      if (pDI != null && mDI != null && (pDI + mDI) != 0) {
        dx[i] = 100 * (pDI - mDI).abs() / (pDI + mDI);
      }
    }

    final validDxIndices = <int>[for (int i = 0; i < n; i++) if (dx[i] != null) i];

    if (validDxIndices.length >= period) {
      double adxSum = 0;
      for (int k = 0; k < period; k++) {
        adxSum += dx[validDxIndices[k]]!;
      }
      double adxPrev = adxSum / period;
      adxOut[validDxIndices[period - 1]] = adxPrev;
      for (int k = period; k < validDxIndices.length; k++) {
        final i = validDxIndices[k];
        adxPrev = (adxPrev * (period - 1) + dx[i]!) / period;
        adxOut[i] = adxPrev;
      }
    }

    final latestAdx = adxOut.lastWhere((v) => v != null, orElse: () => null);
    final latestPlusDI = plusDIout.lastWhere((v) => v != null, orElse: () => null);
    final latestMinusDI = minusDIout.lastWhere((v) => v != null, orElse: () => null);

    String interpretation;
    if (latestAdx == null) {
      interpretation = 'بيانات غير كافية لحساب قوة الاتجاه';
    } else if (latestAdx >= 25) {
      final dirLabel = (latestPlusDI != null && latestMinusDI != null)
          ? (latestPlusDI > latestMinusDI ? ' (صعودي)' : ' (هبوطي)')
          : '';
      interpretation = 'اتجاه قوي (Trending)$dirLabel - مناسب لاستراتيجيات تتبع الاتجاه';
    } else if (latestAdx <= 20) {
      interpretation = 'سوق عرضي (Ranging) - الاتجاه ضعيف، احذر من إشارات تقاطع EMA الزائفة';
    } else {
      interpretation = 'منطقة انتقالية - قوة الاتجاه غير حاسمة';
    }

    return {
      'plusDI': IndicatorResult(name: '+DI', latestValue: latestPlusDI, series: plusDIout, interpretation: interpretation),
      'minusDI': IndicatorResult(name: '-DI', latestValue: latestMinusDI, series: minusDIout, interpretation: interpretation),
      'adx': IndicatorResult(name: 'ADX', latestValue: latestAdx, series: adxOut, interpretation: interpretation),
    };
  }

  static Map<String, IndicatorResult> bollingerBands(
    List<Candle> candles, {
    int period = 20,
    double stdDevMultiplier = 2,
  }) {
    final closes = candles.map((c) => c.close).toList();
    final middle = sma(candles, period);
    final List<double?> upper = List.filled(closes.length, null);
    final List<double?> lower = List.filled(closes.length, null);

    for (int i = period - 1; i < closes.length; i++) {
      final window = closes.sublist(i - period + 1, i + 1);
      final mean = middle[i]!;
      final variance = window.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / period;
      final std = variance <= 0 ? 0.0 : math.sqrt(variance);
      upper[i] = mean + stdDevMultiplier * std;
      lower[i] = mean - stdDevMultiplier * std;
    }

    final lastClose = closes.isNotEmpty ? closes.last : null;
    final lastUpper = upper.isNotEmpty ? upper.last : null;
    final lastLower = lower.isNotEmpty ? lower.last : null;

    String interpretation = 'بيانات غير كافية';
    if (lastClose != null && lastUpper != null && lastLower != null) {
      if (lastClose >= lastUpper) {
        interpretation = 'السعر عند الحد العلوي أو فوقه - احتمال تشبع شرائي';
      } else if (lastClose <= lastLower) {
        interpretation = 'السعر عند الحد السفلي أو تحته - احتمال تشبع بيعي';
      } else {
        interpretation = 'السعر داخل النطاق الطبيعي';
      }
    }

    return {
      'middle': IndicatorResult(name: 'Bollinger Middle', latestValue: middle.isNotEmpty ? middle.last : null, series: middle, interpretation: interpretation),
      'upper': IndicatorResult(name: 'Bollinger Upper', latestValue: lastUpper, series: upper, interpretation: interpretation),
      'lower': IndicatorResult(name: 'Bollinger Lower', latestValue: lastLower, series: lower, interpretation: interpretation),
    };
  }
}
