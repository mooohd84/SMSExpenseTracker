import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../providers/transactions_provider.dart';

class TransactionCard extends ConsumerWidget {
  final Transaction transaction;

  const TransactionCard({super.key, required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formattedDate = DateFormat('MMM d, yyyy - h:mm a').format(transaction.date);
    final currencyFormatter = NumberFormat.currency(symbol: 'SAR ', decimalDigits: 2);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Icon based on category or type
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIconForCategory(transaction.category),
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 16),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.merchant ?? 'Unknown Merchant',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  if (transaction.category != null)
                     InkWell(
                       onTap: () => _showCategoryEditDialog(context, ref),
                       borderRadius: BorderRadius.circular(8),
                       child: Container(
                         margin: const EdgeInsets.only(top: 8.0),
                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                         decoration: BoxDecoration(
                           color: Colors.blue.withOpacity(0.1),
                           borderRadius: BorderRadius.circular(8),
                           border: Border.all(color: Colors.blue.withOpacity(0.3)),
                         ),
                         child: Row(
                           mainAxisSize: MainAxisSize.min,
                           children: [
                             Text(
                               transaction.category!,
                               style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.blue[800],
                               ),
                             ),
                             const SizedBox(width: 4),
                             Icon(Icons.edit, size: 12, color: Colors.blue[800]),
                           ],
                         ),
                       ),
                     )
                ],
              ),
            ),
            // Amount
            Text(
              currencyFormatter.format(transaction.amount),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.redAccent, 
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryEditDialog(BuildContext context, WidgetRef ref) {
      final categories = [
          'Groceries',
          'Restaurants',
          'Coffee',
          'Gasoline',
          'Pharmacies',
          'Utilities',
          'Communication',
          'Travel & Tourism',
          'Online Shopping',
          'Cash Withdrawal',
          'Transfer',
          'Uncategorized'
      ];
      
      showDialog(
          context: context,
          builder: (context) => SimpleDialog(
              title: const Text('Select Category'),
              children: categories.map((cat) => SimpleDialogOption(
                  onPressed: () {
                      _updateCategory(context, ref, cat);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(cat),
                  ),
              )).toList(),
          ),
      );
  }

  Future<void> _updateCategory(BuildContext context, WidgetRef ref, String newCategory) async {
       // Close dialog
       Navigator.pop(context);
       
       // Update logic
       transaction.category = newCategory;
       await ref.read(transactionRepositoryProvider).updateTransaction(transaction);
       
       if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text("Category updated to $newCategory")),
           );
       }
  }

  IconData _getIconForCategory(String? category) {
    switch (category) {
      case 'POS Purchase':
        return Icons.shopping_bag;
      case 'Cash Withdrawal':
        return Icons.atm;
      case 'Groceries':
        return Icons.local_grocery_store;
      case 'Communication':
        return Icons.phone_android;
      case 'Utilities':
        return Icons.lightbulb;
      case 'Travel & Tourism':
        return Icons.flight;
      case 'Restaurants':
        return Icons.restaurant;
      case 'Coffee':
        return Icons.coffee;
      case 'Gasoline':
        return Icons.local_gas_station;
      case 'Pharmacies':
        return Icons.medical_services;
      case 'Online Shopping':
        return Icons.shopping_cart;
      case 'Transfer':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.attach_money;
    }
  }
}
