import 'dart:math';

class BankSyncConfig {
  const BankSyncConfig({
    this.backgroundBankSyncEnabled = true,
    this.baseInterval = const Duration(hours: 1),
    this.jitterPercent = 0.10,
    this.minimumInterval = const Duration(minutes: 45),
    this.retrySchedule = const [
      Duration(minutes: 10),
      Duration(minutes: 30),
      Duration(minutes: 60),
    ],
    this.retryJitterPercent = 0.10,
    this.parserRetryLimit = 2,
    this.browserStartupTimeout = const Duration(seconds: 35),
    this.pageLoadTimeout = const Duration(seconds: 45),
    this.syncScenarioTimeout = const Duration(minutes: 4),
    this.totalSyncTimeout = const Duration(minutes: 5),
    this.browserShutdownTimeout = const Duration(seconds: 15),
    this.busyRescheduleDelay = const Duration(minutes: 5),
    this.queueSpacing = const Duration(seconds: 4),
  });

  final bool backgroundBankSyncEnabled;
  final Duration baseInterval;
  final double jitterPercent;
  final Duration minimumInterval;
  final List<Duration> retrySchedule;
  final double retryJitterPercent;
  final int parserRetryLimit;
  final Duration browserStartupTimeout;
  final Duration pageLoadTimeout;
  final Duration syncScenarioTimeout;
  final Duration totalSyncTimeout;
  final Duration browserShutdownTimeout;
  final Duration busyRescheduleDelay;
  final Duration queueSpacing;
}

class BankSyncSchedulePolicy {
  BankSyncSchedulePolicy({this.config = const BankSyncConfig(), Random? random})
    : random = random ?? Random.secure();

  final BankSyncConfig config;
  final Random random;

  Duration plannedDelay() =>
      _withJitter(config.baseInterval, config.jitterPercent);

  DateTime plannedAfter(DateTime anchor) => anchor.add(plannedDelay());

  Duration retryDelay(int consecutiveFailures) {
    if (config.retrySchedule.isEmpty) return plannedDelay();
    final index = (consecutiveFailures - 1)
        .clamp(0, config.retrySchedule.length - 1)
        .toInt();
    return _withJitter(config.retrySchedule[index], config.retryJitterPercent);
  }

  DateTime retryAfter(DateTime anchor, int consecutiveFailures) =>
      anchor.add(retryDelay(consecutiveFailures));

  Duration _withJitter(Duration source, double percent) {
    if (source == Duration.zero || percent <= 0) return source;
    final bounded = percent.clamp(0, 0.5);
    final factor = 1 + ((random.nextDouble() * 2) - 1) * bounded;
    return Duration(milliseconds: (source.inMilliseconds * factor).round());
  }
}
