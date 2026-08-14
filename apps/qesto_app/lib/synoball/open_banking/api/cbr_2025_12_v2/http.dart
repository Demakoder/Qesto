import '../../core/errors.dart';

class FapiInteractionId {
  factory FapiInteractionId(String value) {
    if (!_uuid.hasMatch(value)) {
      throw const OpenBankingValidationError(
        'invalid_interaction_id',
        'x-fapi-interaction-id must be an RFC 4122 UUID.',
      );
    }
    return FapiInteractionId._(value.toLowerCase());
  }

  const FapiInteractionId._(this.value);

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  final String value;

  @override
  String toString() => value;
}

class CbrHttpStatus {
  const CbrHttpStatus(this.code);

  static const ok = CbrHttpStatus(200);
  static const created = CbrHttpStatus(201);
  static const noContent = CbrHttpStatus(204);
  static const badRequest = CbrHttpStatus(400);
  static const unauthorized = CbrHttpStatus(401);
  static const forbidden = CbrHttpStatus(403);
  static const notFound = CbrHttpStatus(404);
  static const methodNotAllowed = CbrHttpStatus(405);
  static const notAcceptable = CbrHttpStatus(406);
  static const unsupportedMediaType = CbrHttpStatus(415);
  static const tooManyRequests = CbrHttpStatus(429);
  static const internalServerError = CbrHttpStatus(500);
  static const notImplemented = CbrHttpStatus(501);
  static const serviceUnavailable = CbrHttpStatus(503);

  final int code;

  bool get isSuccess => code >= 200 && code < 300;
  bool get isRetryHintRelevant => code == 429 || code == 503;
}

class CbrHeaders {
  CbrHeaders([Map<String, String> values = const {}])
    : _values = {
        for (final entry in values.entries)
          entry.key.toLowerCase(): entry.value,
      };

  static const interactionIdName = 'x-fapi-interaction-id';
  static const authDateName = 'x-fapi-auth-date';
  static const customerIpAddressName = 'x-fapi-customer-ip-address';
  static const customerUserAgentName = 'x-customer-user-agent';
  static const detachedJwsName = 'x-jws-signature';

  final Map<String, String> _values;

  String? operator [](String name) => _values[name.toLowerCase()];

  void set(String name, String value) {
    _values[name.toLowerCase()] = value;
  }

  FapiInteractionId? get interactionId {
    final raw = this[interactionIdName];
    return raw == null ? null : FapiInteractionId(raw);
  }

  DateTime? get authenticationDate {
    final raw = this[authDateName];
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  String? get customerIpAddress => this[customerIpAddressName];
  String? get customerUserAgent => this[customerUserAgentName];
  String? get detachedJws => this[detachedJwsName];

  Map<String, String> toMap() => Map.unmodifiable(_values);
}

class CbrResourcePath {
  const CbrResourcePath({
    required this.participantPathPrefix,
    required this.version,
    required this.resourceGroup,
    required this.resource,
    this.resourceId,
    this.subResource,
  });

  static const individualAccountsResourceGroup = 'acis-pe';

  final String participantPathPrefix;
  final String version;
  final String resourceGroup;
  final String resource;
  final String? resourceId;
  final String? subResource;

  String build() {
    final prefix = participantPathPrefix
        .split('/')
        .where((segment) => segment.isNotEmpty);
    final segments = <String>[
      ...prefix,
      'open-banking',
      version,
      resourceGroup,
      resource,
      if (resourceId != null && resourceId!.isNotEmpty) resourceId!,
      if (subResource != null && subResource!.isNotEmpty) subResource!,
    ];
    return '/${segments.map(Uri.encodeComponent).join('/')}';
  }

  Uri resolveAgainst(Uri baseUri) => baseUri.resolve(build());
}

class RetryPolicyHint {
  const RetryPolicyHint({this.delay, this.at});

  final Duration? delay;
  final DateTime? at;

  static RetryPolicyHint? fromHeaders(int status, CbrHeaders headers) {
    if (status != 429 && status != 503) return null;
    final raw = headers['retry-after'];
    if (raw == null) return const RetryPolicyHint();
    final seconds = int.tryParse(raw);
    if (seconds != null && seconds >= 0) {
      return RetryPolicyHint(delay: Duration(seconds: seconds));
    }
    final instant = DateTime.tryParse(raw)?.toUtc() ?? _tryParseHttpDate(raw);
    return RetryPolicyHint(at: instant);
  }
}

class CbrLinks {
  const CbrLinks({
    required this.self,
    this.first,
    this.previous,
    this.next,
    this.last,
  });

  final Uri self;
  final Uri? first;
  final Uri? previous;
  final Uri? next;
  final Uri? last;

  factory CbrLinks.fromJson(Map<String, Object?> json) => CbrLinks(
    self: Uri.parse(json['self'] as String),
    first: _optionalUri(json['first']),
    previous: _optionalUri(json['prev']),
    next: _optionalUri(json['next']),
    last: _optionalUri(json['last']),
  );
}

class CbrMeta {
  const CbrMeta({this.totalPages, this.extensions = const {}});

  final int? totalPages;
  final Map<String, Object?> extensions;

  factory CbrMeta.fromJson(Map<String, Object?> json) => CbrMeta(
    totalPages: (json['totalPages'] as num?)?.toInt(),
    extensions: Map.fromEntries(
      json.entries.where((entry) => entry.key != 'totalPages'),
    ),
  );
}

class CbrApiResponse<T> {
  const CbrApiResponse({required this.data, this.links, this.meta});

  final T data;
  final CbrLinks? links;
  final CbrMeta? meta;

  factory CbrApiResponse.fromJson(
    Map<String, Object?> json,
    T Function(Object? raw) decodeData,
  ) => CbrApiResponse(
    data: decodeData(json['Data']),
    links: json['Links'] is Map
        ? CbrLinks.fromJson(Map<String, Object?>.from(json['Links']! as Map))
        : null,
    meta: json['Meta'] is Map
        ? CbrMeta.fromJson(Map<String, Object?>.from(json['Meta']! as Map))
        : null,
  );
}

class CbrErrorCode {
  const CbrErrorCode(this.value);

  final String value;

  bool get isKnown => CbrKnownErrorCodes.all.contains(value);

  @override
  String toString() => value;
}

abstract final class CbrKnownErrorCodes {
  static const all = <String>{
    'RU.CBR.Field.Expected',
    'RU.CBR.Field.Invalid',
    'RU.CBR.Field.InvalidDate',
    'RU.CBR.Field.Missing',
    'RU.CBR.Header.Invalid',
    'RU.CBR.Header.Missing',
    'RU.CBR.Resource.InvalidFormat',
    'RU.CBR.Resource.NotFound',
    'RU.CBR.Resource.NotCreated',
    'RU.CBR.Rules.AfterCutOffDateTime',
    'RU.CBR.Signature.Invalid',
    'RU.CBR.Signature.InvalidClaim',
    'RU.CBR.Signature.MissingClaim',
    'RU.CBR.Signature.Malformed',
    'RU.CBR.Signature.Missing',
    'RU.CBR.Unsupported.AccountIdentifier',
    'RU.CBR.Unsupported.LocalInstrument',
    'RU.CBR.Operation.Unprocessable',
    'RU.CBR.Authenticate.InvalidScope',
    'RU.CBR.Authenticate.InvalidConsent',
    'RU.CBR.Authenticate.SuspiciousActivityDetected',
  };
}

class CbrErrorItem {
  const CbrErrorItem({
    required this.errorCode,
    required this.message,
    this.path,
    this.url,
    this.extensions = const {},
  });

  final CbrErrorCode errorCode;
  final String message;
  final String? path;
  final Uri? url;
  final Map<String, Object?> extensions;

  factory CbrErrorItem.fromJson(Map<String, Object?> json) {
    const known = {'errorCode', 'message', 'path', 'url'};
    return CbrErrorItem(
      errorCode: CbrErrorCode(json['errorCode'] as String),
      message: json['message'] as String,
      path: json['path'] as String?,
      url: _optionalUri(json['url']),
      extensions: Map.fromEntries(
        json.entries.where((entry) => !known.contains(entry.key)),
      ),
    );
  }
}

class CbrErrorResponse {
  const CbrErrorResponse({
    required this.code,
    this.id,
    this.message,
    this.errors = const [],
    this.extensions = const {},
  });

  final CbrErrorCode code;
  final String? id;
  final String? message;
  final List<CbrErrorItem> errors;
  final Map<String, Object?> extensions;

  factory CbrErrorResponse.fromJson(Map<String, Object?> json) {
    const known = {'code', 'id', 'message', 'Errors'};
    final rawCode = json['code'];
    if (rawCode is! String || rawCode.isEmpty) {
      throw const OpenBankingValidationError(
        'invalid_cbr_error',
        'CBR error envelope requires a string code.',
      );
    }
    final rawErrors = json['Errors'];
    return CbrErrorResponse(
      code: CbrErrorCode(rawCode),
      id: json['id'] as String?,
      message: json['message'] as String?,
      errors: rawErrors is List
          ? rawErrors
                .whereType<Map>()
                .map(
                  (raw) =>
                      CbrErrorItem.fromJson(Map<String, Object?>.from(raw)),
                )
                .toList(growable: false)
          : const [],
      extensions: Map.fromEntries(
        json.entries.where((entry) => !known.contains(entry.key)),
      ),
    );
  }
}

Uri? _optionalUri(Object? value) =>
    value is String && value.isNotEmpty ? Uri.parse(value) : null;

DateTime? _tryParseHttpDate(String raw) {
  final match = RegExp(
    r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(raw);
  if (match == null) return null;
  const months = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };
  final month = months[match.group(2)];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}
