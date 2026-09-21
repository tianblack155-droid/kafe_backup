import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/auth/login_screen.dart';
import 'features/cashier/cashier_controller.dart';
import 'features/cashier/cashier_screen.dart';

class CashierApp extends StatefulWidget {
  const CashierApp({super.key, required this.controller, this.demo = false});
  final CashierController controller;
  final bool demo;

  @override
  State<CashierApp> createState() => _CashierAppState();
}

class _CashierAppState extends State<CashierApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  bool _foreground = true;
  bool _sound = true;
  bool _wasSignedIn = false;
  int _serial = 0;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _serial = widget.controller.newOrderSerial;
    _wasSignedIn = widget.controller.signedIn;
    widget.controller.addListener(_changed);
    widget.controller.setForeground(_foreground);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.controller.initialize();
    } catch (_) {
      if (mounted) {
        setState(
          () => _startupError = 'Sesi gagal dimuat. Silakan masuk kembali.',
        );
      }
    }
  }

  void _changed() {
    final c = widget.controller;
    final alert = c.newOrderSerial != _serial && c.signedIn && _foreground;
    _serial = c.newOrderSerial;
    if (_wasSignedIn && !c.signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
          _messenger.currentState?.clearSnackBars();
        }
      });
    }
    _wasSignedIn = c.signedIn;
    if (alert) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_foreground || !c.signedIn) return;
        _messenger.currentState?.showSnackBar(
          const SnackBar(content: Text('Pesanan baru masuk')),
        );
        if (_sound) {
          unawaited(
            SystemSound.play(SystemSoundType.alert).catchError((Object _) {}),
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    widget.controller.setForeground(_foreground);
    if (!_foreground) _messenger.currentState?.clearSnackBars();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    widget.controller.setForeground(false);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kasir TerasKayuManis',
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigator,
    scaffoldMessengerKey: _messenger,
    builder: (context, child) => widget.demo
        ? Column(
            children: [
              SafeArea(
                bottom: false,
                child: Material(
                  color: const Color(0xffede0d0),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'DEMO • Data lokal, reset saat proses app ditutup. Tidak terhubung web.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              Expanded(child: child!),
            ],
          )
        : child!,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff573a29),
        primary: const Color(0xff573a29),
        secondary: const Color(0xffc8912a),
        surface: const Color(0xfffaf7f2),
      ),
      scaffoldBackgroundColor: const Color(0xfffaf7f2),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        helperMaxLines: 3,
        errorMaxLines: 3,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffdcc4a8)),
        ),
      ),
      cardTheme: CardThemeData(
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffede0d0)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => widget.controller.signedIn
          ? CashierScreen(
              controller: widget.controller,
              sound: _sound,
              onSoundChanged: (value) => setState(() => _sound = value),
            )
          : widget.demo
          ? Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: widget.controller.busy
                      ? null
                      : () => widget.controller.login('demo', ''),
                  child: const Text('Masuk demo kasir'),
                ),
              ),
            )
          : LoginScreen(
              controller: widget.controller,
              startupError: _startupError,
            ),
    ),
  );
}
