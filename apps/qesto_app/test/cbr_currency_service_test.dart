import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/profile/services/cbr_currency_service.dart';

void main() {
  test('CBR XML adapter normalizes unit rates without changing finance data', () {
    const xml = '''
      <ValCurs Date="14.08.2026" name="Foreign Currency Market">
        <Valute ID="R01235">
          <CharCode>USD</CharCode><Nominal>1</Nominal>
          <Value>79,7653</Value><VunitRate>79,7653</VunitRate>
        </Valute>
        <Valute ID="R01335">
          <CharCode>KZT</CharCode><Nominal>100</Nominal>
          <Value>14,7500</Value>
        </Valute>
      </ValCurs>
    ''';

    final snapshot = CbrCurrencyService().parse(xml);

    expect(snapshot.date, DateTime(2026, 8, 14));
    expect(snapshot.rates['RUB']?.rublesPerUnit, 1);
    expect(snapshot.rates['USD']?.rublesPerUnit, closeTo(79.7653, 0.00001));
    expect(snapshot.rates['KZT']?.rublesPerUnit, closeTo(0.1475, 0.00001));
  });
}
