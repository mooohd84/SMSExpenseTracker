import 'package:flutter_test/flutter_test.dart';
import 'package:sms_expenses_tracker/services/sms_parser_service.dart';

void main() {
  test('Amazon SA multiple SAR format test', () {
    const bulkBody = '''
Online Purchase
SAR 87.94
At Amazon SA
Credit Card *6140
Account *0505
Total Amount Due SAR 6739.96
Remaining Limit SAR 13260.04
On 26-01-13 21:51
''';

    final transactions = SmsParserService.parseBulkSms(bulkBody);
    print("Parsed ${transactions.length} transactions.");
    
    for (var i = 0; i < transactions.length; i++) {
       final t = transactions[i];
       print("Tx \$i:");
       print("Amount: ${t.amount}");
       print("Merchant: ${t.merchant}");
       print("Date: ${t.date}");
       print("Category: ${t.category}");
    }
  });

  test('Single transaction single parse', () {
    const bulkBody = '''
Online Purchase
SAR 87.94
At Amazon SA
Credit Card *6140
Account *0505
Total Amount Due SAR 6739.96
Remaining Limit SAR 13260.04
On 26-01-13 21:51
''';

   final t = SmsParserService.parseSms(bulkBody);
   print("Single Amount: ${t?.amount}");
   print("Single Merchant: ${t?.merchant}");
   print("Single Date: ${t?.date}");
  });
}
