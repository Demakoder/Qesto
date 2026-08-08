import '../../data/models/qesto_models.dart';

final emptyUserFinancialData = UserFinancialData(
  user: const QestoUser(
    id: 'local-user',
    name: 'Пользователь',
    defaultCurrency: 'RUB',
  ),
  referenceDate: DateTime.now(),
);
