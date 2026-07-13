import 'package:flutter/material.dart';

class SquareCardPlatform {
  SquareCardPlatform._();
  static final instance = SquareCardPlatform._();
  bool get isSupported => false;
  void prepare(String mountElementId) {}
  Widget buildCardView() => const SizedBox.shrink();
  Future<void> initialize({
    required String applicationId,
    required String locationId,
    required String environment,
  }) async {
    throw UnsupportedError(
      'Square card payments are currently available on web only.',
    );
  }

  Future<String> tokenize() async {
    throw UnsupportedError(
      'Square card payments are currently available on web only.',
    );
  }

  Future<void> destroy() async {}
}
