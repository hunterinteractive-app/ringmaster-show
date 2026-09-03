import 'dart:convert';

String friendlyDeliveryFailureMessage(String rawMessage) {
  final raw = rawMessage.trim();
  if (raw.isEmpty) return 'The email could not be delivered.';

  String diagnostic = '';
  String providerMessage = '';
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final bounce = decoded['bounce'];
      if (bounce is Map) {
        final diagnosticCode = bounce['diagnosticCode'];
        if (diagnosticCode is List) {
          diagnostic = diagnosticCode
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .join(' ');
        } else {
          diagnostic = diagnosticCode?.toString().trim() ?? '';
        }
        providerMessage = bounce['message']?.toString().trim() ?? '';
      }
      providerMessage = providerMessage.isNotEmpty
          ? providerMessage
          : (decoded['message'] ?? decoded['error'] ?? '').toString().trim();
    }
  } catch (_) {
    diagnostic = raw;
  }

  final detail = diagnostic.isNotEmpty ? diagnostic : providerMessage;
  final normalized = detail.toLowerCase();
  if (normalized.contains('5.1.1') ||
      normalized.contains('does not exist') ||
      normalized.contains('no such user')) {
    return 'The recipient email account does not exist. Correct the address, then retry.';
  }
  if (normalized.contains('relay access denied')) {
    return 'The recipient mail server rejected this address (relay access denied). Correct the address, then retry.';
  }
  if (normalized.contains('mailbox full') ||
      normalized.contains('quota exceeded')) {
    return 'The recipient mailbox is full. Retry after the recipient has made space.';
  }
  if (normalized.contains('suppressed')) {
    return 'The email provider suppressed this address. Verify or correct it before retrying.';
  }
  if (normalized.contains('complaint')) {
    return 'The recipient previously marked this sender as unwanted. Do not retry until they ask to receive these reports.';
  }

  if (detail.isNotEmpty && detail.length <= 240) return detail;
  return 'The recipient mail server rejected this message. Verify the address, then retry.';
}
