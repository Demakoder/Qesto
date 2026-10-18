// Run under the EXISTING app package config. Never open a repository/profile.
import 'dart:convert';
import 'dart:io';
import '../../../apps/qesto_app/lib/data/persistence/user_financial_data_codec.dart';

void main(List<String> args) {
  final path = File(args.single).absolute.path;
  if (!path.contains('qesto-storage-spike-'))
    throw StateError('synthetic-only');
  const codec = UserFinancialDataCodec();
  final original = File(path).readAsStringSync();
  final restored = codec.decode(original), next = codec.encode(restored);
  // Key ordering is not part of the v7 contract; all values and list orders are.
  Object? sorted(Object? v) => switch (v) {
    Map m => {
      for (final k in (m.keys.cast<String>().toList()..sort())) k: sorted(m[k]),
    },
    List l => l.map(sorted).toList(),
    _ => v,
  };
  if (jsonEncode(sorted(jsonDecode(original))) !=
      jsonEncode(sorted(jsonDecode(next))))
    throw StateError('actual-v7-codec-lossless-gate');
  print(
    jsonEncode({
      'codec': 7,
      'lossless': true,
      'accounts': restored.accounts.length,
      'goals': restored.savingsGoals.length,
      'debts': restored.debts.length,
      'investments': restored.investmentAccounts.length,
      'canonical': restored.synoballState!.transactions.length,
    }),
  );
}
