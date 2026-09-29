import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/domain/bank_browser_models.dart';
import 'package:qesto/features/bank_browser/security/bank_browser_security_policy.dart';

void main() {
  const policy = BankBrowserSecurityPolicy();
  final bank = BankConnectorRegistry.sber;

  group('BankBrowserSecurityPolicy', () {
    test('allows only configured bank and authentication origins', () {
      expect(
        policy.decide(Uri.parse('https://online.sberbank.ru/login'), bank),
        NavigationDecision.allow,
      );
      expect(
        policy.decide(Uri.parse('https://id.sber.ru/auth'), bank),
        NavigationDecision.allow,
      );
    });

    test('blocks dangerous and non-HTTPS schemes', () {
      for (final value in [
        'http://online.sberbank.ru',
        'file:///C:/secret.txt',
        'javascript:alert(1)',
        'data:text/html,test',
      ]) {
        expect(policy.decide(Uri.parse(value), bank), NavigationDecision.block);
      }
    });

    test('blocks unknown HTTPS top-level origin', () {
      expect(
        policy.decide(Uri.parse('https://example.com/help'), bank),
        NavigationDecision.block,
      );
    });

    test('sanitizes query, fragment and credentials before persistence', () {
      final result = policy.sanitizedForPersistence(
        Uri.parse('https://user:pass@online.sberbank.ru/path?token=abc#otp'),
      );
      expect(result.toString(), 'https://online.sberbank.ru/path');
    });
  });
}
