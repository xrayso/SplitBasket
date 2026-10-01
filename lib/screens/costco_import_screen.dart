import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/costco_receipts.dart';

/// Lets the user sign in to costco.ca inside the app, then pick one of their
/// recent in-warehouse receipts. Pops with the chosen [CostcoReceipt].
class CostcoImportScreen extends StatefulWidget {
  const CostcoImportScreen({super.key});

  @override
  State<CostcoImportScreen> createState() => _CostcoImportScreenState();
}

enum _Stage { signIn, loading, pick, error }

class _CostcoImportScreenState extends State<CostcoImportScreen> {
  // "Orders & Purchases" — sends the user through Costco's sign-in first if
  // needed, and leaves the page holding the tokens the receipts API wants.
  static const _startUrl = 'https://www.costco.ca/OrderStatusCmd';
  static const _daysBack = 90;
  static const _maxAttempts = 5;

  late final WebViewController _web;
  _Stage _stage = _Stage.signIn;
  List<CostcoReceipt> _receipts = [];
  String _error = '';
  int _attempts = 0;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('CostcoBridge', onMessageReceived: _onBridge)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: _onPage))
      ..loadRequest(Uri.parse(_startUrl));
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  /* ---------------- WEBVIEW → RECEIPTS ---------------- */
  void _onPage(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    // Only costco.ca pages hold the tokens; skip the sign-in pages.
    if (!host.endsWith('costco.ca') || _stage == _Stage.pick) return;
    _attempts = 0;
    _fetch();
  }

  void _fetch() {
    _retry?.cancel();
    _attempts++;
    _web.runJavaScript(costcoFetchReceiptsJs(daysBack: _daysBack));
  }

  void _onBridge(JavaScriptMessage msg) {
    final data = jsonDecode(msg.message) as Map<String, dynamic>;
    switch (data['status']) {
      case 'ok':
        final receipts = (data['receipts'] as List)
            .map((r) => CostcoReceipt.fromJson(Map<String, dynamic>.from(r)))
            .where((r) => r.items.isNotEmpty)
            .toList()
          ..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
        setState(() {
          _receipts = receipts;
          _stage = _Stage.pick;
        });
        break;
      case 'signedOut':
        // Right after sign-in the page can take a moment to store its tokens.
        if (_attempts < _maxAttempts) {
          setState(() => _stage = _Stage.loading);
          _retry = Timer(const Duration(seconds: 2), _fetch);
        } else {
          setState(() => _stage = _Stage.signIn);
        }
        break;
      default:
        setState(() {
          _error = data['message']?.toString() ?? 'Something went wrong';
          _stage = _Stage.error;
        });
    }
  }

  Future<void> _signOut() async {
    await _web.clearLocalStorage();
    await WebViewCookieManager().clearCookies();
    setState(() {
      _receipts = [];
      _stage = _Stage.signIn;
    });
    _web.loadRequest(Uri.parse(_startUrl));
  }

  void _reload() {
    setState(() => _stage = _Stage.signIn);
    _web.loadRequest(Uri.parse(_startUrl));
  }

  /* ---------------- UI ---------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from Costco'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'signOut' ? _signOut() : _reload(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reload', child: Text('Reload')),
              PopupMenuItem(value: 'signOut', child: Text('Sign out of Costco')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        // Keep the WebView alive underneath so the session isn't lost.
        index: _stage == _Stage.signIn ? 0 : 1,
        children: [
          Column(
            children: [
              const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text(
                  'Sign in to your Costco account. Your password goes straight '
                  'to Costco — SplitBasket never sees it.',
                ),
              ),
              Expanded(child: WebViewWidget(controller: _web)),
            ],
          ),
          _overlay(),
        ],
      ),
    );
  }

  Widget _overlay() {
    switch (_stage) {
      case _Stage.pick:
        return _receiptList();
      case _Stage.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text("Couldn't load your Costco receipts.\n$_error",
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _reload, child: const Text('Try again')),
              ],
            ),
          ),
        );
      default:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Fetching your receipts…'),
            ],
          ),
        );
    }
  }

  Widget _receiptList() {
    if (_receipts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No in-warehouse receipts in the last $_daysBack days.\n'
            'New receipts can take up to a day to show up.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final fmt = DateFormat('EEE, MMM d · h:mm a');
    return ListView.separated(
      itemCount: _receipts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = _receipts[i];
        return ListTile(
          leading: const Icon(Icons.receipt_long),
          title: Text(r.date != null ? fmt.format(r.date!) : 'Unknown date'),
          subtitle: Text('${r.warehouse} · ${r.items.length} items'),
          trailing: Text('\$${r.total.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium),
          onTap: () => Navigator.pop(context, r),
        );
      },
    );
  }
}
