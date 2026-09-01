enum TradeDirection { long, short }
enum TradeMarketType { spot, futures }

class Trade {
  final int? id;
  final String symbol; // e.g. BTCUSDT
  final TradeDirection direction;
  final double accountBalance;
  final double riskPercent; // % من رأس المال يتم المخاطرة به
  final double entryPrice;
  final double stopLossPrice;
  final double riskRewardRatio; // مثلا 2 تعني هدف = 2x المخاطرة
  final double positionSize; // الناتج المحسوب (بوحدة الأصل) بعد تقريب lot size
  final double riskAmount; // المبلغ المعرض للخطر بالعملة (الفعلي بعد التقريب)
  final double takeProfitPrice; // الهدف المحسوب
  final DateTime createdAt;
  final String? notes;

  // حقول محرك المخاطرة الاحترافي (المرحلة 2) - قيم افتراضية للتوافق مع
  // الصفقات القديمة المحفوظة قبل إضافتها.
  final TradeMarketType marketType;
  final double leverage;
  final double feePercent;
  final double slippagePercent;
  final double requiredMargin;
  final double estimatedFee;
  final double estimatedSlippage;
  final double maxLoss;
  final double? netRiskRewardRatio;

  Trade({
    this.id,
    required this.symbol,
    required this.direction,
    required this.accountBalance,
    required this.riskPercent,
    required this.entryPrice,
    required this.stopLossPrice,
    required this.riskRewardRatio,
    required this.positionSize,
    required this.riskAmount,
    required this.takeProfitPrice,
    required this.createdAt,
    this.notes,
    this.marketType = TradeMarketType.spot,
    this.leverage = 1,
    this.feePercent = 0,
    this.slippagePercent = 0,
    this.requiredMargin = 0,
    this.estimatedFee = 0,
    this.estimatedSlippage = 0,
    this.maxLoss = 0,
    this.netRiskRewardRatio,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'symbol': symbol,
      'direction': direction.name,
      'accountBalance': accountBalance,
      'riskPercent': riskPercent,
      'entryPrice': entryPrice,
      'stopLossPrice': stopLossPrice,
      'riskRewardRatio': riskRewardRatio,
      'positionSize': positionSize,
      'riskAmount': riskAmount,
      'takeProfitPrice': takeProfitPrice,
      'createdAt': createdAt.toIso8601String(),
      'notes': notes,
      'marketType': marketType.name,
      'leverage': leverage,
      'feePercent': feePercent,
      'slippagePercent': slippagePercent,
      'requiredMargin': requiredMargin,
      'estimatedFee': estimatedFee,
      'estimatedSlippage': estimatedSlippage,
      'maxLoss': maxLoss,
      'netRiskRewardRatio': netRiskRewardRatio,
    };
  }

  factory Trade.fromMap(Map<String, dynamic> map) {
    return Trade(
      id: map['id'] as int?,
      symbol: map['symbol'] as String,
      direction: TradeDirection.values.firstWhere(
        (e) => e.name == map['direction'],
        orElse: () => TradeDirection.long,
      ),
      accountBalance: (map['accountBalance'] as num).toDouble(),
      riskPercent: (map['riskPercent'] as num).toDouble(),
      entryPrice: (map['entryPrice'] as num).toDouble(),
      stopLossPrice: (map['stopLossPrice'] as num).toDouble(),
      riskRewardRatio: (map['riskRewardRatio'] as num).toDouble(),
      positionSize: (map['positionSize'] as num).toDouble(),
      riskAmount: (map['riskAmount'] as num).toDouble(),
      takeProfitPrice: (map['takeProfitPrice'] as num).toDouble(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      notes: map['notes'] as String?,
      marketType: TradeMarketType.values.firstWhere(
        (e) => e.name == map['marketType'],
        orElse: () => TradeMarketType.spot,
      ),
      leverage: map['leverage'] == null ? 1 : (map['leverage'] as num).toDouble(),
      feePercent: map['feePercent'] == null ? 0 : (map['feePercent'] as num).toDouble(),
      slippagePercent: map['slippagePercent'] == null ? 0 : (map['slippagePercent'] as num).toDouble(),
      requiredMargin: map['requiredMargin'] == null ? 0 : (map['requiredMargin'] as num).toDouble(),
      estimatedFee: map['estimatedFee'] == null ? 0 : (map['estimatedFee'] as num).toDouble(),
      estimatedSlippage: map['estimatedSlippage'] == null ? 0 : (map['estimatedSlippage'] as num).toDouble(),
      maxLoss: map['maxLoss'] == null ? 0 : (map['maxLoss'] as num).toDouble(),
      netRiskRewardRatio: map['netRiskRewardRatio'] == null ? null : (map['netRiskRewardRatio'] as num).toDouble(),
    );
  }
}
