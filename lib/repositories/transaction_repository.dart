import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';

class TransactionRepository {
  late Isar _isar;
  
  // Web Fallback Storage & Learning
  final List<Transaction> _webStorage = [];
  Map<String, String> _merchantCategoryMap = {};
  final _webStreamController = StreamController<List<Transaction>>.broadcast();

  // Singleton pattern
  static final TransactionRepository _instance = TransactionRepository._internal();
  factory TransactionRepository() => _instance;
  TransactionRepository._internal();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    if (kIsWeb) {
      debugPrint("Initializing Web Repository (In-Memory)");
      final prefs = await SharedPreferences.getInstance();
      
      // Load learned categories
      final String? storedMap = prefs.getString('merchant_category_map');
      if (storedMap != null) {
          try {
             final decoded = json.decode(storedMap) as Map<String, dynamic>;
             _merchantCategoryMap = decoded.map((k, v) => MapEntry(k, v.toString()));
          } catch (e) {
             debugPrint("Error loading merchant map: $e");
          }
      }

      // Load transactions
      final String? storedTxns = prefs.getString('web_transactions');
      if (storedTxns != null) {
          try {
             final List<dynamic> decoded = json.decode(storedTxns);
             _webStorage.clear();
             _webStorage.addAll(decoded.map((e) => Transaction.fromJson(e)).toList());
             // Sort after load
              _webStorage.sort((a, b) => b.date.compareTo(a.date));
          } catch (e) {
             debugPrint("Error loading transactions: $e");
          }
      }
      
      _isInitialized = true;
      // Emit initial state
      _webStreamController.add(List.from(_webStorage));
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
        // Fallback for other platforms if needed
        return;
    }
    
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [TransactionSchema],
      directory: dir.path,
    );
    _isInitialized = true;
  }

  // ... initBackground ...

  Future<void> addTransaction(Transaction transaction) async {
    if (!_isInitialized) await init();
    
    // Smart LEarning: Check if we have a learned category for this merchant
    if (transaction.merchant != null && transaction.merchant != 'Unknown Merchant') {
         // Normalized key
         final key = transaction.merchant!.trim().toLowerCase();
         if (_merchantCategoryMap.containsKey(key)) {
             transaction.category = _merchantCategoryMap[key];
         }
    }

    if (kIsWeb) {
      // Simulate Auto-Increment ID for Web
      if (transaction.id == Isar.autoIncrement) {
         transaction.id = DateTime.now().millisecondsSinceEpoch;
      }
      _webStorage.add(transaction);
      // Sort desc
      _webStorage.sort((a, b) => b.date.compareTo(a.date));
      _webStreamController.add(List.from(_webStorage));
      await _saveWebTransactions();
      return;
    }
    
    await _isar.writeTxn(() async {
      await _isar.transactions.put(transaction);
    });
  }

  Future<void> updateTransaction(Transaction transaction) async {
      if (!_isInitialized) await init();

      // Smart Learning: Learn this preference
      if (transaction.merchant != null && transaction.category != null && transaction.merchant != 'Unknown Merchant') {
          final key = transaction.merchant!.trim().toLowerCase();
          _merchantCategoryMap[key] = transaction.category!;
          if (kIsWeb) {
              debugPrint("Learned: $key -> ${transaction.category}");
              await _saveMerchantMap();
          }
      }

      if (kIsWeb) {
        final index = _webStorage.indexWhere((t) => t.id == transaction.id);
        if (index != -1) {
          _webStorage[index] = transaction;
          _webStorage.sort((a, b) => b.date.compareTo(a.date));
          _webStreamController.add(List.from(_webStorage));
          await _saveWebTransactions();
        }
        return;
      }

      await _isar.writeTxn(() async {
        await _isar.transactions.put(transaction);
      });
  }

  Future<void> _saveMerchantMap() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('merchant_category_map', json.encode(_merchantCategoryMap));
  }

  Future<void> _saveWebTransactions() async {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList = _webStorage.map((t) => t.toJson()).toList();
      await prefs.setString('web_transactions', json.encode(jsonList));
  }

  Future<List<Transaction>> getAllTransactions() async {
    if (!_isInitialized) await init();
    
    if (kIsWeb) {
        return List.from(_webStorage);
    }

    return await _isar.transactions.where().sortByDateDesc().findAll();
  }

  Stream<List<Transaction>> watchTransactions() async* {
    if (!_isInitialized) await init();
    
    if (kIsWeb) {
        // Yield current state immediately so UI doesn't get stuck in loading
        yield List.from(_webStorage);
        yield* _webStreamController.stream;
    } else {
        yield* _isar.transactions
            .where()
            .sortByDateDesc()
            .watch(fireImmediately: true);
    }
  }
  
  // Data Purging Option 1: Clear History
  Future<void> clearTransactions() async {
    if (!_isInitialized) await init();

    if (kIsWeb) {
        _webStorage.clear();
        _webStreamController.add([]);
        await _saveWebTransactions();
        return;
    }

    await _isar.writeTxn(() async {
        await _isar.transactions.clear();
    });
  }

  // Data Purging Option 2: Clear Categorization Memory
  Future<void> clearMerchantMemory() async {
    if (!_isInitialized) await init();
    
    _merchantCategoryMap.clear();
    
    if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('merchant_category_map');
    }
  }

  // Clean up
  Future<void> close() async {
    if (_isInitialized) {
        if (kIsWeb) {
            _webStreamController.close();
        } else {
            await _isar.close();
        }
      _isInitialized = false;
    }
  }
}
