import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/stripe_connect_service.dart';

void main() {
  group('StripeConnectService.connectedAccountId', () {
    test('reads the provider-neutral account identifier', () {
      expect(
        StripeConnectService.connectedAccountId({
          'show_payment_account': {
            'provider_account_id': ' acct_provider ',
            'stripe_account_id': 'acct_stripe',
          },
        }),
        'acct_provider',
      );
    });

    test('falls back to the legacy Stripe account identifier', () {
      expect(
        StripeConnectService.connectedAccountId({
          'show_payment_account': {
            'provider_account_id': '',
            'stripe_account_id': ' acct_legacy ',
          },
        }),
        'acct_legacy',
      );
    });

    test('returns empty when the response has no connected account', () {
      expect(StripeConnectService.connectedAccountId(null), isEmpty);
      expect(
        StripeConnectService.connectedAccountId({'show_payment_account': null}),
        isEmpty,
      );
    });
  });
}
