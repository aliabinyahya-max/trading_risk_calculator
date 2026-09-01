import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/market_data_service.dart';
import '../services/strategy_engine.dart';

class LiveMarketScreen extends StatefulWidget {
  const LiveMarketScreen({super.key});

  @override
  State<LiveMarketScreen> createState() => _LiveMarketScreenState();
}

class _LiveMarketScreenState extends State<LiveMarketScreen> {
  final _instIdCtrl = TextEditingController(text: 'BTC-USDT');
  String _timeframe = '1m';
  TradingStrategyPreset _strategy = TradingStrategyPreset.intraday;
  MarketDataService? _service;
  double? _lastPrice;
  int _candleCount = 0;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final List<TradingSignal> _signals = [];
  MarketSnapshot? _snapshot;
  final _fmt = NumberFormat.decimalPattern();
  final _timeFmt = DateFormat('HH:mm:ss');

  final List<StreamSubscription> _subscriptions = [];

  static const _timeframes = ['1m', '5m', '15m', '1H', '4H'];

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _connect() {
    _disconnect();
    final service = MarketDataService(
      instId: _instIdCtrl.text.trim().isEmpty ? 'BTC-USDT' : _instIdCtrl.text.trim(),
      timeframe: _timeframe,
      strategy: _strategy,
    );

    _subscriptions.add(service.priceStream.listen((p) {
      if (mounted) setState(() => _lastPrice = p);
    }));

    _subscriptions.add(service.candlesStream.listen((c) {
      if (mounted) setState(() => _candleCount = c.length);
    }));

    _subscriptions.add(service.signalsStream.listen((newSignals) {
      if (mounted) {
        setState(() => _signals.insertAll(0, newSignals));
      }
    }));

    _subscriptions.add(service.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    }));

    _subscriptions.add(service.snapshotStream.listen((snap) {
      if (mounted) setState(() => _snapshot = snap);
    }));

    service.connect();
    setState(() {
      _service = service;
      _status = service.status;
    });
  }

  void _disconnect() {
    _cancelSubscriptions();
    _service?.dispose();
    if (mounted) {
      setState(() {
        _service = null;
        _status = ConnectionStatus.disconnected;
        _snapshot = null;
      });
    }
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _service?.dispose();
    _instIdCtrl.dispose();
    super.dispose();
  }

  String _statusLabel() {
    switch (_status) {
      case ConnectionStatus.disconnected:
        return 'غير متصل';
      case ConnectionStatus.stopped:
        return 'تم الإيقاف يدوياً';
      case ConnectionStatus.connecting:
        return 'جاري الاتصال...';
      case ConnectionStatus.connected:
        return 'متصل ✅';
      case ConnectionStatus.reconnecting:
        return 'انقطع الاتصال - جاري إعادة المحاولة...';
      case ConnectionStatus.error:
        return 'خطأ في الاتصال';
    }
  }

  Color _statusColor() {
    switch (_status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return Colors.orange;
      case ConnectionStatus.error:
        return Colors.red;
      case ConnectionStatus.disconnected:
      case ConnectionStatus.stopped:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.connected ||
        _status == ConnectionStatus.reconnecting;

    return Scaffold(
      appBar: AppBar(title: const Text('السوق المباشر')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 12, color: _statusColor()),
                const SizedBox(width: 8),
                Text(_statusLabel(), style: TextStyle(color: _statusColor(), fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instIdCtrl,
              enabled: !isBusy,
              decoration: const InputDecoration(
                labelText: 'الرمز (مثال: BTC-USDT)',
                border: OutlineInputBorder(),
                helperText: 'صيغة OKX Public API - بدون تسجيل دخول',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _timeframes.map((tf) {
                return ChoiceChip(
                  label: Text(tf),
                  selected: _timeframe == tf,
                  onSelected: isBusy ? null : (_) => setState(() => _timeframe = tf),
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
                  onSelected: isBusy ? null : (_) => setState(() => _strategy = s),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isBusy ? _disconnect : _connect,
              icon: Icon(isBusy ? Icons.stop : Icons.play_arrow),
              label: Text(isBusy ? 'إيقاف المتابعة' : 'بدء المتابعة الحية'),
              style: FilledButton.styleFrom(
                backgroundColor: isBusy ? Colors.red : null,
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('آخر سعر', style: TextStyle(color: Colors.grey)),
                        Text(
                          _lastPrice != null ? _fmt.format(_lastPrice) : '-',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('الشموع المجمّعة', style: TextStyle(color: Colors.grey)),
                        Text('$_candleCount', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_snapshot != null) ...[
              const SizedBox(height: 8),
              Card(
                color: _regimeColor(_snapshot!.regime).withAlpha(20),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.speed, color: _regimeColor(_snapshot!.regime), size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _snapshot!.adxValue != null
                                ? 'قوة الاتجاه (ADX): ${_snapshot!.adxValue!.toStringAsFixed(1)}'
                                : 'قوة الاتجاه (ADX): غير متوفرة بعد',
                            style: TextStyle(fontWeight: FontWeight.bold, color: _regimeColor(_snapshot!.regime)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(_snapshot!.regimeInterpretation, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      if (_snapshot!.obvInterpretation != null) ...[
                        const SizedBox(height: 6),
                        Text('OBV: ${_snapshot!.obvInterpretation}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_status == ConnectionStatus.connected && _candleCount < strategyMinCandles(_strategy))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'جاري تجميع الشموع... التحليل يبدأ تلقائياً بعد توفر ${strategyMinCandles(_strategy)} شمعة ($_candleCount/${strategyMinCandles(_strategy)})',
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
            const Divider(height: 32),
            const Text('الإشارات المكتشفة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Expanded(
              child: _signals.isEmpty
                  ? const Center(child: Text('لا توجد إشارات بعد', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _signals.length,
                      itemBuilder: (context, index) {
                        final s = _signals[index];
                        final isBuy = s.direction == SignalDirection.buy;
                        return Card(
                          color: isBuy ? Colors.green.withAlpha(25) : Colors.red.withAlpha(25),
                          child: ListTile(
                            leading: Icon(
                              isBuy ? Icons.trending_up : Icons.trending_down,
                              color: isBuy ? Colors.green : Colors.red,
                            ),
                            title: Text(isBuy ? 'فرصة شراء' : 'فرصة بيع'),
                            subtitle: Text(s.reason),
                            trailing: Text(_timeFmt.format(s.detectedAt)),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  int strategyMinCandles(TradingStrategyPreset s) => s.emaSlowPeriod + 2;

  Color _regimeColor(MarketRegime regime) {
    switch (regime) {
      case MarketRegime.trending:
        return Colors.green;
      case MarketRegime.ranging:
        return Colors.orange;
      case MarketRegime.unknown:
        return Colors.grey;
    }
  }
}
