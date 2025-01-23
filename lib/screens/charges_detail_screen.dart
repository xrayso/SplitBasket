import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/charges.dart';

class ChargesDetailScreen extends StatefulWidget {
  final String otherUserId;
  final String userName;
  final String currentUserId;

  const ChargesDetailScreen({super.key, 
    required this.otherUserId,
    required this.userName,
    required this.currentUserId,
  });

  @override
  _ChargesDetailScreenState createState() => _ChargesDetailScreenState();
}
class _ChargesDetailScreenState extends State<ChargesDetailScreen> {
  final DatabaseService _dbService = DatabaseService();

  void _resolveCharge(Charge charge) async {
    await _dbService.resolveCharge(charge.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Charge resolved.')),
    );
  }

  void _requestChargeResolution(Charge charge) async {
    await _dbService.requestChargeResolution(charge.id, widget.currentUserId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Resolution request sent.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Details for ${widget.userName}'),
      ),
      body: StreamBuilder<List<Charge>>(
        stream: _dbService.getChargesBetweenUsers(
            widget.currentUserId, widget.otherUserId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}\n${widget.currentUserId} ${widget.otherUserId}',
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final charges = snapshot.data!;
          if (charges.isEmpty) {
            return Center(child: Text('No items found.'));
          }
          charges.sort((a, b) => b.date.compareTo(a.date));

          return ListView.builder(
            itemCount: charges.length,
            itemBuilder: (context, index) {
              Charge charge = charges[index];

              // Determine if the current user is the payee or payer
              bool isPayee = widget.currentUserId == charge.payeeId;
              bool isPayer = widget.currentUserId == charge.payerId;

              // Determine button visibility
              bool showResolveButton = isPayee;
              bool showRequestResolutionButton = isPayer && charge.status == 'pending';
              bool showRequestSentIndicator = isPayer && charge.status == 'requested';

              String splitWithText = charge.item.userShares.length - 1 == 1
                  ? 'Split with: ${charge.item.userShares.length - 1} other'
                  : 'Split with: ${charge.item.userShares.length - 1} others';
              if (charge.item.userShares.length == 1) {
                splitWithText = "Not split";
              }


              Color? tileColor;
              if (charge.status == 'resolved') {
                tileColor = Colors.grey[300]; // Resolved charges are grey
              } else if (isPayee) {
                tileColor = Colors.green[100]; // User is payee (owed money)
              } else if (isPayer) {
                tileColor = Colors.red[100]; // User is payer (owes money)
              }

              String totalString = charge.isTax ?
              'Price ${isPayee ? 'Owed to You' : 'You Owe'}: \$${charge.amount.toStringAsFixed(2)}\nTax Percent: ${(charge.item.price * 100).toStringAsFixed(2)}%' :
              'Price ${isPayee ? 'Owed to You' : 'You Owe'}: \$${charge.amount.toStringAsFixed(2)}\nQuantity: ${charge.item.quantity}\n$splitWithText';

              return ListTile(
                tileColor: tileColor,
                title: Text(charge.item.name),
                subtitle: Text(totalString),
                trailing: charge.status == 'resolved'
                    ? Icon(Icons.check_circle, color: Colors.green)
                    : showResolveButton
                    ? ElevatedButton(
                  onPressed: () => _resolveCharge(charge),
                  child: Text('Resolve'),
                )
                    : showRequestResolutionButton
                    ? ElevatedButton(
                  onPressed: () =>
                      _requestChargeResolution(charge),
                  child: Text('Request Resolve'),
                )
                    : showRequestSentIndicator
                    ? Icon(Icons.hourglass_empty,
                    color: Colors.orange)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}