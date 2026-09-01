import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/app_database.dart';
import '../models/trade.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Trade>> _tradesFuture;
  final _fmt = NumberFormat.decimalPattern();
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _tradesFuture = AppDatabase.instance.getAllTrades());
  }

  Future<void> _delete(int id) async {
    await AppDatabase.instance.deleteTrade(id);
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف الصفقة بنجاح'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد المسح'),
        content: const Text('هل أنت متأكد من مسح جميع الصفقات المحفوظة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح')),
        ],
      ),
    );

    if (confirmed == true) {
      final trades = await AppDatabase.instance.getAllTrades();
      for (final t in trades) {
        if (t.id != null) await AppDatabase.instance.deleteTrade(t.id!);
      }
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم مسح كامل السجل')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الصفقات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _reload,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'مسح الكل',
            onPressed: _confirmClearAll,
          ),
        ],
      ),
      body: FutureBuilder<List<Trade>>(
        future: _tradesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('خطأ أثناء تحميل السجل: ${snapshot.error}'));
          }
          final trades = snapshot.data ?? [];
          if (trades.isEmpty) {
            return const Center(child: Text('لا توجد صفقات محفوظة بعد'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              itemCount: trades.length,
              itemBuilder: (context, index) {
                final t = trades[index];
                final isLong = t.direction == TradeDirection.long;
                final isFutures = t.marketType == TradeMarketType.futures;
                return Dismissible(
                  key: ValueKey(t.id ?? index),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    if (t.id != null) _delete(t.id!);
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isLong ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30),
                        child: Icon(
                          isLong ? Icons.trending_up : Icons.trending_down,
                          color: isLong ? Colors.green : Colors.red,
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${t.symbol} • ${isLong ? "Long" : "Short"}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isFutures) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Futures ${t.leverage.toStringAsFixed(t.leverage == t.leverage.roundToDouble() ? 0 : 1)}x',
                                style: const TextStyle(fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        'دخول: ${_fmt.format(t.entryPrice)} | وقف: ${_fmt.format(t.stopLossPrice)} | هدف: ${_fmt.format(t.takeProfitPrice)}\n'
                        'حجم المركز: ${_fmt.format(t.positionSize)} | مخاطرة فعلية: ${_fmt.format(t.riskAmount)} USDT\n'
                        '${isFutures ? "هامش: ${_fmt.format(t.requiredMargin)} USDT | " : ""}'
                        'رسوم+انزلاق: ${_fmt.format(t.estimatedFee + t.estimatedSlippage)} USDT | '
                        'أقصى خسارة: ${_fmt.format(t.maxLoss)} USDT\n'
                        '${t.netRiskRewardRatio != null ? "R:R بعد الرسوم: ${t.netRiskRewardRatio!.toStringAsFixed(2)} | " : ""}'
                        '${_dateFmt.format(t.createdAt)}',
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
