import 'package:flutter/material.dart';

import '../widgets/colour-utility.dart';
import '../widgets/grocery_item_tile.dart' show categoryColor, categoryIcon;

/// One line from a scanned or imported receipt, editable before it's added.
class ReceiptLine {
  String description;
  int qty;
  double total;
  bool taxable;
  String? category;
  // Store's item/PLU number, if known; used to look up the real product name.
  final String code;
  // The name exactly as printed, shown when the readable name differs so a
  // wrong guess is easy to spot.
  final String receiptText;
  // Instant savings / coupons already taken off [total], as a positive amount.
  final double discount;
  bool include = true;
  Set<String> people = {};

  ReceiptLine({
    required this.description,
    required this.qty,
    required this.total,
    this.taxable = false,
    this.category,
    this.code = '',
    this.receiptText = '',
    this.discount = 0,
  });
}

class ReceiptReviewResult {
  final List<ReceiptLine> lines; // only the ones to add
  final String payerId;
  final double tax;

  ReceiptReviewResult(this.lines, this.payerId, this.tax);
}

/// Full-screen review of a receipt: untick lines to skip, fix names and
/// prices, mark what was taxed, and choose who's in on each item before
/// anything is added to the basket.
class ReceiptReviewScreen extends StatefulWidget {
  final String title;
  final List<ReceiptLine> lines;
  final List<String> memberIds;
  final Map<String, String> names;
  final String defaultPayer;
  final double tax;
  // What the receipt says the items cost before tax, if known. Used to warn
  // when lines were missed or misread.
  final double? receiptSubtotal;

  const ReceiptReviewScreen({
    super.key,
    required this.title,
    required this.lines,
    required this.memberIds,
    required this.names,
    required this.defaultPayer,
    this.tax = 0,
    this.receiptSubtotal,
  });

  @override
  State<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends State<ReceiptReviewScreen> {
  late String _payer = widget.defaultPayer;
  late final TextEditingController _taxCtrl = TextEditingController(
    text: widget.tax > 0 ? widget.tax.toStringAsFixed(2) : '',
  );

  List<ReceiptLine> get _included =>
      widget.lines.where((l) => l.include).toList();

  @override
  void initState() {
    super.initState();
    // Most shopping trips are shared by everyone; untick people per item.
    for (final line in widget.lines) {
      line.people = widget.memberIds.toSet();
    }
  }

  @override
  void dispose() {
    _taxCtrl.dispose();
    super.dispose();
  }

  String _firstName(String uid) {
    final name = widget.names[uid] ?? '…';
    return name.trim().split(RegExp(r'\s+')).first;
  }

  void _setEveryone(Set<String> people) {
    setState(() {
      for (final line in widget.lines) {
        line.people = {...people};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final included = _included;
    final itemsTotal = included.fold(0.0, (s, l) => s + l.total);
    final allLinesTotal = widget.lines.fold(0.0, (s, l) => s + l.total);
    final subtotal = widget.receiptSubtotal;
    final mismatch =
        subtotal != null && subtotal > 0 && (allLinesTotal - subtotal).abs() > 0.05;
    final unassigned = included.where((l) => l.people.isEmpty).length;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _payer,
                    decoration: const InputDecoration(labelText: 'Who paid?'),
                    items: widget.memberIds
                        .map((u) => DropdownMenuItem(
                            value: u, child: Text(widget.names[u] ?? '…')))
                        .toList(),
                    onChanged: (v) => setState(() => _payer = v!),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _taxCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Tax',
                      prefixText: '\$',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Split all with:', style: theme.textTheme.labelLarge),
                ActionChip(
                  label: const Text('Everyone'),
                  onPressed: () => _setEveryone(widget.memberIds.toSet()),
                ),
                ActionChip(
                  label: Text('${_firstName(_payer)} only'),
                  onPressed: () => _setEveryone({_payer}),
                ),
                ActionChip(
                  label: const Text('Decide later'),
                  onPressed: () => _setEveryone({}),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '${included.length} of ${widget.lines.length} items · '
              '\$${itemsTotal.toStringAsFixed(2)}'
              '${unassigned > 0 ? ' · $unassigned for later' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (mismatch)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'These lines add up to \$${allLinesTotal.toStringAsFixed(2)}, '
                  'but the receipt says \$${subtotal.toStringAsFixed(2)} before tax. '
                  'Check for a missed or misread line.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          for (var i = 0; i < widget.lines.length; i++) _lineCard(i),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: included.isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      ReceiptReviewResult(
                        included,
                        _payer,
                        double.tryParse(_taxCtrl.text.trim()) ?? 0,
                      ),
                    ),
            child: Text('Add ${included.length} items'),
          ),
        ),
      ),
    );
  }

  /// A borderless text field that looks like plain text until it's tapped.
  InputDecoration _inlineField({String? prefixText}) {
    final primary = Theme.of(context).colorScheme.primary;
    return InputDecoration(
      isDense: true,
      filled: false,
      prefixText: prefixText,
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: primary, width: 2)),
    );
  }

  Widget _categoryTile(String? category) {
    final theme = Theme.of(context);
    final colour = categoryColor(category);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colour.withValues(alpha: theme.brightness == Brightness.dark ? 0.24 : 0.13),
          theme.colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(categoryIcon(category),
          size: 18, color: onColor(colour, theme.brightness)),
    );
  }

  /// "On receipt: KS ORG EGGS · \$4.00 off", when there's anything to say.
  String? _note(ReceiptLine line) {
    final parts = [
      if (line.receiptText.isNotEmpty &&
          line.receiptText.toLowerCase() != line.description.toLowerCase())
        'On receipt: ${line.receiptText}',
      if (line.discount >= 0.005) '\$${line.discount.toStringAsFixed(2)} off',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _lineCard(int i) {
    final theme = Theme.of(context);
    final line = widget.lines[i];
    return Opacity(
      key: ValueKey(i),
      opacity: line.include ? 1 : 0.45,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: line.include,
                    onChanged: (v) => setState(() => line.include = v!),
                  ),
                  _categoryTile(line.category),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      initialValue: line.description,
                      minLines: 1,
                      maxLines: 2,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      decoration: _inlineField(),
                      onChanged: (t) => line.description = t,
                    ),
                  ),
                  if (line.qty > 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('×${line.qty}', style: theme.textTheme.bodySmall),
                    ),
                  SizedBox(
                    width: 88,
                    child: TextFormField(
                      initialValue: line.total.toStringAsFixed(2),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      decoration: _inlineField(prefixText: '\$'),
                      onChanged: (t) {
                        final p = double.tryParse(t);
                        if (p != null) setState(() => line.total = p);
                      },
                    ),
                  ),
                ],
              ),
              if (_note(line) case final note?)
                Padding(
                  padding: const EdgeInsets.only(left: 90, bottom: 4),
                  child: Text(note,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              if (line.include)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final uid in widget.memberIds)
                        FilterChip(
                          label: Text(_firstName(uid)),
                          showCheckmark: false,
                          selected: line.people.contains(uid),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onSelected: (on) => setState(() =>
                              on ? line.people.add(uid) : line.people.remove(uid)),
                        ),
                      FilterChip(
                        label: const Text('Taxed'),
                        avatar: const Icon(Icons.percent, size: 16),
                        showCheckmark: false,
                        selected: line.taxable,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onSelected: (on) => setState(() => line.taxable = on),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
