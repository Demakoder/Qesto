import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class BoundedHttpBodyException implements Exception {
  const BoundedHttpBodyException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<String> readBoundedHttpBody(
  http.StreamedResponse response, {
  required int maximumBytes,
  required Duration timeout,
}) {
  if (maximumBytes <= 0 ||
      (response.contentLength != null &&
          response.contentLength! > maximumBytes)) {
    throw const BoundedHttpBodyException('HTTP response is too large');
  }

  final completer = Completer<String>();
  final body = BytesBuilder(copy: false);
  var total = 0;
  StreamSubscription<List<int>>? subscription;
  late final Timer timer;

  void fail(Object error, [StackTrace? stackTrace]) {
    if (completer.isCompleted) return;
    timer.cancel();
    subscription?.cancel();
    completer.completeError(error, stackTrace);
  }

  timer = Timer(
    timeout,
    () => fail(TimeoutException('HTTP response timed out', timeout)),
  );
  subscription = response.stream.listen(
    (chunk) {
      total += chunk.length;
      if (total > maximumBytes) {
        fail(const BoundedHttpBodyException('HTTP response is too large'));
        return;
      }
      body.add(chunk);
    },
    onError: (Object error, StackTrace stackTrace) => fail(error, stackTrace),
    onDone: () {
      if (completer.isCompleted) return;
      timer.cancel();
      try {
        completer.complete(utf8.decode(body.takeBytes()));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    },
    cancelOnError: true,
  );
  if (completer.isCompleted) subscription.cancel();
  return completer.future;
}
