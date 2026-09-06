const closeoutReportStatusTimeoutMessage =
    'The report status check took too long. If generation is already running, '
    'it will continue on the server. Select Retry to check progress again.';

bool isCloseoutStatusStatementTimeout(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('statement timeout') ||
      message.contains('code: 57014') ||
      message.contains('code=57014') ||
      message.contains('"code":"57014"');
}

String closeoutReportStatusErrorMessage(Object error) =>
    isCloseoutStatusStatementTimeout(error)
    ? closeoutReportStatusTimeoutMessage
    : error.toString();
