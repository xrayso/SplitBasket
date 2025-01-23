import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../screens/edit_item_screen.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
// import 'edit_item_screen.dart'; // Uncomment if you have an EditItemScreen

class GroceryItemTile extends StatefulWidget {
  final GroceryItem item;
  final String basketId;
  final bool isFinalized;

  const GroceryItemTile({
    Key? key,
    required this.item,
    required this.basketId,
    this.isFinalized = false,
  }) : super(key: key);

  @override
  _GroceryItemTileState createState() => _GroceryItemTileState();
}

class _GroceryItemTileState extends State<GroceryItemTile> {
  final _dbService = DatabaseService();

  final _authService = AuthService();

  late Future<Map<bool, List<String>>> _optedInSummaryFuture;
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
    currentOptedIn = {true: [], false : []};
  }

  @override
  void didUpdateWidget(GroceryItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.userShares != oldWidget.item.userShares) {
      setState(() {
        _optedInSummaryFuture = _buildOptedInSummary();
      });
    }
  }

  Future<Map<bool, List<String>>> _buildOptedInSummary() async {
    // Gather UIDs of those who have share > 0
    final optedInEntries = widget.item.userShares.entries
        .where((entry) => (entry.value['share'] ?? 0.0) > 0.0)
        .toList();

    if (optedInEntries.isEmpty) {
      return  {true: [], false : []};
    }

    // Otherwise, fetch each name
    Map<bool, List<String>> results = {true: [], false : []};
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
    if (everyoneEqual){
      return {true: ["EveryoneEqual"], false: ["EveryoneEqual"]};
    }
    return results;
  }

  RichText _resultsToRichText(Map<bool, List<String>> results) {
    if (results[true]!.isEmpty && results[false]!.isEmpty) {
      return RichText(
          text: TextSpan(
              style: DefaultTextStyle
                  .of(context)
                  .style,
              children: <TextSpan>[
                const TextSpan(
                    text: "No one opted in",
                    style: TextStyle(color: Colors.deepOrange)
                )
              ]
          )
      );
    }
    if (results[true]!.isNotEmpty && results[false]!.isNotEmpty) {
      if (results[true]?.first == "EveryoneEqual" &&
          results[false]?.first == "EveryoneEqual") {
        return RichText(
            text: TextSpan(
                style: DefaultTextStyle
                    .of(context)
                    .style,
                children: <TextSpan>[
                  const TextSpan(
                      text: "Everyone Equally",
                      style: TextStyle(color: Colors.green)
                  )
                ]
            )
        );
      }
    }
    final manualNames = results[true] ?? [];
    final autoNames = results[false] ?? [];

    List<TextSpan> textSpans = [];

    // 1. Add the manually opted-in names in red
    for (int i = 0; i < manualNames.length; i++) {
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

    // 2. Add automatically opted-in names in black
    for (int i = 0; i < autoNames.length; i++) {
      textSpans.add(
        TextSpan(
          text: autoNames[i],
          style: const TextStyle(color: Colors.black),
        ),
      );
      if (i < autoNames.length - 1) {
        textSpans.add(const TextSpan(text: ", "));
      }
    }

    // Wrap everything in a RichText with a prefix if desired
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle
            .of(context)
            .style,
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        onTap: _editItem, // Tap the tile to edit the entire item
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.isFinalized)
              IconButton(
                icon: Icon(
                  _isOptedIn
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color: _isOptedIn ? Colors.green : null,
                ),
                tooltip: _isOptedIn ? 'Opt out' : 'Opt in',
                onPressed: _toggleOptIn,
              ),
            if (!widget.isFinalized)
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Set percentage',
                onPressed: _showShareDialog,
              ),
          ],
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
                Text('Current share: ${(currentShare * 100).toStringAsFixed(0)}%'),
                Slider(
                  value: currentShare,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(currentShare * 100).toStringAsFixed(0)}%',
                  onChanged: (val) {
                    setDialogState(() {
                      currentShare = val;
                      textCtrl.text = (currentShare * 100).toStringAsFixed(0);
                    });
                  },
                ),
                TextField(
                  controller: textCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Enter share in percentage',
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val);
                    if (parsed != null) {
                      final clampVal = parsed.clamp(0, 100);
                      setDialogState(() {
                        currentShare = clampVal / 100;
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

  /// Example navigation to an EditItemScreen (if you have one):
  void _editItem() {
    // Replace with actual edit screen if needed
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditItemScreen(
          basketId: widget.basketId,
          item: widget.item,
        ),
      ),
    );
  }
}
