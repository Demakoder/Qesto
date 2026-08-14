class OpenBankingException implements Exception {
  const OpenBankingException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'OpenBankingException($code): $message';
}

class OpenBankingNotEnabledError extends OpenBankingException {
  const OpenBankingNotEnabledError([
    String message =
        'Live Open Banking connectivity is intentionally disabled.',
  ]) : super('open_banking_not_enabled', message);
}

class OpenBankingValidationError extends OpenBankingException {
  const OpenBankingValidationError(super.code, super.message);
}

class OpenBankingNotImplementedError extends OpenBankingException {
  const OpenBankingNotImplementedError(String feature)
    : super(
        'open_banking_not_implemented',
        '$feature is a contract-only foundation and is not implemented.',
      );
}

class InvalidTokenBindingError extends OpenBankingException {
  const InvalidTokenBindingError()
    : httpStatus = 401,
      super(
        'invalid_token',
        'The access token is not bound to the presented mTLS certificate.',
      );

  final int httpStatus;
}
