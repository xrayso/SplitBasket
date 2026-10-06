import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../connectors/connections.dart';
import '../connectors/receipt_connector.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'connector_screen.dart';

/// The Connections tab: stores people can sign in to, so their receipts can
/// be imported without scanning.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  Map<String, DateTime?> _synced = {};

  @override
  void initState() {
    super.initState();
    _load();
    Connections.changes.addListener(_load);
  }

  @override
  void dispose() {
    Connections.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final synced = {
      for (final c in receiptConnectors) c.id: await Connections.lastSynced(c),
    };
    if (mounted) setState(() => _synced = synced);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              "Connect a store to import your receipts from it, no photos "
              "needed. You sign in on the store's own site, so your password "
              'never reaches Split Basket.',
              style: subtleText(context),
            ),
          ),
          for (final connector in receiptConnectors)
            _ConnectorCard(
              connector: connector,
              synced: _synced[connector.id],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ConnectorScreen(connector: connector)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.document_scanner_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'More stores are on the way. Shopping somewhere else? Scan '
                    'the receipt from inside a basket.',
                    style: subtleText(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectorCard extends StatelessWidget {
  final ReceiptConnector connector;
  final DateTime? synced;
  final VoidCallback onTap;

  const _ConnectorCard({
    required this.connector,
    required this.synced,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = synced != null;
    final statusColor = connected
        ? AppColors.of(context).positive
        : theme.colorScheme.onSurfaceVariant;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(connector.icon,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connector.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(connector.description, style: subtleText(context)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          connected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: statusColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            connected
                                ? 'Connected · updated ${_ago(synced!)}'
                                : 'Not connected',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              connected
                  ? Icon(Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant)
                  : FilledButton.tonal(
                      onPressed: onTap, child: const Text('Connect')),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime when) {
    final age = DateTime.now().difference(when);
    if (age.inMinutes < 1) return 'just now';
    if (age.inHours < 1) return '${age.inMinutes} min ago';
    if (age.inDays < 1) return '${age.inHours} h ago';
    if (age.inDays == 1) return 'yesterday';
    return DateFormat('MMM d').format(when);
  }
}
