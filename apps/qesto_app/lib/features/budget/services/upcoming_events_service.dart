import 'dart:math' as math;

import '../../../data/models/qesto_models.dart';
import '../../../features/capital/domain/debt_analytics_service.dart';
import '../../../synoball/core/models.dart';
import '../../../synoball/enrichment/enrichment.dart';
import '../../../synoball/enrichment/recurrence_calendar.dart';

enum UpcomingEventOrigin {
  inferredRecurring,
  manualOneTime,
  manualRecurring,
  debt,
}

class UpcomingPaymentEvent {
  const UpcomingPaymentEvent({
    required this.id,
    required this.sourceId,
    required this.origin,
    required this.title,
    required this.amount,
    required this.currency,
    required this.date,
    this.frequency,
    this.isEstimate = false,
    this.isOverdue = false,
  });

  final String id;
  final String sourceId;
  final UpcomingEventOrigin origin;
  final String title;
  final int amount;
  final String currency;
  final DateTime date;
  final RecurrenceFrequency? frequency;
  final bool isEstimate;
  final bool isOverdue;
}

class UpcomingEventsSnapshot {
  const UpcomingEventsSnapshot({
    required this.upcoming,
    required this.overdue,
    required this.tentativeStreams,
    required this.tentativeEvents,
    required this.monthlyRegularByCurrency,
    required this.detectedStreamCount,
  });

  final List<UpcomingPaymentEvent> upcoming;
  final List<UpcomingPaymentEvent> overdue;
  final List<RecurringStream> tentativeStreams;
  final List<UpcomingPaymentEvent> tentativeEvents;
  final Map<String, int> monthlyRegularByCurrency;
  final int detectedStreamCount;

  UpcomingPaymentEvent? get nextEvent => upcoming.firstOrNull;
}

/// A read-only projection over existing local sources. Neither inferred nor
/// debt events are persisted here, and no observed transaction is created.
class UpcomingEventsService {
  const UpcomingEventsService({
    this.enrichment = const EnrichmentEngine(),
    this.debtAnalytics = const DebtAnalyticsService(),
  });

  final EnrichmentEngine enrichment;
  final DebtAnalyticsService debtAnalytics;

  UpcomingEventsSnapshot build({
    required String userId,
    required DateTime asOf,
    required Iterable<RecurringStream> streams,
    Iterable<CanonicalTransaction> transactions = const [],
    required Iterable<UpcomingExpense> manualExpenses,
    required Iterable<DebtAccount> debts,
  }) {
    final today = _day(asOf);
    final ownedExpenses = manualExpenses
        .where(
          (item) =>
              item.userId == userId && !item.isCancelled && item.amount > 0,
        )
        .toList(growable: false);
    final manual = ownedExpenses
        .where((item) => item.source == UpcomingExpenseSource.manual)
        .toList(growable: false);
    final ownedStreams = streams
        .where((item) => item.entityId == 'ent-$userId')
        .toList(growable: false);
    final observedById = <String, CanonicalTransaction>{
      for (final transaction in transactions)
        if (transaction.entityId == 'ent-$userId') transaction.id: transaction,
    };
    final upcoming = <UpcomingPaymentEvent>[];
    final overdue = <UpcomingPaymentEvent>[];
    final tentativeEvents = <UpcomingPaymentEvent>[];
    final monthlyRegular = <String, int>{};
    void addRegular(String currency, int amount, RecurrenceFrequency cadence) {
      monthlyRegular.update(
        currency,
        (value) => value + _monthlyEquivalent(amount, cadence),
        ifAbsent: () => _monthlyEquivalent(amount, cadence),
      );
    }

    for (final item in manual) {
      final frequency = item.isRecurring
          ? frequencyForRule(item.recurrenceRule)
          : null;
      final date = frequency == null
          ? item.plannedDate
          : nextOccurrenceOnOrAfter(item.plannedDate, frequency, today);
      final isOverdue = frequency == null && _day(date).isBefore(today);
      final event = UpcomingPaymentEvent(
        id: 'manual-${item.id}',
        sourceId: item.id,
        origin: frequency == null
            ? UpcomingEventOrigin.manualOneTime
            : UpcomingEventOrigin.manualRecurring,
        title: item.title,
        amount: item.amount,
        currency: item.currency,
        date: date,
        frequency: frequency,
        isOverdue: isOverdue,
      );
      (isOverdue ? overdue : upcoming).add(event);
      if (frequency != null) {
        addRegular(item.currency, item.amount, frequency);
      }
    }

    for (final stream in ownedStreams.where((item) => !item.isTentative)) {
      final amount = stream.typicalAmount.minorUnits ~/ 100;
      if (amount <= 0) continue;
      // An unobserved, stale subscription is not an indefinite obligation.
      // Repeatedly advancing its forecast would invent payments for years.
      if (_day(stream.nextExpectedAt).isBefore(today)) continue;
      final sameManual = _hasManualOverride(
        manual,
        stream.merchantKey,
        stream.typicalAmount.currency,
        stream.nextExpectedAt,
        amount,
        today,
      );
      if (sameManual) continue;
      final observedAmounts = [
        for (final id in stream.transactionIds)
          if (observedById[id] case final transaction?)
            transaction.amount.minorUnits,
      ];
      final variableAmount =
          observedAmounts.length < 2 ||
          observedAmounts.reduce(math.max) >
              observedAmounts.reduce(math.min) * 1.05;
      upcoming.add(
        UpcomingPaymentEvent(
          id: 'inferred-${stream.id}',
          sourceId: stream.id,
          origin: UpcomingEventOrigin.inferredRecurring,
          title: stream.title,
          amount: amount,
          currency: stream.typicalAmount.currency,
          date: stream.nextExpectedAt,
          frequency: stream.frequency,
          isEstimate: variableAmount,
        ),
      );
      addRegular(stream.typicalAmount.currency, amount, stream.frequency);
    }

    // Preserve older saved subscription/detected entries that predate
    // Synoball streams. They are plans, never observed transactions.
    var legacyDetectedCount = 0;
    for (final item in ownedExpenses.where(
      (item) => item.source != UpcomingExpenseSource.manual,
    )) {
      final frequency = item.isRecurring
          ? frequencyForRule(item.recurrenceRule)
          : null;
      final date = frequency == null
          ? item.plannedDate
          : nextOccurrenceOnOrAfter(item.plannedDate, frequency, today);
      final merchantKey = enrichment.normalizedMerchantKey(item.title);
      if (_hasManualOverride(
        manual,
        merchantKey,
        item.currency,
        date,
        item.amount,
        today,
      )) {
        continue;
      }
      if (upcoming.any(
        (existing) =>
            existing.origin == UpcomingEventOrigin.inferredRecurring &&
            existing.currency == item.currency &&
            enrichment.normalizedMerchantKey(existing.title) == merchantKey &&
            _day(existing.date).difference(_day(date)).inDays.abs() <= 5 &&
            existing.amount / item.amount >= 1 / 1.6 &&
            existing.amount / item.amount <= 1.6,
      )) {
        continue;
      }
      final event = UpcomingPaymentEvent(
        id: 'legacy-${item.id}',
        sourceId: item.id,
        origin: UpcomingEventOrigin.inferredRecurring,
        title: item.title,
        amount: item.amount,
        currency: item.currency,
        date: date,
        frequency: frequency,
        isEstimate: true,
      );
      if (item.source == UpcomingExpenseSource.detectedRecurring) {
        tentativeEvents.add(event);
      } else if (!_day(date).isBefore(today)) {
        upcoming.add(event);
        legacyDetectedCount++;
        if (frequency != null) {
          addRegular(item.currency, item.amount, frequency);
        }
      }
    }

    // This is a view of the existing debt schedule, never a copied obligation.
    for (final payment in debtAnalytics.getNextPayments(
      debts.where(
        (item) =>
            item.userId == userId && item.isOpen && item.currentBalance > 0,
      ),
      asOf: today,
      days: 3650,
    )) {
      upcoming.add(
        UpcomingPaymentEvent(
          id: 'debt-${payment.debtId}',
          sourceId: payment.debtId,
          origin: UpcomingEventOrigin.debt,
          title: payment.title,
          amount: payment.amount,
          currency: payment.currency,
          date: payment.date,
          isEstimate: payment.confidence < 0.8,
        ),
      );
    }
    upcoming.sort(_compareEvents);
    overdue.sort(_compareEvents);
    return UpcomingEventsSnapshot(
      upcoming: List.unmodifiable(upcoming),
      overdue: List.unmodifiable(overdue),
      tentativeStreams: List.unmodifiable(
        ownedStreams.where((item) => item.isTentative),
      ),
      tentativeEvents: List.unmodifiable(tentativeEvents),
      monthlyRegularByCurrency: Map.unmodifiable(monthlyRegular),
      detectedStreamCount: ownedStreams.length + legacyDetectedCount,
    );
  }

  bool _hasManualOverride(
    List<UpcomingExpense> manual,
    String merchantKey,
    String currency,
    DateTime date,
    int amount,
    DateTime today,
  ) => manual.any((item) {
    if (item.currency != currency ||
        enrichment.normalizedMerchantKey(item.title) != merchantKey) {
      return false;
    }
    final manualDate = item.isRecurring
        ? nextOccurrenceOnOrAfter(
            item.plannedDate,
            frequencyForRule(item.recurrenceRule),
            today,
          )
        : item.plannedDate;
    final delta = _day(manualDate).difference(_day(date)).inDays.abs();
    final ratio = item.amount / amount;
    return delta <= 5 && ratio >= 1 / 1.6 && ratio <= 1.6;
  });
}

RecurrenceFrequency frequencyForRule(String? rule) => switch (rule) {
  'weekly' => RecurrenceFrequency.weekly,
  'biweekly' => RecurrenceFrequency.biweekly,
  'bimonthly' => RecurrenceFrequency.bimonthly,
  'quarterly' => RecurrenceFrequency.quarterly,
  'halfYearly' => RecurrenceFrequency.halfYearly,
  'yearly' => RecurrenceFrequency.yearly,
  _ => RecurrenceFrequency.monthly, // legacy isRecurring records
};

int _compareEvents(UpcomingPaymentEvent a, UpcomingPaymentEvent b) {
  final date = _day(a.date).compareTo(_day(b.date));
  return date != 0 ? date : a.id.compareTo(b.id);
}

DateTime _day(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

int _monthlyEquivalent(int amount, RecurrenceFrequency frequency) =>
    switch (frequency) {
      RecurrenceFrequency.weekly => (amount * 52 / 12).round(),
      RecurrenceFrequency.biweekly => (amount * 26 / 12).round(),
      RecurrenceFrequency.monthly => amount,
      RecurrenceFrequency.bimonthly => (amount / 2).round(),
      RecurrenceFrequency.quarterly => (amount / 3).round(),
      RecurrenceFrequency.halfYearly => (amount / 6).round(),
      RecurrenceFrequency.yearly => (amount / 12).round(),
      RecurrenceFrequency.irregular => math.max(0, amount),
    };
