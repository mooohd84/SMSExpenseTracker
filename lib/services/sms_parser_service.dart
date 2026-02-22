import '../models/transaction_model.dart';

class SmsParserService {
  /// Parses raw SMS body text into a [Transaction] object.
  /// Returns null if the format is not recognized.
  static Transaction? parseSms(String body) {
    // 1. Normalize text: reduce multiple spaces to one, trim
    final cleanBody = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // 2. Extract Amount (The most critical field)
    final amount = _extractAmount(cleanBody);
    if (amount == null) {
      // If we can't find an amount, it's likely not a transaction SMS
      return null;
    }

    // 3. Extract Date
    final date = _extractDate(cleanBody) ?? DateTime.now();

    // 4. Extract Merchant
    final merchant = _extractMerchant(cleanBody) ?? 'Unknown Merchant';
    
    // 5. Determine Category based on keywords and merchant
    final category = _determineCategory(cleanBody, merchant);

    return Transaction()
      ..amount = amount
      ..merchant = merchant
      ..date = date
      ..category = category
      ..originalSmsBody = body;
  }
  static double? _extractAmount(String body) {
    // Supports: SAR 123.45 (Prefix), 123.45 SAR (Suffix)
    // Arabic: ر.س 123
    final currencyCodes = r'(?:SAR|SAR\.|SR|RYL|ر\.س|ر\.س\.|KSA)';
    // Group 1: Amount (Prefix case), Group 2: Amount (Suffix case)
    final currencyPattern = RegExp(
        '(?:$currencyCodes\\s*(\\d+(?:\\.\\d{1,2})?))|' +
        '(?:(\\d+(?:\\.\\d{1,2})?)\\s*$currencyCodes)', 
        caseSensitive: false
    );
    
    final match = currencyPattern.firstMatch(body);
    
    if (match != null) {
      final amountStr = match.group(1) ?? match.group(2);
      return double.tryParse(amountStr ?? '');
    }
    return null;
  }
  
  // ... _extractDate ...

  static String? _extractMerchant(String body) {
    // Strategy 1: Explicit "at"/"to" markers (with optional colon coverage)
    // Matches: "at Merchant", "at:Merchant", "لدى:Merchant", "to Merchant"
    final startMarkersPattern = RegExp(r'(?:at|At|@|لدى|to)[:\s]+');
    final endMarkers = ['on', 'On', 'via', 'through', 'using', 'account', 'mada', 'في', 'outstanding', 'available', 'balance', 'credit', '*', 'debit', 'رصيد'];
    
    int startIndex = -1;
    final match = startMarkersPattern.firstMatch(body);
    if (match != null) {
        startIndex = match.end;
    }

    if (startIndex != -1) {
       // Replace newlines with spaces so that newlines don't break the regex or index search
       String remaining = body.substring(startIndex).replaceAll('\n', ' ');
       String lowerRemaining = remaining.toLowerCase();
       int closestEndIndex = remaining.length;
       for (var m in endMarkers) {
          final idx = lowerRemaining.indexOf(" $m "); // check with spaces
          if (idx != -1 && idx < closestEndIndex) {
              closestEndIndex = idx;
          }
          // specific check for Arabic/Colon delimiters in end markers if needed
          final idxColon = lowerRemaining.indexOf("$m:");
           if (idxColon != -1 && idxColon < closestEndIndex) {
              closestEndIndex = idxColon;
          }
           // Check for new line as terminator (ONLY if it's two newlines, indicating end of block, 
           // but we've already normalized text, so single newline is just a space)
           // Actually, let's just replace \n with space in `remaining` before processing to make it robust.
           // Removed the `\n` stop index check because merchant names might be on the next line.
       }
       String rawMerchant = remaining.substring(0, closestEndIndex).trim();
       if (rawMerchant.isNotEmpty) return rawMerchant;
    }

    // Strategy 2: Heuristic - Between Amount and Date/End
    // Find amount end (Robust Regex)
    final currencyCodes = r'(?:SAR|SAR\.|SR|RYL|ر\.س|ر\.س\.|KSA)';
    final currencyPattern = RegExp(
        '(?:$currencyCodes\\s*(\\d+(?:\\.\\d{1,2})?))|' +
        '(?:(\\d+(?:\\.\\d{1,2})?)\\s*$currencyCodes)', 
        caseSensitive: false
    );
    final amountMatch = currencyPattern.firstMatch(body);
    
    if (amountMatch != null) {
        int merchantStart = amountMatch.end;
        String candidate = body.substring(merchantStart).replaceAll('\n', ' ');
        
        // Find Date or "on" marker to stop
        int stopIndex = candidate.length;
        
        // Check for specific stop words first
        for (var m in endMarkers) {
             final idx = candidate.toLowerCase().indexOf(" $m ");
             if (idx != -1 && idx < stopIndex) {
                 stopIndex = idx;
             }
        }
        
        // We won't stop at \n anymore since some banks put merchant on the second line.
        
        // Also check if we see a date pattern
        final datePattern = RegExp(r'\d{2,4}[-/]\d{2}[-/]\d{2,4}');
        final dateMatch = datePattern.firstMatch(candidate);
        if (dateMatch != null && dateMatch.start < stopIndex) {
            stopIndex = dateMatch.start;
        }

        String extracted = candidate.substring(0, stopIndex).trim();
        // Clean up common prefix noise often found after amount if "at" is missing
        // e.g. "SAR 50.00 POS Purchase STARBUCKS"
        final noiseWords = ['pos', 'purchase', 'withdrawal', 'transfer', 'payment', 'transaction'];
        for (var w in noiseWords) {
             if (extracted.toLowerCase().startsWith("$w ")) {
                 extracted = extracted.substring(w.length + 1).trim();
             }
        }
        
        // Remove leading punctuation/digits
        extracted = extracted.replaceAll(RegExp(r'^[\d\W]+'), '');

        if (extracted.isNotEmpty && extracted.length < 50) { // arbitrary max length sanity check
            return extracted.trim();
        }
    }

    return null;
  }

  static DateTime? _extractDate(String body) {
    // 1. Try ISO (YYYY-MM-DD)
    final isoRegex = RegExp(r'(\d{4}-\d{2}-\d{2})');
    final isoMatch = isoRegex.firstMatch(body);
    if (isoMatch != null) {
       final d = DateTime.tryParse(isoMatch.group(1)!);
       if (d != null && !d.isAfter(DateTime.now())) return d;
    }

    // 2. Try DD-MM-YYYY (4 digit year)
    // e.g. 28-10-2025
    final longRegex = RegExp(r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})(?:\s+(\d{2}:\d{2}))?');
    final longMatch = longRegex.firstMatch(body);
    if (longMatch != null) {
       final day = int.parse(longMatch.group(1)!);
       final month = int.parse(longMatch.group(2)!);
       final year = int.parse(longMatch.group(3)!);
       
       final timePart = longMatch.group(4) ?? '00:00';
       final tParts = timePart.split(':');
       final hour = int.parse(tParts[0]);
       final minute = int.parse(tParts[1]);

       final d = DateTime(year, month, day, hour, minute);
       if (!d.isAfter(DateTime.now())) return d;
    }

    // 3. Try Short patterns (XX-XX-XX)
    final shortRegex = RegExp(r'(\d{2})[-/](\d{2})[-/](\d{2})(?:\s+(\d{2}:\d{2}))?');
    final shortMatch = shortRegex.firstMatch(body);
    
    if (shortMatch != null) {
      final p1 = int.parse(shortMatch.group(1)!);
      final p2 = int.parse(shortMatch.group(2)!);
      final p3 = int.parse(shortMatch.group(3)!);
      final timePart = shortMatch.group(4) ?? '00:00';
      final tParts = timePart.split(':');
      final hour = int.parse(tParts[0]);
      final minute = int.parse(tParts[1]);

      // Helper to build and validate date
      DateTime? tryDate(int y, int m, int d) {
         if (m < 1 || m > 12) return null;
         if (d < 1 || d > 31) return null;
         final fullYear = y < 100 ? 2000 + y : y;
         final date = DateTime(fullYear, m, d, hour, minute);
         // Reject future dates (allow 1 day buffer for timezone diffs)
         if (date.isAfter(DateTime.now().add(const Duration(days: 1)))) return null;
         return date;
      }

      // Priority 1: YY-MM-DD (User Reference)
      // e.g. 17-01-26 -> 2017 Jan 26
      if (p1 > 0) {
         final d = tryDate(p1, p2, p3);
         if (d != null) return d;
      }

      // Priority 2: DD-MM-YY (Common Bank Format)
      // e.g. 26-01-17 -> 2017 Jan 26
      final d2 = tryDate(p3, p2, p1);
      if (d2 != null) return d2;

      // Priority 3: YYYY-MM-DD (if p1 is large 4 digit caught by 2 digit regex?? Unlikely but safe)
    }
    
    return null;
  }



  // Helper function to check keywords
  static bool _hasKeyword(String text, List<String> keywords) {
    for (var k in keywords) {
      // Use word boundaries to avoid partial matches (e.g. 'se' in 'Purchase')
      if (RegExp(r'\b' + RegExp.escape(k) + r'\b', caseSensitive: false).hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  static String _determineCategory(String body, String merchant) {
    final text = '$body $merchant'.toLowerCase();
    
    // 1. Utilities
    if (_hasKeyword(text, ['electricity', 'water', 'se', 'nwc', 'alkahraba', 'utility', 'bill'])) {
      return 'Utilities';
    }
    
    // 2. Communication / Telecom
    if (_hasKeyword(text, ['stc', 'mobily', 'zain', 'virgin', 'salam', 'telecom'])) {
      return 'Communication';
    }
    
    // 3. Groceries
    if (_hasKeyword(text, ['panda', 'othaim', 'danube', 'tamimi', 'lulu', 'carrefour', 'market', 'grocery', 'supermarket', 'bakala', 'food', 'farm', 'spar'])) {
      return 'Groceries';
    }
    
    // 4. Gasoline / Fuel
    if (_hasKeyword(text, ['gas', 'station', 'fuel', 'petrol', 'sasco', 'oil', 'naft', 'aldrees', 'way'])) {
      return 'Gasoline';
    }

    // 5. Coffee
    if (_hasKeyword(text, ['coffee', 'cafe', 'starbucks', 'dunkin', 'tim hortons', 'barns', 'espresso', 'latte', 'dose', 'brew'])) {
       return 'Coffee';
    }

    // 6. Pharmacies
    if (_hasKeyword(text, ['pharmacy', 'medical', 'health', 'nahdi', 'dawa', 'boots', 'whites', 'lemon'])) {
       return 'Pharmacies';
    }

    // 7. Restaurants (Removed coffee keywords)
    if (_hasKeyword(text, ['restaurant', 'burger', 'pizza', 'mcdonald', 'kfc', 'subway', 'shawarma', 'kudu', 'herfy', 'baik', 'domin'])) {
      return 'Restaurants';
    }
    
    // 5. Travel & Tourism
    if (_hasKeyword(text, ['hotel', 'airline', 'fly', 'air', 'booking', 'agoda', 'trip', 'travel', 'uber', 'careem', 'bolt', 'jeeny', 'kaiian'])) {
      return 'Travel & Tourism';
    }
    
    // 6. Online Shopping
    if (_hasKeyword(text, ['amazon', 'noon', 'namshi', 'jarir', 'extra', 'shop', 'online', 'shein', 'temy', 'apple', 'google', 'itunes'])) {
      return 'Online Shopping';
    }
    
    // 7. General Transaction Types
    if (text.contains('withdrawal') || text.contains('cash') || text.contains('atm') || text.contains('سحب')) {
      return 'Cash Withdrawal';
    }
    if (text.contains('transfer') || text.contains('salary') || text.contains('deposit')) {
        return 'Transfer';
    }
    
    // Default fallback
    return 'Uncategorized';
  }

  /// Wrapper to handle parsing multiple SMS messages pasted/copied together.
  /// Splits by double newlines or single newlines depending on structure,
  /// and feeds each chunk to the single parser.
  static List<Transaction> parseBulkSms(String bulkBody) {
    final normalized = bulkBody.replaceAll('\r\n', '\n');
    
    // Pattern to detect if a string has a currency amount
    final currencyPattern = RegExp(
        r'(?:(?:SAR|SAR\.|SR|RYL|ر\.س|ر\.س\.|KSA)\s*\d+(?:\.\d{1,2})?)|'
        r'(?:\d+(?:\.\d{1,2})?\s*(?:SAR|SAR\.|SR|RYL|ر\.س|ر\.س\.|KSA))', 
        caseSensitive: false
    );

    // Group lines into logical chunks per transaction.
    // Each transaction should ideally have exactly one amount string.
    final List<String> logicalChunks = [];
    String currentChunk = "";
    
    // Keywords that indicate a secondary amount in the same message, not a new message barrier.
    final secondaryAmountKeywords = ['due', 'limit', 'available', 'outstanding', 'balance', 'credit', 'رصيد', 'متبقي'];

    for (var line in normalized.split('\n')) {
      final lowerLine = line.toLowerCase();
      bool hasSecondaryKeyword = secondaryAmountKeywords.any((k) => lowerLine.contains(k));

      if (currencyPattern.hasMatch(line) && !hasSecondaryKeyword) {
         // If current chunk already has a primary amount, it's a complete message. Save it.
         if (currentChunk.isNotEmpty && currencyPattern.hasMatch(currentChunk)) {
             logicalChunks.add(currentChunk.trim());
             currentChunk = line;
         } else {
             // Otherwise, append to existing chunk
             currentChunk += (currentChunk.isEmpty ? "" : " ") + line;
         }
      } else {
         currentChunk += (currentChunk.isEmpty ? "" : " ") + line;
      }
    }
    
    if (currentChunk.isNotEmpty) {
      logicalChunks.add(currentChunk.trim());
    }

    final List<Transaction> validTransactions = [];
    for (var chunk in logicalChunks) {
      if (chunk.trim().isEmpty) continue;
      final tx = parseSms(chunk);
      if (tx != null) {
        validTransactions.add(tx);
      }
    }

    // Fallback: if grouping completely failed, try treating the whole block as 1 message
    if (validTransactions.isEmpty) {
        final single = parseSms(normalized);
        if (single != null) return [single];
    }

    return validTransactions;
  }
}
