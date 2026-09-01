import '../models/candle.dart';

enum PatternSignal { bullish, bearish, neutral }

class DetectedPattern {
  final String nameAr;
  final String nameEn;
  final PatternSignal signal;
  final int candleIndex;
  final String description;

  DetectedPattern({
    required this.nameAr,
    required this.nameEn,
    required this.signal,
    required this.candleIndex,
    required this.description,
  });
}

class CandlestickPatternService {
  static List<DetectedPattern> detectAll(List<Candle> candles) {
    final List<DetectedPattern> results = [];
    if (candles.isEmpty) return results;

    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];

      _checkDoji(c, i, results);
      _checkHammer(c, i, results);
      _checkShootingStar(c, i, results);

      if (i >= 1) {
        final prev = candles[i - 1];
        _checkEngulfing(prev, c, i, results);
        _checkPiercingAndDarkCloud(prev, c, i, results);
      }

      if (i >= 2) {
        final a = candles[i - 2];
        final b = candles[i - 1];
        _checkThreeSoldiersOrCrows(a, b, c, i, results);
        _checkMorningEveningStar(a, b, c, i, results);
      }
    }
    return results;
  }

  static void _checkDoji(Candle c, int i, List<DetectedPattern> out) {
    if (c.range == 0) return;
    if (c.body <= c.range * 0.1) {
      out.add(DetectedPattern(
        nameAr: 'دوجي (Doji)',
        nameEn: 'Doji',
        signal: PatternSignal.neutral,
        candleIndex: i,
        description: 'تردد في السوق - جسم الشمعة صغير جداً مقارنة بمداها، غالباً ما يسبق انعكاساً',
      ));
    }
  }

  static void _checkHammer(Candle c, int i, List<DetectedPattern> out) {
    if (c.range == 0 || c.body == 0) return;
    final smallBody = c.body <= c.range * 0.35;
    final longLowerWick = c.lowerWick >= c.body * 2;
    final smallUpperWick = c.upperWick <= c.body * 0.5;
    if (smallBody && longLowerWick && smallUpperWick) {
      out.add(DetectedPattern(
        nameAr: 'المطرقة (Hammer)',
        nameEn: 'Hammer',
        signal: PatternSignal.bullish,
        candleIndex: i,
        description: 'ذيل سفلي طويل يشير لرفض المشترين لمستويات أدنى - إشارة انعكاس صعودي محتملة',
      ));
    }
  }

  static void _checkShootingStar(Candle c, int i, List<DetectedPattern> out) {
    if (c.range == 0 || c.body == 0) return;
    final smallBody = c.body <= c.range * 0.35;
    final longUpperWick = c.upperWick >= c.body * 2;
    final smallLowerWick = c.lowerWick <= c.body * 0.5;
    if (smallBody && longUpperWick && smallLowerWick) {
      out.add(DetectedPattern(
        nameAr: 'نجمة الرماية (Shooting Star)',
        nameEn: 'Shooting Star',
        signal: PatternSignal.bearish,
        candleIndex: i,
        description: 'ذيل علوي طويل يشير لرفض البائعين لمستويات أعلى - إشارة انعكاس هبوطي محتملة',
      ));
    }
  }

  static void _checkEngulfing(Candle prev, Candle c, int i, List<DetectedPattern> out) {
    final bullishEngulf = prev.isBearish &&
        c.isBullish &&
        c.open <= prev.close &&
        c.close >= prev.open;
    final bearishEngulf = prev.isBullish &&
        c.isBearish &&
        c.open >= prev.close &&
        c.close <= prev.open;

    if (bullishEngulf) {
      out.add(DetectedPattern(
        nameAr: 'الابتلاع الصعودي (Bullish Engulfing)',
        nameEn: 'Bullish Engulfing',
        signal: PatternSignal.bullish,
        candleIndex: i,
        description: 'شمعة صعودية تبتلع جسم الشمعة الهابطة السابقة بالكامل - قوة شرائية واضحة',
      ));
    }
    if (bearishEngulf) {
      out.add(DetectedPattern(
        nameAr: 'الابتلاع الهبوطي (Bearish Engulfing)',
        nameEn: 'Bearish Engulfing',
        signal: PatternSignal.bearish,
        candleIndex: i,
        description: 'شمعة هابطة تبتلع جسم الشمعة الصعودية السابقة بالكامل - ضغط بيعي واضح',
      ));
    }
  }

  static void _checkPiercingAndDarkCloud(Candle prev, Candle c, int i, List<DetectedPattern> out) {
    final prevMid = (prev.open + prev.close) / 2;
    final piercing = prev.isBearish &&
        c.isBullish &&
        c.open <= prev.close &&
        c.close > prevMid &&
        c.close <= prev.open;
    final darkCloud = prev.isBullish &&
        c.isBearish &&
        c.open >= prev.close &&
        c.close < prevMid &&
        c.close >= prev.open;

    if (piercing) {
      out.add(DetectedPattern(
        nameAr: 'نمط الاختراق (Piercing Line)',
        nameEn: 'Piercing Line',
        signal: PatternSignal.bullish,
        candleIndex: i,
        description: 'شمعة صعودية تغلق فوق منتصف جسم الشمعة الهابطة - انعكاس صعودي محتمل',
      ));
    }
    if (darkCloud) {
      out.add(DetectedPattern(
        nameAr: 'الغيمة السوداء (Dark Cloud Cover)',
        nameEn: 'Dark Cloud Cover',
        signal: PatternSignal.bearish,
        candleIndex: i,
        description: 'شمعة هابطة تغلق تحت منتصف جسم الشمعة الصعودية - انعكاس هبوطي محتمل',
      ));
    }
  }

  static void _checkThreeSoldiersOrCrows(Candle a, Candle b, Candle c, int i, List<DetectedPattern> out) {
    final threeSoldiers = a.isBullish &&
        b.isBullish &&
        c.isBullish &&
        b.close > a.close &&
        c.close > b.close &&
        b.open >= a.open &&
        c.open >= b.open;
    final threeCrows = a.isBearish &&
        b.isBearish &&
        c.isBearish &&
        b.close < a.close &&
        c.close < b.close &&
        b.open <= a.open &&
        c.open <= b.open;

    if (threeSoldiers) {
      out.add(DetectedPattern(
        nameAr: 'الجنود الثلاثة البيض (Three White Soldiers)',
        nameEn: 'Three White Soldiers',
        signal: PatternSignal.bullish,
        candleIndex: i,
        description: 'ثلاث شموع صعودية متتالية بإغلاقات متصاعدة - زخم شرائي قوي ومستمر',
      ));
    }
    if (threeCrows) {
      out.add(DetectedPattern(
        nameAr: 'الغربان الثلاثة السود (Three Black Crows)',
        nameEn: 'Three Black Crows',
        signal: PatternSignal.bearish,
        candleIndex: i,
        description: 'ثلاث شموع هابطة متتالية بإغلاقات متنازلة - زخم بيعي قوي ومستمر',
      ));
    }
  }

  static void _checkMorningEveningStar(Candle a, Candle b, Candle c, int i, List<DetectedPattern> out) {
    if (a.range == 0 || b.range == 0 || c.range == 0) return;
    final smallMiddleBody = b.body <= b.range * 0.35;
    final morningStar = a.isBearish &&
        smallMiddleBody &&
        c.isBullish &&
        b.close <= a.close &&
        c.close >= (a.open + a.close) / 2;
    final eveningStar = a.isBullish &&
        smallMiddleBody &&
        c.isBearish &&
        b.close >= a.close &&
        c.close <= (a.open + a.close) / 2;

    if (morningStar) {
      out.add(DetectedPattern(
        nameAr: 'نجمة الصباح (Morning Star)',
        nameEn: 'Morning Star',
        signal: PatternSignal.bullish,
        candleIndex: i,
        description: 'نمط ثلاثي انعكاسي صعودي: هبوط، ثم حيرة، ثم شمعة صعودية قوية',
      ));
    }
    if (eveningStar) {
      out.add(DetectedPattern(
        nameAr: 'نجمة المساء (Evening Star)',
        nameEn: 'Evening Star',
        signal: PatternSignal.bearish,
        candleIndex: i,
        description: 'نمط ثلاثي انعكاسي هبوطي: صعود، ثم حيرة، ثم شمعة هابطة قوية',
      ));
    }
  }
}
