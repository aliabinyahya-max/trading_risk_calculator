import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../models/candle.dart';
import '../services/candlestick_pattern_service.dart';
import '../services/indicator_service.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final _symbolCtrl = TextEditingController(text: 'BTCUSDT');
  final _openCtrl = TextEditingController();
  final _highCtrl = TextEditingController();
  final _lowCtrl = TextEditingController();
  final _closeCtrl = TextEditingController();

  List<Candle> _candles = [];
  List<DetectedPattern> _patterns = [];
  final _fmt = NumberFormat.decimalPattern();

  @override
  void initState() {
    super.initState();
    _loadCandles();
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _openCtrl.dispose();
    _highCtrl.dispose();
    _lowCtrl.dispose();
    _closeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCandles() async {
    final candles = await AppDatabase.instance.getCandles(_symbolCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _candles = candles;
      _patterns = CandlestickPatternService.detectAll(candles);
    });
  }

  Future<void> _addCandle() async {
    final open = double.tryParse(_openCtrl.text);
    final high = double.tryParse(_highCtrl.text);
    final low = double.tryParse(_lowCtrl.text);
    final close = double.tryParse(_closeCtrl.text);

    if (open == null || high == null || low == null || close == null || open <= 0 || high <= 0 || low <= 0 || close <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء إدخال أرقام موجبة صحيحة لكل من Open/High/Low/Close')),
        );
      }
      return;
    }

    if (high < low || high < open || high < close || low > open || low > close) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خطأ في منطق الشمعة: High يجب أن يكون الأعلى و Low الأدنى دائماً')),
        );
      }
      return;
    }

    final candle = Candle(
      symbol: _symbolCtrl.text.trim().isEmpty ? 'BTCUSDT' : _symbolCtrl.text.trim(),
      time: DateTime.now().add(Duration(seconds: _candles.length)),
      open: open,
      high: high,
      low: low,
      close: close,
    );

    await AppDatabase.instance.insertCandle(candle);
    _openCtrl.clear();
    _highCtrl.clear();
    _lowCtrl.clear();
    _closeCtrl.clear();
    await _loadCandles();
  }

  Future<void> _clearAll() async {
    await AppDatabase.instance.deleteCandlesForSymbol(_symbolCtrl.text.trim());
    await _loadCandles();
  }

  @override
  Widget build(BuildContext context) {
    final rsi = _candles.length > 14 ? IndicatorService.rsi(_candles) : null;
    final macd = _candles.length > 26 ? IndicatorService.macd(_candles) : null;
    final bb = _candles.length >= 20 ? IndicatorService.bollingerBands(_candles) : null;
    final adx = _candles.length >= 29 ? IndicatorService.adx(_candles) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('التحليل الفني')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _symbolCtrl,
              decoration: const InputDecoration(labelText: 'الرمز (Symbol)', border: OutlineInputBorder()),
              onSubmitted: (_) => _loadCandles(),
              onEditingComplete: _loadCandles,
            ),
            const SizedBox(height: 12),
            const Text('إضافة شمعة يدوياً (بالترتيب الزمني - الأقدم أولاً):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _openCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Open', border: OutlineInputBorder()))),
                const SizedBox(width: 6),
                Expanded(child: TextField(controller: _highCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'High', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _lowCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Low', border: OutlineInputBorder()))),
                const SizedBox(width: 6),
                Expanded(child: TextField(controller: _closeCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Close', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _addCandle,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة شمعة'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('مسح الكل'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('عدد الشموع المُدخلة: ${_candles.length}', style: const TextStyle(color: Colors.grey)),
            const Divider(height: 32),
            const Text('أنماط الشموع اليابانية المكتشفة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (_candles.isEmpty)
              const Text('أضف شموعاً لبدء التحليل', style: TextStyle(color: Colors.grey))
            else if (_patterns.isEmpty)
              const Text('لم يتم اكتشاف أنماط معروفة في البيانات الحالية', style: TextStyle(color: Colors.grey))
            else
              ..._patterns.reversed.take(10).map((p) => Card(
                    color: p.signal == PatternSignal.bullish
                        ? Colors.green.withAlpha(25)
                        : p.signal == PatternSignal.bearish
                            ? Colors.red.withAlpha(25)
                            : null,
                    child: ListTile(
                      leading: Icon(
                        p.signal == PatternSignal.bullish
                            ? Icons.arrow_upward
                            : p.signal == PatternSignal.bearish
                                ? Icons.arrow_downward
                                : Icons.remove,
                        color: p.signal == PatternSignal.bullish
                            ? Colors.green
                            : p.signal == PatternSignal.bearish
                                ? Colors.red
                                : Colors.grey,
                      ),
                      title: Text(p.nameAr),
                      subtitle: Text(p.description),
                    ),
                  )),
            const Divider(height: 32),
            const Text('المؤشرات الفنية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (rsi == null)
              const Text('RSI: يحتاج 15 شمعة على الأقل', style: TextStyle(color: Colors.grey))
            else
              _indicatorCard('RSI', rsi.latestValue, rsi.interpretation),
            if (macd != null) ...[
              const SizedBox(height: 8),
              _indicatorCard('MACD Histogram', macd['histogram']!.latestValue, macd['histogram']!.interpretation),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('MACD: يحتاج 27 شمعة على الأقل', style: TextStyle(color: Colors.grey)),
              ),
            if (bb != null) ...[
              const SizedBox(height: 8),
              _indicatorCard('Bollinger Bands', bb['middle']!.latestValue, bb['middle']!.interpretation),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Bollinger Bands: يحتاج 20 شمعة على الأقل', style: TextStyle(color: Colors.grey)),
              ),
            if (adx != null) ...[
              const SizedBox(height: 8),
              _indicatorCard('ADX (قوة الاتجاه)', adx['adx']!.latestValue, adx['adx']!.interpretation),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('ADX: يحتاج 29 شمعة على الأقل', style: TextStyle(color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _indicatorCard(String name, double? value, String interpretation) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              flex: 1,
              child: Text(value != null ? _fmt.format(value) : '-', textAlign: TextAlign.center),
            ),
            Expanded(
              flex: 3,
              child: Text(interpretation, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}
