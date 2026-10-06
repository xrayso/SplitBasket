import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../connectors/connections.dart';
import '../connectors/receipt_connector.dart';
import '../models/basket.dart';
import '../services/receipt_import.dart';
import '../widgets/ui.dart';
import 'basket_screen.dart';

/// One connected store: signing in on the store's own site, then its recent
/// receipts. Tapping a receipt adds it to [basket], or asks which basket when
/// there isn't one.
class ConnectorScreen extends StatefulWidget {
  final ReceiptConnector connector;
  final Basket? basket;

  const ConnectorScreen({super.key, required this.connector, this.basket});

  @override
  State<ConnectorScreen> createState() => _ConnectorScreenState();
}

enum _Stage { signIn, loading, pick, error }

class _ConnectorScreenState extends State<ConnectorScreen> {
  static const _maxAttempts = 5;

  late final WebViewController _web;
  _Stage _stage = _Stage.signIn;
  List<ConnectedReceipt> _receipts = [];
  Set<String> _imported = {};
  String _error = '';
  int _attempts = 0;
  Timer? _retry;

  ReceiptConnector get _connector => widget.connector;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('ReceiptBridge', onMessageReceived: _onBridge)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: _onPage))
      ..loadRequest(_connector.startUrl);
    // Already connected: show a spinner, not the store's page, while the
    // receipts load.
    Connections.lastSynced(_connector).then((synced) {
      if (mounted && synced != null && _stage == _Stage.signIn) {
        setState(() => _stage = _Stage.loading);
      }
    });
    Connections.imported(_connector).then((ids) {
      if (mounted) setState(() => _imported = ids);
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  /* ---------------- WEBVIEW → RECEIPTS ---------------- */
  void _onPage(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !_connector.isStorePage(uri)) {
      // The store sent them to its sign-in page.
      if (_stage == _Stage.loading) setState(() => _stage = _Stage.signIn);
      return;
    }
    if (_stage == _Stage.pick) return;
    _attempts = 0;
    _fetch();
  }

  void _fetch() {
    _retry?.cancel();
    _attempts++;
    _web.runJavaScript(_connector.fetchReceiptsJs());
  }

  void _onBridge(JavaScriptMessage msg) {
    final data = jsonDecode(msg.message) as Map<String, dynamic>;
    switch (data['status']) {
      case 'ok':
        final receipts = (data['receipts'] as List)
            .map((r) =>
                _connector.parseReceipt(Map<String, dynamic>.from(r)))
            .where((r) => r.itemCount > 0)
            .toList()
          ..sort((a, b) =>
              (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
        Connections.markSynced(_connector);
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
          Connections.markSignedOut(_connector);
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

  void _reload() {
    setState(() => _stage = _Stage.loading);
    _web.loadRequest(_connector.startUrl);
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Disconnect ${_connector.name}?'),
        content: Text(
            "You'll need to sign in to ${_connector.name} again to import "
            'receipts.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    await Connections.disconnectAll();
    if (!mounted) return;
    setState(() {
      _receipts = [];
      _imported = {};
      _stage = _Stage.signIn;
    });
    _web.loadRequest(_connector.startUrl);
  }

  /* ---------------- IMPORT ---------------- */
  Future<void> _import(ConnectedReceipt receipt) async {
    if (_imported.contains(receipt.id)) {
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import it again?'),
          content: const Text("You've already added this receipt to a basket."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import again')),
          ],
        ),
      );
      if (again != true || !mounted) return;
    }

    final basket = widget.basket ??
        await ReceiptImport.pickBasket(context, newName: receipt.title);
    if (basket == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final added = await ReceiptImport.intoBasket(
      context,
      basket,
      title: receipt.title,
      lines: receipt.lines(),
      tax: receipt.tax,
      subtotal: receipt.subtotal,
      tidyNamesFor: receipt.store,
    );
    if (added == null || added == 0) return;

    await Connections.markImported(_connector, receipt.id);
    if (widget.basket != null) {
      // Came from the basket: go back to it.
      navigator.pop();
      showAddedSnack(messenger, added);
      return;
    }
    if (mounted) setState(() => _imported.add(receipt.id));
    showAddedSnack(messenger, added,
        basketName: basket.name,
        open: () => navigator.push(MaterialPageRoute(
            builder: (_) => BasketScreen(basketId: basket.id))));
  }

  /* ---------------- UI ---------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.basket == null
            ? _connector.name
            : 'Import from ${_connector.name}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'disconnect' ? _disconnect() : _reload(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'reload', child: Text('Refresh')),
              PopupMenuItem(
                  value: 'disconnect',
                  child: Text('Disconnect ${_connector.name}')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        // Keep the store's page alive underneath so the session isn't lost.
        index: _stage == _Stage.signIn ? 0 : 1,
        children: [
          Column(
            children: [
              _signInNote(context),
              Expanded(child: WebViewWidget(controller: _web)),
            ],
          ),
          _overlay(context),
        ],
      ),
    );
  }

  Widget _signInNote(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.lock_outline,
              size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sign in to your ${_connector.name} account. Your password goes '
              'straight to ${_connector.name}; Split Basket never sees it.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    switch (_stage) {
      case _Stage.pick:
        return _receiptList(context);
      case _Stage.error:
        return EmptyState(
          icon: Icons.cloud_off_outlined,
          title: "Couldn't load your receipts",
          message: _error,
          action: FilledButton(
              onPressed: _reload, child: const Text('Try again')),
        );
      default:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Getting your ${_connector.name} receipts…'),
            ],
          ),
        );
    }
  }

  Widget _receiptList(BuildContext context) {
    final theme = Theme.of(context);
    final header = widget.basket == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Pick a receipt to add to '),
                TextSpan(
                  text: widget.basket!.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ]),
              style: subtleText(context),
            ),
          );

    if (_receipts.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No receipts yet',
        message: 'Nothing from the last 90 days. New receipts can take up to '
            'a day to show up.',
        action: OutlinedButton(onPressed: _reload, child: const Text('Refresh')),
      );
    }
    final fmt = DateFormat('EEE, MMM d · h:mm a');
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: _receipts.length + (header == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (header != null && index == 0) return header;
          final r = _receipts[index - (header == null ? 0 : 1)];
          final imported = _imported.contains(r.id);
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.receipt_long_outlined,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              title: Text(
                r.date != null ? fmt.format(r.date!) : 'Unknown date',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text([
                if (r.place.isNotEmpty) r.place,
                ReceiptImport.itemCount(r.itemCount),
                if (imported) 'Imported',
              ].join(' · ')),
              trailing: Text(
                money(r.total),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              onTap: () => _import(r),
            ),
          );
        },
      ),
    );
  }
}
