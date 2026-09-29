import '../domain/bank_screenshot_models.dart';
import 'bank_screenshot_parser.dart';
import 'bank_screenshot_identity.dart';
import 'generic_bank_screenshot_parser.dart';
import 'sber_bank_screenshot_parser.dart';

class BankScreenshotImportService {
  const BankScreenshotImportService({
    this.sberParser = const SberBankScreenshotParser(),
    this.genericParser = const GenericBankScreenshotParser(),
  });

  final SberBankScreenshotParser sberParser;
  final GenericBankScreenshotParser genericParser;

  BankScreenshotParseResult parseAll(
    Iterable<ExtractedBankScreenshot> documents,
  ) {
    final candidates = <String, BankScreenshotCandidate>{};
    final warnings = <String>[];
    final seenImages = <String>{};
    final seenFacts = <String, List<BankScreenshotCandidate>>{};
    for (final document in documents) {
      if (document.imageHash.trim().isEmpty) {
        warnings.add(
          'Скриншот без отпечатка изображения не принят: выберите файл повторно.',
        );
        continue;
      }
      if (!seenImages.add(document.imageHash)) continue;
      final parsers = <BankScreenshotParser>[sberParser, genericParser]
        ..sort(
          (left, right) => right
              .confidenceFor(document)
              .compareTo(left.confidenceFor(document)),
        );
      final selected = sberParser.confidenceFor(document) >= 0.5
          ? sberParser
          : parsers.first;
      final result = selected.parse(document);
      warnings.addAll(result.warnings);
      for (final parsed in result.candidates) {
        var candidate = screenshotObservation(parsed);
        final key = screenshotFinancialKey(candidate);
        final previous = seenFacts[key] ?? const <BankScreenshotCandidate>[];
        final overlapping = previous.any(
          (row) =>
              row.imageHash != candidate.imageHash &&
              (row.accountHint == null ||
                  candidate.accountHint == null ||
                  row.accountHint == candidate.accountHint) &&
              (row.balanceAfterMinor == null ||
                  candidate.balanceAfterMinor == null ||
                  row.balanceAfterMinor == candidate.balanceAfterMinor),
        );
        if (overlapping) {
          candidate = candidate.copyWith(
            selected: false,
            possibleDuplicateReason:
                'Похожа на строку другого скриншота. '
                'Выберите её только если это отдельная операция.',
          );
          warnings.add(
            'Похожие строки разных скриншотов сохранены для проверки, '
            'но не выбраны автоматически.',
          );
        }
        candidates[candidate.id] = candidate;
        (seenFacts[key] ??= []).add(candidate);
      }
    }
    return BankScreenshotParseResult(
      candidates: candidates.values.toList(growable: false),
      warnings: warnings.toSet().toList(growable: false),
    );
  }
}
