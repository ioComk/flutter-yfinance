import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const StockApp());
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      title: 'Liquid Stocks',
      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: CupertinoColors.systemBlue,
        scaffoldBackgroundColor: Color(0xFF090E19),
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
  static const String _watchlistSymbolsKey = 'watchlist_symbols_v1';
  static const String _watchlistOrderKey = 'watchlist_order_v1';
  static const List<String> _defaultWatchlist = <String>['AAPL', 'MSFT'];

  final YahooFinanceService _service = YahooFinanceService();
  final List<String> _watchlist = <String>[..._defaultWatchlist];
  final Map<String, QuoteSnapshot> _quotes = <String, QuoteSnapshot>{};
  Timer? _refreshTimer;
  bool _isEditMode = false;
  bool _isPersistReady = false;
  bool _saveInProgress = false;
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdatedAt;
  DateTime? _lastPersistAt;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeDashboard());
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_refreshAll());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeDashboard() async {
    await _loadWatchlistFromStorage();
    if (!mounted) {
      return;
    }
    setState(() {
      _isPersistReady = true;
    });
    await _refreshAll();
  }

  Future<void> _loadWatchlistFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedOrder = prefs.getStringList(_watchlistOrderKey);
      final storedSymbols = prefs.getStringList(_watchlistSymbolsKey);
      final source = storedOrder ?? storedSymbols;
      if (source == null || source.isEmpty) {
        return;
      }

      final sanitized = <String>[];
      for (final symbol in source) {
        final normalized = symbol.trim().toUpperCase();
        if (normalized.isEmpty || sanitized.contains(normalized)) {
          continue;
        }
        sanitized.add(normalized);
      }

      if (sanitized.isEmpty || !mounted) {
        return;
      }

      setState(() {
        _watchlist
          ..clear()
          ..addAll(sanitized);
        _lastPersistAt = DateTime.now();
      });
    } catch (_) {
      // In test environments, plugin channels may be unavailable.
    }
  }

  Future<void> _saveWatchlistToStorage() async {
    if (!_isPersistReady) {
      return;
    }

    final symbols = List<String>.from(_watchlist);
    if (mounted) {
      setState(() {
        _saveInProgress = true;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_watchlistSymbolsKey, symbols);
      await prefs.setStringList(_watchlistOrderKey, symbols);

      if (!mounted) {
        return;
      }
      setState(() {
        _saveInProgress = false;
        _lastPersistAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saveInProgress = false;
      });
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
    });
  }

  void _reorderWatchlist(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (oldIndex == newIndex) {
      return;
    }

    setState(() {
      final symbol = _watchlist.removeAt(oldIndex);
      _watchlist.insert(newIndex, symbol);
    });

    unawaited(HapticFeedback.selectionClick());
    unawaited(_saveWatchlistToStorage());
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
        _lastUpdatedAt = DateTime.now();
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

  Future<void> _openAddSheet() async {
    final added = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => AddSymbolSheet(service: _service),
    );

    final normalized = added?.trim().toUpperCase();
    if (normalized == null ||
        normalized.isEmpty ||
        _watchlist.contains(normalized)) {
      return;
    }

    setState(() {
      _watchlist.add(normalized);
    });
    unawaited(_saveWatchlistToStorage());
    await _refreshAll();
  }

  void _removeSymbol(String symbol) {
    setState(() {
      _watchlist.remove(symbol);
      _quotes.remove(symbol);
    });
    unawaited(_saveWatchlistToStorage());
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Stack(
        children: [
          const _LiquidBackground(),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                CupertinoSliverRefreshControl(onRefresh: _refreshAll),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _TopHeader(
                      itemCount: _watchlist.length,
                      lastUpdatedAt: _lastUpdatedAt,
                      lastPersistAt: _lastPersistAt,
                      loading: _loading,
                      isEditMode: _isEditMode,
                      saveInProgress: _saveInProgress,
                      isPersistReady: _isPersistReady,
                      onRefresh: () => unawaited(_refreshAll()),
                      onToggleEdit: _toggleEditMode,
                    ),
                  ),
                ),
                if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: LiquidGlassSurface(
                        tint: CupertinoColors.systemRed.withValues(alpha: 0.2),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: CupertinoColors.systemRed,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_loading && _quotes.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CupertinoActivityIndicator(radius: 16),
                    ),
                  )
                else if (_watchlist.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        '銘柄を追加してください',
                        style: TextStyle(color: CupertinoColors.systemGrey),
                      ),
                    ),
                  )
                else
                  _isEditMode
                      ? SliverReorderableList(
                          itemCount: _watchlist.length,
                          onReorder: _reorderWatchlist,
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) {
                                final t = Curves.easeOut.transform(
                                  animation.value,
                                );
                                final scale =
                                    ui.lerpDouble(1.0, 1.02, t) ?? 1.0;
                                return Transform.scale(
                                  scale: scale,
                                  child: Opacity(
                                    opacity: ui.lerpDouble(0.9, 1.0, t) ?? 1.0,
                                    child: child,
                                  ),
                                );
                              },
                            );
                          },
                          itemBuilder: (context, index) {
                            final symbol = _watchlist[index];
                            final quote = _quotes[symbol];
                            return Padding(
                              key: ValueKey<String>(symbol),
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              child: QuoteGlassCard(
                                symbol: symbol,
                                quote: quote,
                                isEditMode: true,
                                showDragHandle: true,
                                dragHandle: ReorderableDragStartListener(
                                  index: index,
                                  child: const _ReorderHandle(),
                                ),
                                onRemove: () => _removeSymbol(symbol),
                                onTap: null,
                              ),
                            );
                          },
                        )
                      : SliverList.builder(
                          itemCount: _watchlist.length,
                          itemBuilder: (context, index) {
                            final symbol = _watchlist[index];
                            final quote = _quotes[symbol];
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              child: QuoteGlassCard(
                                symbol: symbol,
                                quote: quote,
                                isEditMode: false,
                                showDragHandle: false,
                                onRemove: () => _removeSymbol(symbol),
                                onTap: quote == null
                                    ? null
                                    : () {
                                        Navigator.of(context).push(
                                          CupertinoPageRoute<void>(
                                            builder: (_) => CandleChartScreen(
                                              symbol: quote.symbol,
                                              service: _service,
                                            ),
                                          ),
                                        );
                                      },
                              ),
                            );
                          },
                        ),
                const SliverToBoxAdapter(child: SizedBox(height: 84)),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: _openAddSheet,
                child: const LiquidGlassSurface(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.add_circled_solid, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '銘柄をダッシュボードに追加',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.itemCount,
    required this.lastUpdatedAt,
    required this.lastPersistAt,
    required this.loading,
    required this.isEditMode,
    required this.saveInProgress,
    required this.isPersistReady,
    required this.onRefresh,
    required this.onToggleEdit,
  });

  final int itemCount;
  final DateTime? lastUpdatedAt;
  final DateTime? lastPersistAt;
  final bool loading;
  final bool isEditMode;
  final bool saveInProgress;
  final bool isPersistReady;
  final VoidCallback onRefresh;
  final VoidCallback onToggleEdit;

  @override
  Widget build(BuildContext context) {
    final updatedText = lastUpdatedAt == null
        ? '未更新'
        : '${lastUpdatedAt!.hour.toString().padLeft(2, '0')}:${lastUpdatedAt!.minute.toString().padLeft(2, '0')}';
    final persistText = !isPersistReady
        ? '準備中'
        : saveInProgress
        ? '保存中'
        : lastPersistAt == null
        ? '未保存'
        : '保存済み';

    return LiquidGlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Liquid Stocks',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'iOS First Dashboard • 1分自動更新',
            style: TextStyle(
              color: CupertinoColors.systemGrey.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatPill(label: '銘柄数', value: '$itemCount'),
              const SizedBox(width: 10),
              _StatPill(label: '最終更新', value: updatedText),
              const SizedBox(width: 10),
              _StatPill(label: '並び順', value: persistText),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                color: CupertinoColors.systemBlue.withValues(alpha: 0.25),
                onPressed: loading ? null : onRefresh,
                child: loading
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.refresh, size: 18),
              ),
              const SizedBox(width: 10),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                color: isEditMode
                    ? CupertinoColors.systemBlue.withValues(alpha: 0.3)
                    : CupertinoColors.systemGrey.withValues(alpha: 0.24),
                onPressed: onToggleEdit,
                child: Text(
                  isEditMode ? '完了' : '編集',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: CupertinoColors.systemGrey.withValues(alpha: 0.9),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ReorderHandle extends StatelessWidget {
  const _ReorderHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        CupertinoIcons.line_horizontal_3,
        size: 18,
        color: CupertinoColors.systemGrey2,
      ),
    );
  }
}

class QuoteGlassCard extends StatelessWidget {
  const QuoteGlassCard({
    required this.symbol,
    required this.quote,
    required this.isEditMode,
    required this.showDragHandle,
    required this.onRemove,
    required this.onTap,
    this.dragHandle,
    super.key,
  }) : assert(!showDragHandle || dragHandle != null);

  final String symbol;
  final QuoteSnapshot? quote;
  final bool isEditMode;
  final bool showDragHandle;
  final Widget? dragHandle;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final change = quote?.changePercent;
    final isUp = (change ?? 0) >= 0;
    final trendColor = isUp
        ? CupertinoColors.systemGreen
        : CupertinoColors.systemRed;

    return GestureDetector(
      onTap: onTap,
      child: LiquidGlassSurface(
        padding: const EdgeInsets.all(14),
        tint: trendColor.withValues(alpha: isEditMode ? 0.14 : 0.08),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: CupertinoColors.black.withValues(alpha: 0.3),
              ),
              child: Icon(
                isUp
                    ? CupertinoIcons.arrow_up_right
                    : CupertinoIcons.arrow_down_right,
                color: trendColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    symbol,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    quote == null ? 'データ取得中...' : '前日比 ${_signed(change!)}%',
                    style: TextStyle(
                      color: quote == null
                          ? CupertinoColors.systemGrey
                          : trendColor,
                    ),
                  ),
                  if (isEditMode)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'ドラッグして並び替え',
                        style: TextStyle(
                          fontSize: 11,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (quote != null)
              Text(
                quote!.price.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(width: 10),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onRemove,
              child: const Icon(
                CupertinoIcons.minus_circle_fill,
                color: CupertinoColors.systemGrey,
              ),
            ),
            if (showDragHandle) ...[const SizedBox(width: 4), dragHandle!],
          ],
        ),
      ),
    );
  }
}

class AddSymbolSheet extends StatefulWidget {
  const AddSymbolSheet({required this.service, super.key});

  final YahooFinanceService service;

  @override
  State<AddSymbolSheet> createState() => _AddSymbolSheetState();
}

class _AddSymbolSheetState extends State<AddSymbolSheet> {
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
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Stack(
          children: [
            const _LiquidBackground(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '銘柄を検索',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: _controller,
                          placeholder: '例: AAPL / Tesla',
                          onSubmitted: (_) => unawaited(_search()),
                          prefix: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(CupertinoIcons.search),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      CupertinoButton.filled(
                        onPressed: _loading ? null : () => unawaited(_search()),
                        child: const Text('検索'),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: CupertinoColors.systemRed,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: LiquidGlassSurface(
                      child: _loading
                          ? const Center(
                              child: CupertinoActivityIndicator(radius: 14),
                            )
                          : ListView.separated(
                              itemCount: _results.length,
                              separatorBuilder: (context, index) => Container(
                                height: 1,
                                color: CupertinoColors.systemGrey.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                              itemBuilder: (_, index) {
                                final item = _results[index];
                                return CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  onPressed: () =>
                                      Navigator.of(context).pop(item.symbol),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.symbol,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: CupertinoColors.white,
                                              ),
                                            ),
                                            Text(
                                              '${item.name} • ${item.exchange}',
                                              style: TextStyle(
                                                color: CupertinoColors
                                                    .systemGrey
                                                    .withValues(alpha: 0.9),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        CupertinoIcons.add_circled,
                                        color: CupertinoColors.systemBlue,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
  ChartRangePreset _selectedPreset = ChartRangePreset.oneMinute;
  double _zoomX = 1.0;
  double _scaleStartZoom = 1.0;
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
      final candles = await widget.service.fetchCandles(
        widget.symbol,
        _selectedPreset,
      );
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

  Future<void> _onPresetChanged(ChartRangePreset preset) async {
    if (_selectedPreset == preset) {
      return;
    }
    setState(() {
      _selectedPreset = preset;
      _loading = true;
      _error = null;
      _zoomX = 1.0;
    });
    await _loadCandles();
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.of(context).size.width - 44;
    final baseChartWidth = max(viewportWidth, _candles.length * 11);
    final chartWidth = baseChartWidth * _zoomX;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('${widget.symbol} • ${_selectedPreset.label}'),
        previousPageTitle: '戻る',
      ),
      child: Stack(
        children: [
          const _LiquidBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 56, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedPreset.description,
                    style: TextStyle(
                      color: CupertinoColors.systemGrey.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: ChartRangePreset.values.map((preset) {
                        final selected = _selectedPreset == preset;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => unawaited(_onPresetChanged(preset)),
                            child: LiquidGlassSurface(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              tint: selected
                                  ? CupertinoColors.systemBlue.withValues(
                                      alpha: 0.2,
                                    )
                                  : null,
                              child: Text(
                                preset.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? CupertinoColors.systemBlue
                                      : CupertinoColors.white,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LiquidGlassSurface(
                      padding: const EdgeInsets.all(10),
                      child: _loading
                          ? const Center(
                              child: CupertinoActivityIndicator(radius: 14),
                            )
                          : _error != null
                          ? Center(child: Text(_error!))
                          : _candles.isEmpty
                          ? const Center(child: Text('データなし'))
                          : GestureDetector(
                              onScaleStart: (details) {
                                _scaleStartZoom = _zoomX;
                              },
                              onScaleUpdate: (details) {
                                if (details.pointerCount < 2) {
                                  return;
                                }
                                setState(() {
                                  _zoomX = (_scaleStartZoom * details.scale)
                                      .clamp(1.0, 8.0);
                                });
                              },
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: chartWidth.toDouble(),
                                  height: double.infinity,
                                  child: CandlestickChart(
                                    candles: _candles,
                                    preset: _selectedPreset,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.tint,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (tint ?? CupertinoColors.white).withValues(alpha: 0.22),
                const Color(0xFF28344A).withValues(alpha: 0.35),
              ],
            ),
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: 0.18),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LiquidBackground extends StatelessWidget {
  const _LiquidBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF080C18), Color(0xFF0D162A), Color(0xFF121A2D)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -70,
            child: _orb(const Color(0xFF4CC9F0), 280),
          ),
          Positioned(
            top: 180,
            left: -100,
            child: _orb(const Color(0xFF4895EF), 260),
          ),
          Positioned(
            bottom: -110,
            right: 40,
            child: _orb(const Color(0xFF3A0CA3), 230),
          ),
        ],
      ),
    );
  }

  Widget _orb(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.52),
              color.withValues(alpha: 0.05),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class CandlestickChart extends StatelessWidget {
  const CandlestickChart({
    required this.candles,
    required this.preset,
    super.key,
  });

  final List<Candle> candles;
  final ChartRangePreset preset;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CandlestickPainter(candles: candles, preset: preset),
      size: Size.infinite,
    );
  }
}

class CandlestickPainter extends CustomPainter {
  CandlestickPainter({required this.candles, required this.preset});

  final List<Candle> candles;
  final ChartRangePreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.isEmpty) {
      return;
    }

    const leftPad = 56.0;
    const rightPad = 12.0;
    const topPad = 8.0;
    const bottomPad = 28.0;
    final plotRect = Rect.fromLTWH(
      leftPad,
      topPad,
      max(0, size.width - leftPad - rightPad),
      max(0, size.height - topPad - bottomPad),
    );
    if (plotRect.width <= 0 || plotRect.height <= 0) {
      return;
    }

    final minPrice = candles.map((e) => e.low).reduce(min);
    final maxPrice = candles.map((e) => e.high).reduce(max);
    final range = max(maxPrice - minPrice, 0.0001);

    final gridPaint = Paint()
      ..color = CupertinoColors.systemGrey.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    for (var i = 0; i <= 5; i++) {
      final ratio = i / 5;
      final y = plotRect.top + plotRect.height * ratio;
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        gridPaint,
      );

      final price = maxPrice - range * ratio;
      _drawText(
        canvas,
        text: price.toStringAsFixed(price >= 100 ? 1 : 2),
        offset: Offset(4, y - 8),
        color: CupertinoColors.systemGrey.withValues(alpha: 0.95),
        fontSize: 10,
      );
    }

    final xGridCount = min(6, max(2, candles.length ~/ 20));
    for (var i = 0; i <= xGridCount; i++) {
      final ratio = i / xGridCount;
      final x = plotRect.left + plotRect.width * ratio;
      canvas.drawLine(
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        gridPaint,
      );

      final candleIndex = min(
        candles.length - 1,
        (ratio * (candles.length - 1)).round(),
      );
      final label = _formatXLabel(candles[candleIndex].time, preset);
      _drawText(
        canvas,
        text: label,
        offset: Offset(x - 20, plotRect.bottom + 8),
        color: CupertinoColors.systemGrey.withValues(alpha: 0.95),
        fontSize: 10,
      );
    }

    final candleWidth = plotRect.width / candles.length;
    final bodyWidth = max(2.0, candleWidth * 0.62);

    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = plotRect.left + (i + 0.5) * candleWidth;

      final highY = _priceToY(c.high, minPrice, range, plotRect);
      final lowY = _priceToY(c.low, minPrice, range, plotRect);
      final openY = _priceToY(c.open, minPrice, range, plotRect);
      final closeY = _priceToY(c.close, minPrice, range, plotRect);

      final up = c.close >= c.open;
      final color = up
          ? CupertinoColors.systemGreen
          : CupertinoColors.systemRed;

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
        max(bodyBottom, bodyTop + 1.3),
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.4)),
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles || oldDelegate.preset != preset;
  }

  double _priceToY(double price, double minPrice, double range, Rect plotRect) {
    final normalized = (price - minPrice) / range;
    return plotRect.bottom - (normalized * plotRect.height);
  }

  String _formatXLabel(DateTime time, ChartRangePreset preset) {
    switch (preset) {
      case ChartRangePreset.oneMinute:
      case ChartRangePreset.fiveMinutes:
      case ChartRangePreset.fifteenMinutes:
      case ChartRangePreset.thirtyMinutes:
      case ChartRangePreset.oneHour:
      case ChartRangePreset.twelveHours:
        return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      case ChartRangePreset.oneDay:
      case ChartRangePreset.threeDays:
      case ChartRangePreset.oneWeek:
        return '${time.year % 100}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
      case ChartRangePreset.oneMonth:
      case ChartRangePreset.oneYear:
        return '${time.year}/${time.month.toString().padLeft(2, '0')}';
    }
  }

  void _drawText(
    Canvas canvas, {
    required String text,
    required Offset offset,
    required Color color,
    required double fontSize,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
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

  Future<List<Candle>> fetchCandles(
    String symbol,
    ChartRangePreset preset,
  ) async {
    final uri = Uri.parse(
      '$_base/v8/finance/chart/$symbol?interval=${preset.apiInterval}&range=${preset.apiRange}',
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

    return _aggregateCandles(candles, preset.groupSize);
  }

  List<Candle> _aggregateCandles(List<Candle> candles, int groupSize) {
    if (groupSize <= 1 || candles.isEmpty) {
      return candles;
    }

    final aggregated = <Candle>[];
    for (var i = 0; i < candles.length; i += groupSize) {
      final end = min(i + groupSize, candles.length);
      final chunk = candles.sublist(i, end);
      aggregated.add(
        Candle(
          time: chunk.first.time,
          open: chunk.first.open,
          high: chunk.map((e) => e.high).reduce(max),
          low: chunk.map((e) => e.low).reduce(min),
          close: chunk.last.close,
        ),
      );
    }
    return aggregated;
  }
}

enum ChartRangePreset {
  oneMinute,
  fiveMinutes,
  fifteenMinutes,
  thirtyMinutes,
  oneHour,
  twelveHours,
  oneDay,
  threeDays,
  oneWeek,
  oneMonth,
  oneYear,
}

extension ChartRangePresetX on ChartRangePreset {
  String get label {
    switch (this) {
      case ChartRangePreset.oneMinute:
        return '1分足';
      case ChartRangePreset.fiveMinutes:
        return '5分足';
      case ChartRangePreset.fifteenMinutes:
        return '15分足';
      case ChartRangePreset.thirtyMinutes:
        return '30分足';
      case ChartRangePreset.oneHour:
        return '1時間';
      case ChartRangePreset.twelveHours:
        return '12時間';
      case ChartRangePreset.oneDay:
        return '1日';
      case ChartRangePreset.threeDays:
        return '3日';
      case ChartRangePreset.oneWeek:
        return '1週間';
      case ChartRangePreset.oneMonth:
        return '1ヶ月';
      case ChartRangePreset.oneYear:
        return '1年';
    }
  }

  String get description {
    switch (this) {
      case ChartRangePreset.oneMinute:
        return '1日分を1分足で表示';
      case ChartRangePreset.fiveMinutes:
        return '5日分を5分足で表示';
      case ChartRangePreset.fifteenMinutes:
        return '1ヶ月分を15分足で表示';
      case ChartRangePreset.thirtyMinutes:
        return '1ヶ月分を30分足で表示';
      case ChartRangePreset.oneHour:
        return '3ヶ月分を1時間足で表示';
      case ChartRangePreset.twelveHours:
        return '1年分を12時間足で表示';
      case ChartRangePreset.oneDay:
        return '5年分を1日足で表示';
      case ChartRangePreset.threeDays:
        return '10年分を3日足で表示';
      case ChartRangePreset.oneWeek:
        return '最大期間を週足で表示';
      case ChartRangePreset.oneMonth:
        return '最大期間を月足で表示';
      case ChartRangePreset.oneYear:
        return '最大期間を年足で表示';
    }
  }

  String get apiInterval {
    switch (this) {
      case ChartRangePreset.oneMinute:
        return '1m';
      case ChartRangePreset.fiveMinutes:
        return '5m';
      case ChartRangePreset.fifteenMinutes:
        return '15m';
      case ChartRangePreset.thirtyMinutes:
        return '30m';
      case ChartRangePreset.oneHour:
      case ChartRangePreset.twelveHours:
        return '60m';
      case ChartRangePreset.oneDay:
      case ChartRangePreset.threeDays:
        return '1d';
      case ChartRangePreset.oneWeek:
        return '1wk';
      case ChartRangePreset.oneMonth:
      case ChartRangePreset.oneYear:
        return '1mo';
    }
  }

  String get apiRange {
    switch (this) {
      case ChartRangePreset.oneMinute:
        return '1d';
      case ChartRangePreset.fiveMinutes:
        return '5d';
      case ChartRangePreset.fifteenMinutes:
      case ChartRangePreset.thirtyMinutes:
        return '1mo';
      case ChartRangePreset.oneHour:
        return '3mo';
      case ChartRangePreset.twelveHours:
        return '1y';
      case ChartRangePreset.oneDay:
        return '5y';
      case ChartRangePreset.threeDays:
        return '10y';
      case ChartRangePreset.oneWeek:
      case ChartRangePreset.oneMonth:
      case ChartRangePreset.oneYear:
        return 'max';
    }
  }

  int get groupSize {
    switch (this) {
      case ChartRangePreset.twelveHours:
        return 12;
      case ChartRangePreset.threeDays:
        return 3;
      case ChartRangePreset.oneYear:
        return 12;
      case ChartRangePreset.oneMinute:
      case ChartRangePreset.fiveMinutes:
      case ChartRangePreset.fifteenMinutes:
      case ChartRangePreset.thirtyMinutes:
      case ChartRangePreset.oneHour:
      case ChartRangePreset.oneDay:
      case ChartRangePreset.oneWeek:
      case ChartRangePreset.oneMonth:
        return 1;
    }
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
