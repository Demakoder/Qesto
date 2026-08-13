abstract interface class OpenBankingClock {
  DateTime now();
}

class SystemOpenBankingClock implements OpenBankingClock {
  const SystemOpenBankingClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

class FixedOpenBankingClock implements OpenBankingClock {
  FixedOpenBankingClock(DateTime value) : _value = value.toUtc();

  DateTime _value;

  @override
  DateTime now() => _value;

  void advance(Duration duration) {
    _value = _value.add(duration);
  }
}
