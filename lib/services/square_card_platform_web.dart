// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

@JS('loadSquarePaymentsSdk')
external JSPromise<JSString> _loadSquarePaymentsSdk(JSString environment);
@JS('initializeSquareCard')
external JSPromise<JSString> _initializeSquareCard(
  JSString applicationId,
  JSString locationId,
  JSString mountElementId,
);
@JS('tokenizeSquareCard')
external JSPromise<JSString> _tokenizeSquareCard();
@JS('destroySquareCard')
external JSPromise<JSString> _destroySquareCard();

class SquareCardPlatform {
  SquareCardPlatform._();
  static final instance = SquareCardPlatform._();
  String? _viewType;
  String? _mountElementId;

  bool get isSupported => true;

  void prepare(String mountElementId) {
    if (_mountElementId == mountElementId && _viewType != null) return;
    _mountElementId = mountElementId;
    _viewType = 'ringmaster-square-card-$mountElementId';
    ui_web.platformViewRegistry.registerViewFactory(_viewType!, (int _) {
      return html.DivElement()
        ..id = mountElementId
        ..style.width = '100%'
        ..style.minHeight = '90px';
    });
  }

  Widget buildCardView() {
    final viewType = _viewType;
    return viewType == null
        ? const SizedBox.shrink()
        : SizedBox(height: 100, child: HtmlElementView(viewType: viewType));
  }

  Future<void> initialize({
    required String applicationId,
    required String locationId,
    required String environment,
  }) async {
    final mount = _mountElementId;
    if (mount == null) throw StateError('Square card form was not prepared.');
    _requireOk(await _loadSquarePaymentsSdk(environment.toJS).toDart);
    _requireOk(
      await _initializeSquareCard(
        applicationId.toJS,
        locationId.toJS,
        mount.toJS,
      ).toDart,
    );
  }

  Future<String> tokenize() async {
    final data = _decode(await _tokenizeSquareCard().toDart);
    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'Card tokenization failed.');
    }
    final sourceId = (data['source_id'] ?? '').toString().trim();
    if (sourceId.isEmpty) {
      throw Exception('Square did not return a payment token.');
    }
    return sourceId;
  }

  Future<void> destroy() async {
    _requireOk(await _destroySquareCard().toDart);
  }

  void _requireOk(JSString value) {
    final data = _decode(value);
    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'Square payment fields failed.');
    }
  }

  Map<String, dynamic> _decode(JSString value) {
    final raw = jsonDecode(value.toDart);
    return (raw as Map).map((key, value) => MapEntry(key.toString(), value));
  }
}
