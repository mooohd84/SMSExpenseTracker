import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction_model.dart';
import '../repositories/transaction_repository.dart';

// Provides the singleton repository instance
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository();
});

// Provides the stream of transactions
final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) async* {
  final repository = ref.watch(transactionRepositoryProvider);
  await repository.init(); // Ensure initialized
  yield* repository.watchTransactions();
});

// FutureProvider for initial loading or one-off fetches if needed
final recentTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final repository = ref.watch(transactionRepositoryProvider);
  await repository.init();
  return repository.getAllTransactions();
});
