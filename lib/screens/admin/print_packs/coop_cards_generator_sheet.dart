// lib/screens/admin/print_packs/coop_cards_generator_sheet.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../closeout/data/loaders/coop_cards_report_loader.dart';
import '../closeout/pdf/builders/coop_cards_report_pdf.dart';
import 'print_pack_pdf_helpers.dart';

// =======================================================

class CoopCardsGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;

  const CoopCardsGeneratorSheet({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<CoopCardsGeneratorSheet> createState() =>
      _CoopCardsGeneratorSheetState();
}

class _CoopCardsGeneratorSheetState
    extends State<CoopCardsGeneratorSheet> {
  bool _building = false;
  String? _msg;
  String _buildStatus = '';
  String _scope = 'all';

  String _safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'show' : cleaned;
  }

  String? get _loaderScope => _scope == 'all' ? null : _scope;

  String get _scopeLabel {
    switch (_scope) {
      case 'open':
        return 'Open';
      case 'youth':
        return 'Youth';
      default:
        return 'All';
    }
  }

  Future<Uint8List> _buildPdfBytes() async {
    if (mounted) {
      setState(() {
        _buildStatus = 'Loading coop card data...';
      });
    }

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final loader = CoopCardsReportLoader();
    final data = await loader
        .load(
          showId: widget.showId,
          scope: _loaderScope,
        )
        .timeout(
          const Duration(seconds: 90),
          onTimeout: () => throw TimeoutException(
            'Loading coop card data took longer than 90 seconds.',
          ),
        );

    if (data.cards.isEmpty) {
      throw StateError(
        _scope == 'all'
            ? 'No assigned coop numbers with active entries were found.'
            : 'No $_scopeLabel coop cards with active entries were found.',
      );
    }

    if (mounted) {
      setState(() {
        _buildStatus =
            'Building ${data.cardCount} coop cards (${(data.cardCount / 4).ceil()} pages)...';
      });
    }

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final builder = await CoopCardsReportPdfBuilder.fromAssets();
    return builder.build(data).timeout(
          const Duration(seconds: 120),
          onTimeout: () => throw TimeoutException(
            'Building the coop card PDF took longer than 2 minutes.',
          ),
        );
  }

  Future<void> _previewPdf() async {
    if (_building) return;

    setState(() {
      _building = true;
      _msg = null;
      _buildStatus = 'Starting...';
    });

    try {
      final bytes = await _buildPdfBytes();
      if (!mounted) return;
      setState(() => _buildStatus = 'Opening print preview...');

      await Printing.layoutPdf(
        name:
            '${_safeFileName(widget.showName)}_coop_cards_${_scopeLabel.toLowerCase()}.pdf',
        onLayout: (_) async => bytes,
      );

      if (!mounted) return;
      setState(() {
        _building = false;
        _buildStatus = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _buildStatus = '';
        _msg = 'Failed to generate coop cards: $e';
      });
    }
  }

  Future<void> _savePdf() async {
    if (_building) return;

    setState(() {
      _building = true;
      _msg = null;
      _buildStatus = 'Starting...';
    });

    try {
      final bytes = await _buildPdfBytes();
      if (mounted) {
        setState(() => _buildStatus = 'Waiting for save location...');
      }
      final suggestedName =
          '${_safeFileName(widget.showName)}_coop_cards_${_scopeLabel.toLowerCase()}.pdf';

      final path = await savePdfToUserChosenLocation(
        bytes: bytes,
        suggestedName: suggestedName,
      );

      if (!mounted) return;
      setState(() {
        _building = false;
        _buildStatus = '';
        _msg = path == null
            ? 'Save cancelled.'
            : 'Coop cards saved to $path';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _buildStatus = '';
        _msg = 'Failed to generate coop cards: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Generate Coop Cards',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.showName,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'all',
                  label: Text('All'),
                ),
                ButtonSegment<String>(
                  value: 'open',
                  label: Text('Open'),
                ),
                ButtonSegment<String>(
                  value: 'youth',
                  label: Text('Youth'),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: _building
                  ? null
                  : (values) => setState(() => _scope = values.first),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Cards print four per US Letter page. Each card is 4 in. × 4.5 in. and includes a full cut border.',
              ),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 12),
              Text(
                _msg!,
                style: TextStyle(
                  color: _msg!.toLowerCase().contains('failed')
                      ? Colors.red
                      : Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _building ? null : _previewPdf,
              icon: _building
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined),
              label: Text(
                _building
                    ? (_buildStatus.isEmpty ? 'Building...' : _buildStatus)
                    : 'Preview / Print',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _building ? null : _savePdf,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Save PDF'),
            ),
          ],
        ),
      ),
    );
  }
}