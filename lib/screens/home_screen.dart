import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

import '../providers/transactions_provider.dart';
import '../widgets/transaction_card.dart';
import '../services/sms_parser_service.dart'; // For Debug FAB

import '../widgets/expenses_chart.dart';
import '../models/transaction_model.dart';


enum DurationFilter { thisMonth, last30Days, last3Months, custom }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  DurationFilter _selectedFilter = DurationFilter.thisMonth;
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check clipboard once on cold start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClipboardAndParse();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardAndParse();
    }
  }

  Future<void> _checkClipboardAndParse() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim();
      
      if (text == null || text.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final lastParsedText = prefs.getString('last_parsed_clipboard');

      if (text == lastParsedText) {
        // Already processed this copied text
        return;
      }

      // Try parsing the text as an SMS (or multiple)
      final transactions = SmsParserService.parseBulkSms(text);
      if (transactions.isNotEmpty) {
        // Save to DB
        for (var t in transactions) {
          await ref.read(transactionRepositoryProvider).addTransaction(t);
        }
        
        // Remember that we successfully parsed this text to avoid duplicates
        await prefs.setString('last_parsed_clipboard', text);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("${transactions.length} Expense(s) auto-added from Clipboard!"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error checking clipboard: \$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsyncValue = ref.watch(transactionsStreamProvider);
    final appLocalizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(appLocalizations.appTitle),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear_history') {
                _confirmClearHistory(context);
              } else if (value == 'clear_memory') {
                _confirmClearMemory(context);
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'clear_history',
                child: Text('Clear Expenses History'),
              ),
              const PopupMenuItem(
                value: 'clear_memory',
                child: Text('Clear Smart Category Rules'),
              ),
            ],
          ),
        ],
      ),
      body: transactionsAsyncValue.when(
        data: (allTransactions) {
          final filteredTransactions = _getFilteredTransactions(allTransactions);
          
          if (allTransactions.isEmpty) {
             return _buildEmptyState(appLocalizations);
          }

          return Column(
            children: [
              // Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildFilterChip('This Month', DurationFilter.thisMonth),
                    const SizedBox(width: 8),
                    _buildFilterChip('Last 30 Days', DurationFilter.last30Days),
                    const SizedBox(width: 8),
                    _buildFilterChip('Last 3 Months', DurationFilter.last3Months),
                    const SizedBox(width: 8),
                    _buildFilterChip('Other', DurationFilter.custom),
                  ],
                ),
              ),

              // Expenses Chart (includes Total)
              // Only show if we have filtered data, otherwise show zero state?
              // Or just pass empty list and let chart handle it (0%)
              if (filteredTransactions.isNotEmpty)
                  ExpensesChart(transactions: filteredTransactions)
              else 
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text("No transactions in this period.", style: TextStyle(color: Colors.grey)),
                  ),
              
              const SizedBox(height: 8),
              
              // Transactions List
              Expanded(
                child: ListView.builder(
                  itemCount: filteredTransactions.length,
                  itemBuilder: (context, index) {
                    final transaction = filteredTransactions[index];
                    return TransactionCard(transaction: transaction);
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDebugDialog(context, ref),
        child: const Icon(Icons.message),
      ),
    );
  }
  
  Widget _buildEmptyState(AppLocalizations appLocalizations) {
      return Center(
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
            const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
            appLocalizations.listeningMessage,
            style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
            "No transactions found yet.",
            style: TextStyle(color: Colors.grey),
            ),
        ],
        ),
    );
  }

  Widget _buildFilterChip(String label, DurationFilter filter) {
    final isSelected = _selectedFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (filter == DurationFilter.custom) {
          _pickDateRange();
        } else {
          setState(() {
            _selectedFilter = filter;
          });
        }
      },
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _customDateRange,
    );
    
    if (result != null) {
      setState(() {
        _selectedFilter = DurationFilter.custom;
        _customDateRange = result;
      });
    }
  }

  List<Transaction> _getFilteredTransactions(List<Transaction> transactions) {
    final now = DateTime.now();
    return transactions.where((t) {
      switch (_selectedFilter) {
        case DurationFilter.thisMonth:
          return t.date.year == now.year && t.date.month == now.month;
        case DurationFilter.last30Days:
          return t.date.isAfter(now.subtract(const Duration(days: 30))) && t.date.isBefore(now);
        case DurationFilter.last3Months:
          return t.date.isAfter(now.subtract(const Duration(days: 90))) && t.date.isBefore(now);
        case DurationFilter.custom:
          if (_customDateRange == null) return true;
          // Inclusive range
          return t.date.isAfter(_customDateRange!.start.subtract(const Duration(seconds: 1))) && 
                 t.date.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
      }
    }).toList();
  }

  void _showDebugDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Simulate SMS"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Paste SMS body to test parsing:"),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () async {
              final body = controller.text;
              if (body.trim().isEmpty) return;
              
              final transactions = SmsParserService.parseBulkSms(body);
              if (transactions.isNotEmpty) {
                for (var t in transactions) {
                    await ref.read(transactionRepositoryProvider).addTransaction(t);
                }
                
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("${transactions.length} Transaction(s) Added!")),
                  );
                }
              } else {
                if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Failed to parse SMS!")),
                    );
                }
              }
            },
            child: const Text("Simulate"),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory(BuildContext context) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Clear Expenses History"),
          content: const Text("Are you sure you want to delete all your saved transactions? This cannot be undone."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final repo = ref.read(transactionRepositoryProvider);
                await repo.clearTransactions();
                if (ctx.mounted) {
                   Navigator.pop(ctx);
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text("Expense history cleared!"))
                   );
                }
              },
              child: const Text("Delete"),
            ),
          ],
        ),
      );
  }

  void _confirmClearMemory(BuildContext context) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Clear Smart Category Rules"),
          content: const Text("Are you sure you want to delete all learned merchant categories? The app will forget how you categorized previous stores."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final repo = ref.read(transactionRepositoryProvider);
                await repo.clearMerchantMemory();
                if (ctx.mounted) {
                   Navigator.pop(ctx);
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text("Smart Category Memory cleared!"))
                   );
                }
              },
              child: const Text("Delete"),
            ),
          ],
        ),
      );
  }
}
