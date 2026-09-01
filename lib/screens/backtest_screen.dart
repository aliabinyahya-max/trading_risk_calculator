import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../services/backtest_service.dart';
import '../services/strategy_engine.dart';

class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  static const _timeframes = ['1m', '5m', '15m', '1H', '4H'];

  List<String> _symbols = [];
  String? _selectedSymbol;
  String _timeframe = '1m';
  TradingStrategyPreset _strategy = TradingStrategyPreset.intraday;

  final _rrCtrl = TextEditingController(text: '2');
  final _atrMultiplierCtrl = TextEditingController(text: '1.5');
  final _maxHoldingCtrl = TextEditingController(text: '100');

  bool _loading = false;
  String? _error;
  int _candleCount = 0;
  BacktestSummary? _summary;

  final _fmt = NumberFormat.decimalPattern();
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _loadSymbols();
  }

  @override
  void dispose() {
    _rrCtrl.dispose();
    _atrMultiplierCtrl.dispose();
    _maxHoldingCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSymbols() async {
    final symbols = await AppDatabase.instance.getSymbolsWithCandles();
    if (!mounted) return;
    setState(() {
      _symbols = symbols;
      _selectedSymbol = symbols.isNotEmpty ? symbols.first : null;
    });
  }

  Future<void> _runBacktest() async {
    final symbol = _selectedSymbol;
    if (symbol == null) {
      setState(() => _error = 'لا توجد رموز محفوظة بعد. استخدم شاشة "السوق المباشر" أولاً لتجميع بيانات شموع.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _summary = null;
    });

    try {
      final rr = double.tryParse(_rrCtrl.text) ?? 2;
      final atrMultiplier = double.tryParse(_atrMultiplierCtrl.text) ?? 1.5;
      final maxHolding = int.tryParse(_maxHoldingCtrl.text) ?? 100;

      final candles = await AppDatabase.instance.getCandles(symbol, timeframe: _timeframe, limit: 2000);
      _candleCount = candles.length;

      if (candles.length < _strategy.emaSlowPeriod + 10) {
        setState(() {
          _loading = false;
          _error =
              'عدد الشموع المتوفرة (${candles.length}) غير كافٍ لهذه الاستراتيجية '
              '(تحتاج على الأقل ${_strategy.emaSlowPeriod + 10} شمعة على فريم $_timeframe). '
              'اترك شاشة "السوق المباشر" تعمل لفترة أطول أولاً، أو جرّب استراتيجية سكالبينغ (تحتاج شموعاً أقل).';
        });
        return;
      }

      final request = BacktestRequest(
        candleMaps: candles.map((c) => c.toMap()).toList(),
        emaFastPeriod: _strategy.emaFastPeriod,
        emaSlowPeriod: _strategy.emaSlowPeriod,
        riskRewardRatio: rr,
        atrMultiplier: atrMultiplier,
        maxHoldingCandles: maxHolding,
      );

      // تشغيل الباك-تيست في Isolate منفصل حتى لا تتجمد الواجهة مع بيانات كثيرة
      final summary = await compute(runBacktest, request);

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'حدث خطأ أثناء تشغيل الباك-تيست: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الباك-تيست (اختبار الاستراتيجية على بيانات سابقة)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'يعمل هذا الباك-تيست فقط على الشموع المحفوظة محلياً على جهازك (التي جُمِّعت سابقاً '
                'من شاشة "السوق المباشر"). النتائج تقديرية: تفترض عند تعارض الوقف والهدف داخل نفس '
                'الشمعة أن الوقف أُصيب أولاً (سيناريو متحفظ)، ولا تحتسب الانزلاق أو الرسوم.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            if (_symbols.isEmpty)
              const Text('لا توجد رموز محفوظة بعد. افتح شاشة "السوق المباشر" أولاً.', style: TextStyle(color: Colors.orange))
            else
              DropdownButtonFormField<String>(
                value: _selectedSymbol,
                decoration: const InputDecoration(labelText: 'الرمز', border: OutlineInputBorder()),
                items: _symbols.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _selectedSymbol = v),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _timeframes.map((tf) {
                return ChoiceChip(
                  label: Text(tf),
                  selected: _timeframe == tf,
                  onSelected: (_) => setState(() => _timeframe = tf),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: TradingStrategyPreset.values.map((s) {
                return ChoiceChip(
                  label: Text(s.label),
                  selected: _strategy == s,
                  onSelected: (_) => setState(() => _strategy = s),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rrCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'نسبة R:R', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _atrMultiplierCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'مضاعف ATR للوقف', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxHoldingCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'أقصى مدة انتظار (شموع)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (_loading || _symbols.isEmpty) ? null : _runBacktest,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_circle_outline),
              label: Text(_loading ? 'جاري التشغيل...' : 'تشغيل الباك-تيست'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_summary != null) ...[
              const SizedBox(height: 20),
              Text('البيانات المستخدمة: $_candleCount شمعة', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              _buildSummaryCard(_summary!),
              const SizedBox(height: 16),
              if (_summary!.trades.isNotEmpty) ...[
                const Text('سجل صفقات الباك-تيست (الأحدث أولاً)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._summary!.trades.reversed.take(50).map(_buildTradeRow),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BacktestSummary s) {
    final avgRColor = s.avgRMultiple > 0 ? Colors.green : (s.avgRMultiple < 0 ? Colors.red : Colors.grey);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('عدد الصفقات المحسومة', '${s.totalTrades}'),
            _row('صفقات لم تُحسَم بعد (Timeout)', '${s.timeouts}'),
            const Divider(),
            _row('رابحة / خاسرة', '${s.wins} / ${s.losses}'),
            _row('نسبة الفوز', '${s.winRatePercent.toStringAsFixed(1)}%'),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('متوسط العائد لكل صفقة (Expectancy)', style: TextStyle(color: Colors.grey)),
                  Text('${s.avgRMultiple.toStringAsFixed(2)} R', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: avgRColor)),
                ],
              ),
            ),
            _row('إجمالي العائد التراكمي', '${s.totalRMultiple.toStringAsFixed(2)} R'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTradeRow(BacktestTradeOutcome t) {
    final isBuy = t.direction == SignalDirection.buy;
    final Color color;
    final String label;
    switch (t.outcome) {
      case BacktestOutcome.win:
        color = Colors.green;
        label = 'ربح';
      case BacktestOutcome.loss:
        color = Colors.red;
        label = 'خسارة';
      case BacktestOutcome.timeout:
        color = Colors.grey;
        label = 'لم تُحسَم';
    }
    return Card(
      color: color.withAlpha(15),
      child: ListTile(
        leading: Icon(isBuy ? Icons.trending_up : Icons.trending_down, color: isBuy ? Colors.green : Colors.red),
        title: Text('${isBuy ? "Long" : "Short"} @ ${_fmt.format(t.entryPrice)}'),
        subtitle: Text(
          'وقف: ${_fmt.format(t.stopLossPrice)} | هدف: ${_fmt.format(t.takeProfitPrice)}\n${_dateFmt.format(t.entryTime)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            Text('${t.rMultiple.toStringAsFixed(2)} R', style: TextStyle(color: color)),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
