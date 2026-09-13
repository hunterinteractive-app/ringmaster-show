import '../reporting_core/network/transient_retry.dart';

/// Sending another OTP rotates the code and can trigger the resend limit.
/// An uncertain response should allow code entry and an explicit later resend.
Future<bool> sendEmailCodeOnce(Future<void> Function() send) async {
  try {
    await send();
    return true;
  } catch (error) {
    if (isTransientServiceError(error)) return false;
    rethrow;
  }
}
