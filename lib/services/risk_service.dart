import '../models/candle.dart';
import '../models/trade.dart';
import 'indicator_service.dart';

enum MarketType { spot, futures }

/// مواصفات العقد/الرمز - القيم الافتراضية (0) تعني "غير محدد" فتُهمَل
/// خطوة التقريب/التحقق المرتبطة بها بدل رفض الحساب.
class ContractSpec {
  final double lotSize; // أصغر خطوة للكمية (Step Size). 0 = بدون تقريب
  final double minOrderSize; // أصغر كمية مسموحة. 0 = بدون حد أدنى
  final double tickSize; // أصغر خطوة للسعر. 0 = بدون تقريب سعر

  const ContractSpec({this.lotSize = 0, this.minOrderSize = 0, this.tickSize = 0});
}

class RiskCalculationResult {
  final double riskAmount; // المبلغ المستهدف للمخاطرة قبل تقريب الكمية
  final double rawPositionSize; // حجم المركز الخام (بدون تقريب على lot size)
  final double positionSize; // حجم المركز بعد التقريب - هذا الرقم المستخدم فعلياً
  final double actualRiskAmount; // المخاطرة الفعلية بعد تقريب الكمية (قد تختلف قليلاً عن riskAmount)
  final double takeProfitPrice;
  final double priceDistance;
  final double requiredMargin; // الهامش المطلوب (= القيمة الاسمية / الرافعة)
  final double estimatedFee; // إجمالي الرسوم المقدّرة (دخول + خروج)
  final double estimatedSlippage; // تكلفة الانزلاق المقدّرة (دخول + خروج)
  final double maxLoss; // أسوأ خسارة متوقعة: المخاطرة الفعلية + الرسوم + الانزلاق
  final double potentialProfit; // الربح المتوقع عند TP بعد خصم الرسوم والانزلاق
  final double? netRiskRewardRatio; // نسبة العائد للمخاطرة الفعلية بعد الرسوم (null إذا maxLoss=0)
  final bool isHighRisk;

  RiskCalculationResult({
    required this.riskAmount,
    required this.rawPositionSize,
    required this.positionSize,
    required this.actualRiskAmount,
    required this.takeProfitPrice,
    required this.priceDistance,
    required this.requiredMargin,
    required this.estimatedFee,
    required this.estimatedSlippage,
    required this.maxLoss,
    required this.potentialProfit,
    required this.netRiskRewardRatio,
    this.isHighRisk = false,
  });
}

class RiskService {
  /// سقف افتراضي أقصى لنسبة المخاطرة بالصفقة الواحدة. يمكن رفعه عبر
  /// المعامل [maxRiskPercent] عند الاستدعاء، لكن الافتراضي محافظ عمداً.
  static const double defaultMaxRiskPercent = 10.0;

  /// عتبة تحذير (وليست منعاً) - أي مخاطرة أعلى منها تُعتبر مرتفعة.
  static const double highRiskWarningPercent = 5.0;

  static RiskCalculationResult calculate({
    required double accountBalance,
    required double riskPercent,
    required double entryPrice,
    required double stopLossPrice,
    required double riskRewardRatio,
    required TradeDirection direction,
    double maxRiskPercent = defaultMaxRiskPercent,
    MarketType marketType = MarketType.spot,
    double leverage = 1,
    double feePercent = 0, // نسبة الرسوم لكل طرف من الصفقة (دخول أو خروج)
    double slippagePercent = 0, // نسبة الانزلاق المتوقعة لكل طرف
    ContractSpec contractSpec = const ContractSpec(),
  }) {
    final inputs = <double>[
      accountBalance,
      riskPercent,
      entryPrice,
      stopLossPrice,
      riskRewardRatio,
      leverage,
      feePercent,
      slippagePercent,
    ];
    if (inputs.any((v) => v.isNaN || v.isInfinite)) {
      throw ArgumentError('توجد قيمة غير رقمية أو غير محدودة (NaN/Infinity) في المدخلات');
    }
    if (entryPrice <= 0 || stopLossPrice <= 0 || accountBalance <= 0 || riskRewardRatio <= 0 || riskPercent <= 0) {
      throw ArgumentError('جميع القيم المدخلة يجب أن تكون أكبر من صفر');
    }
    if (riskPercent > maxRiskPercent) {
      throw ArgumentError(
        'نسبة المخاطرة ($riskPercent%) أعلى من الحد الأقصى المسموح ($maxRiskPercent%). '
        'المخاطرة بنسبة عالية جداً من رأس المال في صفقة واحدة قد تؤدي إلى خسائر كبيرة.',
      );
    }
    if (entryPrice == stopLossPrice) {
      throw ArgumentError('سعر الدخول ووقف الخسارة لا يمكن أن يكونا متساويين');
    }
    if (direction == TradeDirection.long && stopLossPrice >= entryPrice) {
      throw ArgumentError('في صفقات الشراء (Long) يجب أن يكون وقف الخسارة أقل من سعر الدخول');
    }
    if (direction == TradeDirection.short && stopLossPrice <= entryPrice) {
      throw ArgumentError('في صفقات البيع (Short) يجب أن يكون وقف الخسارة أعلى من سعر الدخول');
    }
    if (marketType == MarketType.spot && leverage != 1) {
      throw ArgumentError('الرافعة المالية غير متاحة في السوق الفوري (Spot) - يجب أن تكون 1');
    }
    if (leverage <= 0) {
      throw ArgumentError('الرافعة المالية يجب أن تكون أكبر من صفر');
    }
    if (feePercent < 0 || slippagePercent < 0) {
      throw ArgumentError('نسبة الرسوم والانزلاق لا يمكن أن تكون سالبة');
    }

    final double riskAmount = accountBalance * (riskPercent / 100);
    final double priceDistance = (entryPrice - stopLossPrice).abs();
    final double rawPositionSize = riskAmount / priceDistance;

    if (!rawPositionSize.isFinite || rawPositionSize <= 0) {
      throw ArgumentError('تعذر حساب حجم مركز صحيح من القيم المدخلة');
    }

    // تقريب الكمية لأسفل حسب lot size (خطوة الكمية المسموحة في المنصة)
    double positionSize = rawPositionSize;
    if (contractSpec.lotSize > 0) {
      final steps = (rawPositionSize / contractSpec.lotSize).floor();
      positionSize = steps * contractSpec.lotSize;
    }
    if (contractSpec.minOrderSize > 0 && positionSize < contractSpec.minOrderSize) {
      throw ArgumentError(
        'حجم المركز الناتج (${positionSize.toStringAsFixed(8)}) أقل من الحد الأدنى للأمر '
        '(${contractSpec.minOrderSize}). ارفع نسبة المخاطرة أو رأس المال، أو وسّع وقف الخسارة.',
      );
    }
    if (positionSize <= 0) {
      throw ArgumentError('حجم المركز بعد التقريب أصبح صفراً - راجع lot size المدخل');
    }

    // المخاطرة الفعلية بعد تقريب الكمية (قد تختلف قليلاً عن الهدف الأصلي)
    final double actualRiskAmount = positionSize * priceDistance;

    final double notionalValue = positionSize * entryPrice;
    final double requiredMargin = marketType == MarketType.futures ? notionalValue / leverage : notionalValue;

    if (requiredMargin > accountBalance) {
      throw ArgumentError(
        'الهامش المطلوب (${requiredMargin.toStringAsFixed(2)}) أكبر من رصيد الحساب. '
        'ارفع الرافعة المالية (للعقود الآجلة فقط) أو قلّل حجم المركز.',
      );
    }

    double takeProfitPrice;
    if (direction == TradeDirection.long) {
      takeProfitPrice = entryPrice + (priceDistance * riskRewardRatio);
    } else {
      takeProfitPrice = entryPrice - (priceDistance * riskRewardRatio);
      if (takeProfitPrice < 0) {
        throw ArgumentError('نسبة الهدف المحددة تؤدي إلى سعر هدف سالب');
      }
    }

    // الرسوم: نفترض رسماً بنفس النسبة عند الدخول وعند الخروج (سواء عند SL أو TP)
    final double feeEntry = notionalValue * (feePercent / 100);
    final double feeExitAtSl = positionSize * stopLossPrice * (feePercent / 100);
    final double feeExitAtTp = positionSize * takeProfitPrice * (feePercent / 100);

    // الانزلاق: تكلفة تقديرية عند الدخول والخروج، بنفس منطق الرسوم
    final double slippageEntry = notionalValue * (slippagePercent / 100);
    final double slippageExit = positionSize * stopLossPrice * (slippagePercent / 100);

    final double estimatedFee = feeEntry + feeExitAtSl; // أسوأ سيناريو (وقف الخسارة)
    final double estimatedSlippage = slippageEntry + slippageExit;

    final double maxLoss = actualRiskAmount + estimatedFee + estimatedSlippage;

    final double grossProfitAtTp = positionSize * priceDistance * riskRewardRatio;
    final double potentialProfit = grossProfitAtTp - feeEntry - feeExitAtTp - slippageEntry;

    final double? netRiskRewardRatio = maxLoss > 0 ? potentialProfit / maxLoss : null;

    return RiskCalculationResult(
      riskAmount: riskAmount,
      rawPositionSize: rawPositionSize,
      positionSize: positionSize,
      actualRiskAmount: actualRiskAmount,
      takeProfitPrice: takeProfitPrice,
      priceDistance: priceDistance,
      requiredMargin: requiredMargin,
      estimatedFee: estimatedFee,
      estimatedSlippage: estimatedSlippage,
      maxLoss: maxLoss,
      potentialProfit: potentialProfit,
      netRiskRewardRatio: netRiskRewardRatio,
      isHighRisk: riskPercent > highRiskWarningPercent,
    );
  }

  /// يقترح مسافة وقف خسارة بناءً على ATR بدل ترك المستخدم يخمّنها يدوياً.
  /// [multiplier] الشائع هو 1.5-3 حسب الاستراتيجية (سكالبينغ أقل، سوينغ أكثر).
  /// يرجع null إذا كانت الشموع المتوفرة غير كافية لحساب ATR.
  static double? suggestStopLossFromAtr({
    required List<Candle> candles,
    required double entryPrice,
    required TradeDirection direction,
    int atrPeriod = 14,
    double multiplier = 1.5,
  }) {
    if (candles.length < atrPeriod) return null;
    final atrSeries = IndicatorService.atr(candles, period: atrPeriod);
    final latestAtr = atrSeries.isNotEmpty ? atrSeries.last : null;
    if (latestAtr == null || !latestAtr.isFinite || latestAtr <= 0) return null;

    final distance = latestAtr * multiplier;
    if (direction == TradeDirection.long) {
      final sl = entryPrice - distance;
      return sl > 0 ? sl : null;
    } else {
      return entryPrice + distance;
    }
  }
}

class CapitalManager {
  final double baseCapital;
  final double tradeAllocation;
  double reservedProfits;
  bool isTradingPaused;

  CapitalManager({
    required this.baseCapital,
    required this.tradeAllocation,
    this.reservedProfits = 0.0,
    this.isTradingPaused = false,
  });

  double getNextTradeAmount() {
    if (isTradingPaused) return 0.0;
    return tradeAllocation;
  }

  void recordTradeOutcome({required bool isWin, required double profitOrLoss}) {
    if (isWin) {
      if (profitOrLoss > 0) {
        reservedProfits += profitOrLoss;
      }
    } else {
      isTradingPaused = true;
    }
  }

  void resumeTrading() {
    isTradingPaused = false;
  }
}
