import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../domain/models.dart';

/// Immutable attempt is persisted before checkout; never regenerate on retry.
class CheckoutAttempt {
  CheckoutAttempt(this.key, this.token, this.draft);
  factory CheckoutAttempt.create(ReorderDraft draft) {
    final random = Random.secure();
    return CheckoutAttempt(
      const Uuid().v4(),
      base64Url
          .encode(List.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', ''),
      draft,
    );
  }
  final String key, token;
  final ReorderDraft draft;
  String encode() =>
      jsonEncode({'key': key, 'token': token, 'payload': draft.toJson()});
  factory CheckoutAttempt.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final key = json['key'] as String, token = json['token'] as String;
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(key) ||
        token.length < 24 ||
        token.length > 256) {
      throw const FormatException('Invalid saved attempt');
    }
    final payload = json['payload'] as Map<String, dynamic>;
    final draft = ReorderDraft.fromJson(payload);
    if (jsonEncode(payload) != jsonEncode(draft.toJson())) {
      throw const FormatException('Incompatible saved attempt');
    }
    return CheckoutAttempt(key, token, draft);
  }
}
