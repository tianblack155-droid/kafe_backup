import 'package:flutter/material.dart';

import 'app.dart';
import 'demo/demo_cashier.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CashierApp(controller: createDemoController(), demo: true));
}
