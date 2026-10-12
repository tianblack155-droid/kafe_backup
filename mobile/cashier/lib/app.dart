import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_theme.dart';
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
    theme: buildAppTheme(),
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => widget.controller.signedIn
          ? CashierScreen(
              controller: widget.controller,
              sound: _sound,
              onSoundChanged: (value) => setState(() => _sound = value),
              demo: widget.demo,
            )
          : LoginScreen(
              controller: widget.controller,
              startupError: _startupError,
            ),
    ),
  );
}
