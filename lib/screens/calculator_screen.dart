import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../models/trade.dart';
import '../services/risk_service.dart';
import 'history_screen.dart';
import 'analysis_screen.dart';
import 'live_market_screen.dart';
import 'backtest_screen.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _symbolCtrl = TextEditingController(text: 'BTCUSDT');
  final _balanceCtrl = TextEditingController(text: '1000');
  final _riskPercentCtrl = TextEditingController(text: '1');
  final _entryCtrl = TextEditingController();
  final _stopLossCtrl = TextEditingController();
  final _rrCtrl = TextEditingController(text: '2');

  // إعدادات متقدمة (المرحلة 2: محرك المخاطرة الاحترافي)
  MarketType _marketType = MarketType.spot;
  final _leverageCtrl = TextEditingController(text: '1');
  final _feeCtrl = TextEditingController(text: '0.05');
  final _slippageCtrl = TextEditingController(text: '0.05');
  final _lotSizeCtrl = TextEditingController();
  final _minOrderCtrl = TextEditingController();

  TradeDirection _direction = TradeDirection.long;
  RiskCalculationResult? _result;
  String? _error;

  final _fmt = NumberFormat.decimalPattern();
  final _fmtPrecise = NumberFormat('#,##0.########');

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _balanceCtrl.dispose();
    _riskPercentCtrl.dispose();
    _entryCtrl.dispose();
    _stopLossCtrl.dispose();
    _rrCtrl.dispose();
    _leverageCtrl.dispose();
    _feeCtrl.dispose();
    _slippageCtrl.dispose();
    _lotSizeCtrl.dispose();
    _minOrderCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    setState(() => _error = null);
    try {
      final balance = double.tryParse(_balanceCtrl.text);
      final risk = double.tryParse(_riskPercentCtrl.text);
      final entry = double.tryParse(_entryCtrl.text);
      final sl = double.tryParse(_stopLossCtrl.text);
      final rr = double.tryParse(_rrCtrl.text);
      final leverage = double.tryParse(_leverageCtrl.text) ?? 1;
      final fee = double.tryParse(_feeCtrl.text) ?? 0;
      final slippage = double.tryParse(_slippageCtrl.text) ?? 0;
      final lotSize = double.tryParse(_lotSizeCtrl.text) ?? 0;
      final minOrder = double.tryParse(_minOrderCtrl.text) ?? 0;

      if (balance == null || risk == null || entry == null || sl == null || rr == null) {
        throw ArgumentError('الرجاء إدخال أرقام صحيحة في جميع الحقول');
      }

      final result = RiskService.calculate(
        accountBalance: balance,
        riskPercent: risk,
        entryPrice: entry,
        stopLossPrice: sl,
        riskRewardRatio: rr,
        direction: _direction,
        marketType: _marketType,
        leverage: _marketType == MarketType.futures ? leverage : 1,
        feePercent: fee,
        slippagePercent: slippage,
        contractSpec: ContractSpec(lotSize: lotSize, minOrderSize: minOrder),
      );
      setState(() => _result = result);
    } catch (e) {
      setState(() {
        _result = null;
        _error = e is ArgumentError ? e.message.toString() : 'حدث خطأ في الحساب، تأكد من القيم المدخلة';
      });
    }
  }

  Future<void> _pasteFromClipboard(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    final parsed = _parsePastedNumber(text);
    controller.text = parsed ?? text;
  }

  /// يحاول تفسير رقم ملصوق من الحافظة بصيغ مختلفة:
  /// "101250.50"، "101,250.50" (فاصلة آلاف)، "101250,50" (فاصلة عشرية أوروبية).
  /// القاعدة: إذا وُجدت نقطة وفاصلة معاً، الرمز الأخير في النص هو الفاصل العشري.
  /// إذا وُجدت فاصلة واحدة فقط متبوعة بثلاث خانات بالضبط، نعتبرها فاصل آلاف.
  String? _parsePastedNumber(String text) {
    final match = RegExp(r'-?[0-9][0-9.,]*').firstMatch(text);
    if (match == null) return null;
    var raw = match.group(0)!;

    final hasDot = raw.contains('.');
    final hasComma = raw.contains(',');

    if (hasDot && hasComma) {
      final lastDot = raw.lastIndexOf('.');
      final lastComma = raw.lastIndexOf(',');
      if (lastComma > lastDot) {
        // الفاصلة هي الفاصل العشري (نمط أوروبي): 1.234,56 -> 1234.56
        raw = raw.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // النقطة هي الفاصل العشري (النمط الشائع): 1,234.56 -> 1234.56
        raw = raw.replaceAll(',', '');
      }
    } else if (hasComma) {
      final afterLastComma = raw.split(',').last;
      if (afterLastComma.length == 3) {
        // على الأغلب فاصل آلاف: 101,250 -> 101250
        raw = raw.replaceAll(',', '');
      } else {
        // على الأغلب فاصل عشري: 101,5 -> 101.5
        raw = raw.replaceAll(',', '.');
      }
    }

    return double.tryParse(raw) != null ? raw : null;
  }

  Future<void> _suggestStopLossFromAtr() async {
    final entry = double.tryParse(_entryCtrl.text);
    if (entry == null || entry <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل سعر الدخول أولاً قبل اقتراح وقف الخسارة')),
      );
      return;
    }
    final symbol = _symbolCtrl.text.trim();
    if (symbol.isEmpty) return;

    final candles = await AppDatabase.instance.getCandles(symbol, limit: 300);
    final suggestion = RiskService.suggestStopLossFromAtr(
      candles: candles,
      entryPrice: entry,
      direction: _direction,
    );

    if (!mounted) return;
    if (suggestion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات شموع كافية لهذا الرمز لاقتراح وقف خسارة (استخدم شاشة السوق المباشر أولاً)'),
        ),
      );
      return;
    }
    setState(() => _stopLossCtrl.text = suggestion.toStringAsFixed(8));
  }

  Future<void> _saveTrade() async {
    if (_result == null) return;
    try {
      final trade = Trade(
        symbol: _symbolCtrl.text.trim().isEmpty ? 'N/A' : _symbolCtrl.text.trim(),
        direction: _direction,
        accountBalance: double.parse(_balanceCtrl.text),
        riskPercent: double.parse(_riskPercentCtrl.text),
        entryPrice: double.parse(_entryCtrl.text),
        stopLossPrice: double.parse(_stopLossCtrl.text),
        riskRewardRatio: double.parse(_rrCtrl.text),
        positionSize: _result!.positionSize,
        riskAmount: _result!.actualRiskAmount,
        takeProfitPrice: _result!.takeProfitPrice,
        createdAt: DateTime.now(),
        marketType: _marketType == MarketType.futures ? TradeMarketType.futures : TradeMarketType.spot,
        leverage: double.tryParse(_leverageCtrl.text) ?? 1,
        feePercent: double.tryParse(_feeCtrl.text) ?? 0,
        slippagePercent: double.tryParse(_slippageCtrl.text) ?? 0,
        requiredMargin: _result!.requiredMargin,
        estimatedFee: _result!.estimatedFee,
        estimatedSlippage: _result!.estimatedSlippage,
        maxLoss: _result!.maxLoss,
        netRiskRewardRatio: _result!.netRiskRewardRatio,
      );
      await AppDatabase.instance.insertTrade(trade);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الصفقة في السجل ✅')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ الصفقة، تأكد من صحة المدخلات')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حاسبة إدارة المخاطر'),
        actions: [
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'السوق المباشر',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LiveMarketScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.candlestick_chart),
            tooltip: 'التحليل الفني',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AnalysisScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.query_stats),
            tooltip: 'الباك-تيست',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BacktestScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'سجل الصفقات',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _symbolCtrl,
              decoration: const InputDecoration(labelText: 'الرمز (Symbol)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Long (شراء)'),
                    selected: _direction == TradeDirection.long,
                    onSelected: (_) => setState(() => _direction = TradeDirection.long),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Short (بيع)'),
                    selected: _direction == TradeDirection.short,
                    onSelected: (_) => setState(() => _direction = TradeDirection.short),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _balanceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'رصيد الحساب (USDT)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _riskPercentCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'نسبة المخاطرة %', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _entryCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'سعر الدخول',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'لصق من الحافظة',
                  onPressed: () => _pasteFromClipboard(_entryCtrl),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stopLossCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'وقف الخسارة (Stop Loss)',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.auto_graph),
                      tooltip: 'اقتراح تلقائي بناءً على ATR',
                      onPressed: _suggestStopLossFromAtr,
                    ),
                    IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: 'لصق من الحافظة',
                      onPressed: () => _pasteFromClipboard(_stopLossCtrl),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rrCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'نسبة العائد للمخاطرة (R:R)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('إعدادات متقدمة (رافعة، رسوم، انزلاق، Lot Size)'),
                childrenPadding: const EdgeInsets.only(top: 8),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Spot (فوري)'),
                          selected: _marketType == MarketType.spot,
                          onSelected: (_) => setState(() {
                            _marketType = MarketType.spot;
                            _leverageCtrl.text = '1';
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Futures (عقود آجلة)'),
                          selected: _marketType == MarketType.futures,
                          onSelected: (_) => setState(() => _marketType = MarketType.futures),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_marketType == MarketType.futures) ...[
                    TextField(
                      controller: _leverageCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'الرافعة المالية (Leverage)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _feeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'الرسوم % (لكل طرف)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _slippageCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'الانزلاق % (لكل طرف)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _lotSizeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Lot Size (اختياري)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _minOrderCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'أقل حجم أمر (اختياري)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _calculate,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('احسب', style: TextStyle(fontSize: 16)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_result != null && _result!.isHighRisk) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'نسبة المخاطرة مرتفعة نسبياً (أعلى من 5% من رأس المال). راجع النسبة قبل تنفيذ الصفقة.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _resultRow('حجم المركز', _fmtPrecise.format(_result!.positionSize)),
                      _resultRow('المخاطرة الفعلية', '${_fmt.format(_result!.actualRiskAmount)} USDT'),
                      _resultRow('سعر الهدف (Take Profit)', _fmt.format(_result!.takeProfitPrice)),
                      _resultRow('الهامش المطلوب', '${_fmt.format(_result!.requiredMargin)} USDT'),
                      _resultRow('الرسوم المقدّرة', '${_fmt.format(_result!.estimatedFee)} USDT'),
                      _resultRow('الانزلاق المقدّر', '${_fmt.format(_result!.estimatedSlippage)} USDT'),
                      const Divider(),
                      _resultRow('أقصى خسارة متوقعة', '${_fmt.format(_result!.maxLoss)} USDT'),
                      _resultRow('الربح المتوقع عند الهدف', '${_fmt.format(_result!.potentialProfit)} USDT'),
                      _resultRow(
                        'R:R الفعلية بعد الرسوم',
                        _result!.netRiskRewardRatio != null ? _result!.netRiskRewardRatio!.toStringAsFixed(2) : '-',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _saveTrade,
                        icon: const Icon(Icons.save),
                        label: const Text('حفظ الصفقة في السجل'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}
