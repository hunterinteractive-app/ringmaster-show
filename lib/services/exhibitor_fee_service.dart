import 'package:ringmaster_show/services/ringmaster_backend.dart';

class ExhibitorFee {
  const ExhibitorFee({
    required this.exhibitorId,
    required this.label,
    required this.amountCents,
  });

  final String exhibitorId;
  final String label;
  final int amountCents;

  static Future<List<ExhibitorFee>> forCart(String cartId) async {
    final result = await ringMasterClient.rpc(
      'get_cart_exhibitor_fees',
      params: {'p_cart_id': cartId},
    );
    return (result as List)
        .map(
          (row) => ExhibitorFee(
            exhibitorId: row['exhibitor_id'].toString(),
            label: row['label'].toString(),
            amountCents: (row['amount_cents'] as num).toInt(),
          ),
        )
        .toList();
  }
}
