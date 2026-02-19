import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const StockApp());
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YFinance Dashboard',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final YahooFinanceService _service = YahooFinanceService();
  final List<String> _watchlist = <String>['AAPL', 'MSFT'];
  final Map<String, QuoteSnapshot> _quotes = <String, QuoteSnapshot>{};
  Timer? _refreshTimer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshAll());
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_refreshAll());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final futures = _watchlist.map(_service.fetchQuote).toList();
      final quotes = await Future.wait<QuoteSnapshot>(futures);
      final next = <String, QuoteSnapshot>{for (final q in quotes) q.symbol: q};

      if (!mounted) {
        return;
      }

      setState(() {
        _quotes
          ..clear()
          ..addAll(next);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'データ取得に失敗しました: $e';
      });
    }
  }

  Future<void> _openAddDialog() async {
    final added = await showDialog<String>(
      context: context,
      builder: (context) => AddSymbolDialog(service: _service),
    );

    if (added == null || added.isEmpty) {
      return;
    }

    if (_watchlist.contains(added)) {
      return;
    }

    setState(() {
      _watchlist.add(added);
    });
    await _refreshAll();
  }

  void _removeSymbol(String symbol) {
    setState(() {
      _watchlist.remove(symbol);
      _quotes.remove(symbol);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stocks Dashboard'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => unawaited(_refreshAll()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('銘柄追加'),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text('1分ごとに自動更新', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            if (_loading && _quotes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_watchlist.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('銘柄を追加してください')),
              )
            else
              ..._watchlist.map((symbol) {
                final quote = _quotes[symbol];
                return QuoteCard(
                  symbol: symbol,
                  quote: quote,
                  onTap: quote == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CandleChartScreen(
                                symbol: quote.symbol,
                                service: _service,
                              ),
                            ),
                          );
                        },
                  onRemove: () => _removeSymbol(symbol),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class QuoteCard extends StatelessWidget {
  const QuoteCard({
    required this.symbol,
    required this.quote,
    required this.onRemove,
    required this.onTap,
    super.key,
  });

  final String symbol;
  final QuoteSnapshot? quote;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isUp = (quote?.changePercent ?? 0) >= 0;
    final color = isUp ? Colors.green : Colors.red;

    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(symbol),
        subtitle: quote == null
            ? const Text('読み込み中...')
            : Text('前日比 ${_signed(quote!.changePercent)}%'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (quote != null)
              Text(
                quote!.price.toStringAsFixed(2),
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(CupertinoIcons.minus_circle),
            ),
          ],
        ),
      ),
    );
  }
}

class AddSymbolDialog extends StatefulWidget {
  const AddSymbolDialog({required this.service, super.key});

  final YahooFinanceService service;

  @override
  State<AddSymbolDialog> createState() => _AddSymbolDialogState();
}

class _AddSymbolDialogState extends State<AddSymbolDialog> {
  final TextEditingController _controller = TextEditingController();
  final List<SymbolResult> _results = <SymbolResult>[];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await widget.service.searchSymbols(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _results
          ..clear()
          ..addAll(results);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '検索に失敗しました: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('銘柄を検索'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => unawaited(_search()),
                    decoration: const InputDecoration(
                      hintText: '例: AAPL / Tesla',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : () => unawaited(_search()),
                  child: const Text('検索'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, index) {
                        final item = _results[index];
                        return ListTile(
                          title: Text(item.symbol),
                          subtitle: Text('${item.name} (${item.exchange})'),
                          onTap: () => Navigator.of(context).pop(item.symbol),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class CandleChartScreen extends StatefulWidget {
  const CandleChartScreen({
    required this.symbol,
    required this.service,
    super.key,
  });

  final String symbol;
  final YahooFinanceService service;

  @override
  State<CandleChartScreen> createState() => _CandleChartScreenState();
}

class _CandleChartScreenState extends State<CandleChartScreen> {
  final List<Candle> _candles = <Candle>[];
  Timer? _timer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCandles());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_loadCandles());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadCandles() async {
    try {
      final candles = await widget.service.fetchCandles(widget.symbol);
      if (!mounted) {
        return;
      }
      setState(() {
        _candles
          ..clear()
          ..addAll(candles);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'チャート取得に失敗しました: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chartWidth = max(
      MediaQuery.of(context).size.width,
      _candles.length * 10,
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.symbol} 1m Candles')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1日分の1分足を表示', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: Center(child: Text(_error!)))
            else if (_candles.isEmpty)
              const Expanded(child: Center(child: Text('データなし')))
            else
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth.toDouble(),
                    height: double.infinity,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: CandlestickChart(candles: _candles),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CandlestickChart extends StatelessWidget {
  const CandlestickChart({required this.candles, super.key});

  final List<Candle> candles;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CandlestickPainter(candles),
      size: Size.infinite,
    );
  }
}

class CandlestickPainter extends CustomPainter {
  CandlestickPainter(this.candles);

  final List<Candle> candles;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.isEmpty) {
      return;
    }

    final minPrice = candles.map((e) => e.low).reduce(min);
    final maxPrice = candles.map((e) => e.high).reduce(max);
    final range = max(maxPrice - minPrice, 0.0001);

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final candleWidth = size.width / candles.length;
    final bodyWidth = max(2.0, candleWidth * 0.65);

    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = (i + 0.5) * candleWidth;

      final highY = _priceToY(c.high, minPrice, range, size.height);
      final lowY = _priceToY(c.low, minPrice, range, size.height);
      final openY = _priceToY(c.open, minPrice, range, size.height);
      final closeY = _priceToY(c.close, minPrice, range, size.height);

      final up = c.close >= c.open;
      final color = up ? Colors.green : Colors.red;

      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), wickPaint);

      final bodyTop = min(openY, closeY);
      final bodyBottom = max(openY, closeY);
      final rect = Rect.fromLTRB(
        x - bodyWidth / 2,
        bodyTop,
        x + bodyWidth / 2,
        max(bodyBottom, bodyTop + 1.2),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CandlestickPainter oldDelegate) =>
      oldDelegate.candles != candles;

  double _priceToY(double price, double minPrice, double range, double height) {
    final normalized = (price - minPrice) / range;
    return height - (normalized * height);
  }
}

class YahooFinanceService {
  static const String _base = 'https://query1.finance.yahoo.com';

  Future<List<SymbolResult>> searchSymbols(String query) async {
    final uri = Uri.parse(
      '$_base/v1/finance/search?q=${Uri.encodeQueryComponent(query)}&quotesCount=10&newsCount=0',
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final quotes = (map['quotes'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();

    return quotes
        .where((item) => (item['symbol'] as String?)?.isNotEmpty ?? false)
        .map(
          (item) => SymbolResult(
            symbol: item['symbol'] as String,
            name: (item['longname'] ?? item['shortname'] ?? '-') as String,
            exchange: (item['exchange'] ?? '-') as String,
          ),
        )
        .toList();
  }

  Future<QuoteSnapshot> fetchQuote(String symbol) async {
    final uri = Uri.parse(
      '$_base/v8/finance/chart/$symbol?interval=1m&range=1d',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final result =
        ((map['chart'] as Map<String, dynamic>)['result'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .first;

    final meta = result['meta'] as Map<String, dynamic>;
    final price = (meta['regularMarketPrice'] as num?)?.toDouble();
    final prevClose =
        (meta['chartPreviousClose'] as num?)?.toDouble() ??
        (meta['previousClose'] as num?)?.toDouble();

    if (price == null || prevClose == null || prevClose == 0) {
      throw Exception('Invalid quote payload');
    }

    final changePercent = ((price - prevClose) / prevClose) * 100;

    return QuoteSnapshot(
      symbol: symbol,
      price: price,
      previousClose: prevClose,
      changePercent: changePercent,
    );
  }

  Future<List<Candle>> fetchCandles(String symbol) async {
    final uri = Uri.parse(
      '$_base/v8/finance/chart/$symbol?interval=1m&range=1d',
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final result =
        ((map['chart'] as Map<String, dynamic>)['result'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .first;

    final timestamps = (result['timestamp'] as List<dynamic>? ?? <dynamic>[])
        .cast<num>()
        .map((e) => DateTime.fromMillisecondsSinceEpoch(e.toInt() * 1000))
        .toList();

    final indicators =
        ((result['indicators'] as Map<String, dynamic>)['quote']
                as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .first;

    final opens = (indicators['open'] as List<dynamic>? ?? <dynamic>[]);
    final highs = (indicators['high'] as List<dynamic>? ?? <dynamic>[]);
    final lows = (indicators['low'] as List<dynamic>? ?? <dynamic>[]);
    final closes = (indicators['close'] as List<dynamic>? ?? <dynamic>[]);

    final candles = <Candle>[];
    final length = [
      timestamps.length,
      opens.length,
      highs.length,
      lows.length,
      closes.length,
    ].reduce(min);

    for (var i = 0; i < length; i++) {
      final open = (opens[i] as num?)?.toDouble();
      final high = (highs[i] as num?)?.toDouble();
      final low = (lows[i] as num?)?.toDouble();
      final close = (closes[i] as num?)?.toDouble();

      if (open == null || high == null || low == null || close == null) {
        continue;
      }

      candles.add(
        Candle(
          time: timestamps[i],
          open: open,
          high: high,
          low: low,
          close: close,
        ),
      );
    }

    return candles;
  }
}

class SymbolResult {
  const SymbolResult({
    required this.symbol,
    required this.name,
    required this.exchange,
  });

  final String symbol;
  final String name;
  final String exchange;
}

class QuoteSnapshot {
  const QuoteSnapshot({
    required this.symbol,
    required this.price,
    required this.previousClose,
    required this.changePercent,
  });

  final String symbol;
  final double price;
  final double previousClose;
  final double changePercent;
}

class Candle {
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
}

String _signed(double value) {
  final sign = value >= 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(2)}';
}
