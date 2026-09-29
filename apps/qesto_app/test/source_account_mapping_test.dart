import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  SynoballCore engine() => SynoballCore(
    initialState: SynoballState(
      accounts: [
        for (final id in ['a', 'b'])
          SynoballAccount(
            id: id,
            entityId: 'e',
            name: id,
            type: SynoballAccountType.checking,
            currency: 'RUB',
            balance: const Money(minorUnits: 0, currency: 'RUB'),
          ),
      ],
    ),
  );
  test(
    'confirmed mapping survives serialization and repeated confirmation',
    () {
      final core = engine();
      core.linkSourceAccount(
        entityId: 'e',
        sourceKey: 'hash',
        accountId: 'a',
        actorId: 'user',
      );
      core.linkSourceAccount(
        entityId: 'e',
        sourceKey: 'hash',
        accountId: 'a',
        actorId: 'user',
      );
      expect(
        core.state.events.where((e) => e.type == 'account.source-linked'),
        hasLength(1),
      );
      final restored = SynoballCore(
        initialState: SynoballState.fromJson(core.state.toJson()),
      );
      expect(restored.sourceAccountMapping('e', 'hash'), 'a');
      expect(restored.sourceAccountMapping('another-user', 'hash'), isNull);
    },
  );
  test('silent remapping is refused and original mapping preserved', () {
    final core = engine();
    core.linkSourceAccount(
      entityId: 'e',
      sourceKey: 'hash',
      accountId: 'a',
      actorId: 'user',
    );
    expect(
      () => core.linkSourceAccount(
        entityId: 'e',
        sourceKey: 'hash',
        accountId: 'b',
        actorId: 'user',
      ),
      throwsStateError,
    );
    expect(core.sourceAccountMapping('e', 'hash'), 'a');
  });
  test('mapping follows an explicitly merged account', () {
    final core = engine();
    core.linkSourceAccount(
      entityId: 'e',
      sourceKey: 'hash',
      accountId: 'a',
      actorId: 'user',
    );
    core.mergeAccountInto(
      duplicateAccountId: 'a',
      primaryAccountId: 'b',
      actorId: 'user',
      purpose: 'Verified same product',
    );
    expect(core.sourceAccountMapping('e', 'hash'), 'b');
  });
  test('a dangling confirmed link cannot be silently reassigned', () {
    final core = engine();
    core.linkSourceAccount(
      entityId: 'e',
      sourceKey: 'hash',
      accountId: 'a',
      actorId: 'user',
    );
    core.removeAccountIfUnused('a');
    expect(core.sourceAccountMapping('e', 'hash'), isNull);
    expect(
      () => core.linkSourceAccount(
        entityId: 'e',
        sourceKey: 'hash',
        accountId: 'b',
        actorId: 'user',
      ),
      throwsStateError,
    );
  });
}
