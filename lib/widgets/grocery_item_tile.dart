import 'package:flutter/material.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../screens/edit_item_screen.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'colour-utility.dart';

class GroceryItemTile extends StatefulWidget {
  final GroceryItem item;
  final String basketId;
  final bool isFinalized;

  const GroceryItemTile({
    super.key,
    required this.item,
    required this.basketId,
    this.isFinalized = false,
  });

  @override
  _GroceryItemTileState createState() => _GroceryItemTileState();
}

class _GroceryItemTileState extends State<GroceryItemTile> {
  final _dbService = DatabaseService();
  final _authService = AuthService();

  late Future<Map<bool, List<String>>> _optedInSummaryFuture;
  late Future<String> _paidByNameFuture;

  late Map<bool, List<String>> currentOptedIn;

  double get _currentUserShare {
    final uid = _authService.currentUser?.uid ?? '';
    final userData = widget.item.userShares[uid];
    if (userData == null) {
      // The user does not exist in the dictionary at all -> truly "not in"
      return -1.0;
    }
    // If userData exists, pull out the share or default to -1
    return (userData['share'] ?? -1.0).toDouble();
  }

  bool get _isOptedIn => _currentUserShare > 0.0;

  @override
  void initState() {
    super.initState();
    _optedInSummaryFuture = _buildOptedInSummary();
    currentOptedIn = {true: [], false: []};
    _paidByNameFuture = _dbService.getUserNameById(widget.item.paidBy);
  }

  @override
  void didUpdateWidget(GroceryItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.userShares != oldWidget.item.userShares) {
      setState(() {
        _optedInSummaryFuture = _buildOptedInSummary();
      });
    }
    if (widget.item.paidBy != oldWidget.item.paidBy) {
      setState(() {
        _paidByNameFuture = _dbService.getUserNameById(widget.item.paidBy);
      });
    }
  }

  Future<Map<bool, List<String>>> _buildOptedInSummary() async {
    // Gather UIDs of those who have share > 0
    final optedInEntries = widget.item.userShares.entries
        .where((entry) => (entry.value['share'] ?? 0.0) > 0.0)
        .toList();

    if (optedInEntries.isEmpty) {
      return {true: [], false: []};
    }

    // Otherwise, fetch each name
    Map<bool, List<String>> results = {true: [], false: []};
    Basket basket = await _dbService.getBasketById(widget.basketId);
    bool everyoneEqual = optedInEntries.length == basket.memberIds.length;

    for (var entry in optedInEntries) {
      String uid = entry.key;
      double share = (entry.value['share'] ?? 0.0).toDouble();
      bool isManual = entry.value['isManual'] ?? false;
      if (share != 1.0 / basket.memberIds.length) everyoneEqual = false;
      // Get username
      String userName = await _dbService.getUserNameById(uid);
      final percent = (share * 100).toStringAsFixed(0);
      results[isManual]?.add('$userName($percent%)');
    }
    if (everyoneEqual) {
      return {true: ["EveryoneEqual"], false: ["EveryoneEqual"]};
    }
    return results;
  }

  /// Here we fix the black text by choosing white in dark mode or black in light mode.
  RichText _resultsToRichText(Map<bool, List<String>> results) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (results[true]!.isEmpty && results[false]!.isEmpty) {
      return RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: const <TextSpan>[
            TextSpan(
              text: "No one opted in",
              style: TextStyle(color: Colors.deepOrange),
            )
          ],
        ),
      );
    }
    if (results[true]!.isNotEmpty && results[false]!.isNotEmpty) {
      if (results[true]?.first == "EveryoneEqual" &&
          results[false]?.first == "EveryoneEqual") {
        return RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: const <TextSpan>[
              TextSpan(
                text: "Everyone Equally",
                style: TextStyle(color: Colors.green),
              ),
            ],
          ),
        );
      }
    }

    final manualNames = results[true] ?? [];
    final autoNames = results[false] ?? [];

    List<TextSpan> textSpans = [];

    // 1. Add the manually opted-in names in blue
    for (int i = 0; i < manualNames.length; i++) {
      textSpans.add(
        const TextSpan(
          text: "", // Placeholder - we'll insert manualNames[i] next
        ),
      );
      textSpans.add(
        TextSpan(
          text: manualNames[i],
          style: const TextStyle(color: Colors.blue),
        ),
      );
      if (i < manualNames.length - 1) {
        textSpans.add(const TextSpan(text: ", "));
      }
    }

    // If both manual and auto exist, add a comma/space separator
    if (manualNames.isNotEmpty && autoNames.isNotEmpty) {
      textSpans.add(const TextSpan(text: ", "));
    }

    // 2. Add automatically opted-in names. Previously color was Colors.black;
    //    we switch to white if dark mode is active, else black.
    for (int i = 0; i < autoNames.length; i++) {
      textSpans.add(
        TextSpan(
          text: autoNames[i],
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
      );
      if (i < autoNames.length - 1) {
        textSpans.add(const TextSpan(text: ", "));
      }
    }

    // Wrap everything in a RichText with a prefix if desired
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: <TextSpan>[
          const TextSpan(
            text: "Opted in: ",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...textSpans,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        dense: true,                         // ⬅ shrinks tile’s baseline height
        visualDensity: const VisualDensity(
          horizontal: 0,
          vertical: -4,                      // ⬅ pulls title/subtitle closer together
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: _editItem,
        title: Text(
          '${widget.item.name} \$${(widget.item.price * widget.item.quantity).toStringAsFixed(2)}',
          style: TextStyle(
            decoration:
            _isOptedIn ? TextDecoration.underline : TextDecoration.none,
          ),
        ),
        subtitle: FutureBuilder<Map<bool, List<String>>>(
          future: _optedInSummaryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _resultsToRichText(currentOptedIn);
            } else if (snapshot.hasError) {
              return const Text('Opted in: Error');
            } else {
              currentOptedIn = snapshot.data!;
              return _resultsToRichText(currentOptedIn);
            }
          },
        ),

        // ---------- HERE IS THE IMPORTANT PART ----------
        trailing: FittedBox(                    // ⬅ keeps row inside trailing slot
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<String>(
                future: _paidByNameFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  final fullName = snapshot.data ?? '   ';
                  final initials = fullName                       // e.g. “Anna Lee” → “AL”
                      .trim()
                      .split(RegExp(r'\s+'))
                      .where((p) => p.isNotEmpty)
                      .take(2)
                      .map((p) => p[0])
                      .join()
                      .toUpperCase();
                  final theme = Theme.of(context).brightness;
                  final baseColour   = colorForName(fullName);
                  final labelColour  = onColor(baseColour, theme);
                  final chipBg       = baseColour.withOpacity(0.16);      // pastel
                  final avatarBg     = baseColour.withOpacity(0.80);
                  return Tooltip(
                    message: fullName,
                    child: Chip(
                      // Avatar shows the paid icon on a solid colour
                      avatar: CircleAvatar(
                        backgroundColor: avatarBg,
                        radius: 10,
                        child: const Icon(Icons.paid, size: 12, color: Colors.white70),
                      ),

                      label: Text(
                        initials,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: labelColour,            // never black or white
                        ),
                      ),
                      backgroundColor: chipBg,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                    ),
                  );
                },
              ),
              if (!widget.isFinalized) ...[
                IconButton(
                  icon: Icon(_isOptedIn
                      ? Icons.check_box
                      : Icons.check_box_outline_blank),
                  color: _isOptedIn ? Colors.green : null,
                  visualDensity: VisualDensity.compact,
                  tooltip: _isOptedIn ? 'Opt out' : 'Opt in',
                  onPressed: _toggleOptIn,
                ),
                IconButton(
                  icon: const Icon(Icons.tune),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Set percentage',
                  onPressed: _showShareDialog,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleOptIn() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;

    if (_isOptedIn) {
      // If user is in, opting out => share=0
      await _dbService.setUserShare(
        widget.basketId,
        widget.item,
        currentUserId: uid,
        newShare: 0.0,
        isManual: true,
      );
    } else {
      // If user is out, set them as auto with leftover (-1 triggers leftover logic)
      await _dbService.setUserShare(
        widget.basketId,
        widget.item,
        currentUserId: uid,
        newShare: 0.0,
        isManual: false,
      );
    }
    setState(() {
      _optedInSummaryFuture = _buildOptedInSummary();
    });
  }

  Future<void> _showShareDialog() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;

    double currentShare = _currentUserShare;
    if (currentShare < 0) {
      currentShare = 0;
    }
    double shareBeforeSlider = currentShare;
    final textCtrl = TextEditingController(
      text: (currentShare * 100).toStringAsFixed(0),
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Specify share for ${widget.item.name}'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Current share: ${(currentShare * 100).toStringAsFixed(0)}%',
                ),
                Slider(
                  value: currentShare,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(currentShare * 100).toStringAsFixed(2)}%',
                  onChanged: (val) {
                    setDialogState(() {
                      currentShare = val;
                      textCtrl.text = (currentShare * 100).toStringAsFixed(2);
                    });
                  },
                ),
                TextField(
                  controller: textCtrl,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Enter share in percentage',
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val);
                    if (parsed != null) {
                      final clampVal = parsed.clamp(0, 100);
                      setDialogState(() {
                        currentShare = clampVal / 100.0;
                      });
                    }
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: const Text('OK'),
            onPressed: () async {
              Navigator.pop(ctx);
              // Mark them as manual
              if (currentShare != shareBeforeSlider) {
                await _dbService.setUserShare(
                  widget.basketId,
                  widget.item,
                  currentUserId: uid,
                  newShare: currentShare,
                  isManual: true,
                );
                setState(() {
                  _optedInSummaryFuture = _buildOptedInSummary();
                });
              }
            },
          ),
        ],
      ),
    );
  }

  void _editItem() async {
    Basket basket = await _dbService.getBasketById(widget.basketId);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditItemScreen(
          basket: basket,
          item: widget.item,
        ),
      ),
    );
  }
}
