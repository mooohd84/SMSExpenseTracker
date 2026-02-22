import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/generated/app_localizations.dart';

import 'services/sms_parser_service.dart';
import 'models/transaction_model.dart';
import 'repositories/transaction_repository.dart';
import 'screens/home_screen.dart';

// Background callback placeholder (if needed later)
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(dynamic message) async {
  debugPrint("onBackgroundMessage called");
}

Future<void> _processSms(String? body) async {
  if (body == null) return;
  final transaction = SmsParserService.parseSms(body);
  if (transaction != null) {
    debugPrint("Parsed Transaction: $transaction");
    await TransactionRepository().addTransaction(transaction);
  } else {
    debugPrint("Failed to parse SMS: $body");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Isar for the main isolate
  await TransactionRepository().init();
  
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initPlatformState();
    _initAppLinks();
  }

  // Initialize Android Permissions (No SMS listening for now as plugin removed)
  Future<void> _initPlatformState() async {
    if (kIsWeb || !Platform.isAndroid) return;
    
    // Request permissions
    await Permission.sms.request();
  }

  // Initialize iOS/Deep Link Listener
  Future<void> _initAppLinks() async {
    _appLinks = AppLinks();

    // Check initial link (if app opened via link)
    try {
      final initialLink = await _appLinks.getInitialLink(); 
      if (initialLink != null) {
         _handleDeepLink(initialLink);
      }
    } catch (e) {
      // Ignore
    }

    // Listen for new links while app is open
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });
  }

  void _handleDeepLink(Uri uri) {
    // Expected format: expenses://type?body=Purchase...
    if (uri.scheme == 'expenses') {
      final body = uri.queryParameters['body'];
      debugPrint("Deep Link received with body: $body");
      _processSms(body);
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMS Expense Tracker',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), // English
        Locale('ar'), // Arabic
      ],
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
