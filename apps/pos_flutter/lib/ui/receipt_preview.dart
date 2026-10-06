import 'dart:io';

import 'package:flutter/material.dart';

import '../printing/receipt.dart';

/// On-screen rendering of the same blocks sent to the printer.
class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview(this.receipt, {super.key});
  final Receipt receipt;

  static TextAlign _text(ReceiptAlign a) => switch (a) {
    ReceiptAlign.left => TextAlign.left,
    ReceiptAlign.center => TextAlign.center,
    ReceiptAlign.right => TextAlign.right,
  };

  static TextStyle _style(ReceiptSize size, bool bold) => TextStyle(
    fontSize: size.points / 2,
    height: 1.3,
    color: Colors.black,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
  );

  @override
  Widget build(BuildContext context) => Container(
    width: 300,
    padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFDDDDDD)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in receipt.blocks)
          switch (block) {
            ReceiptLogo(:final source, :final file) => Center(
              child: file
                  ? Image.file(
                      File(source),
                      width: 110,
                      semanticLabel: 'Logo de la boutique',
                      color: Colors.grey,
                      colorBlendMode: BlendMode.saturation,
                    )
                  : Image.asset(
                      source,
                      width: 110,
                      semanticLabel: 'Logo de la boutique',
                      color: Colors.grey,
                      colorBlendMode: BlendMode.saturation,
                    ),
            ),
            ReceiptText(:final text, :final align, :final bold, :final size) =>
              Text(text, textAlign: _text(align), style: _style(size, bold)),
            ReceiptRow(
              :final cells,
              :final weights,
              :final aligns,
              :final bold,
              :final size,
            ) =>
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < cells.length; i++)
                    Expanded(
                      flex: weights[i],
                      child: Text(
                        cells[i],
                        textAlign: _text(aligns[i]),
                        style: _style(size, bold),
                      ),
                    ),
                ],
              ),
            ReceiptFeed(:final lines) => SizedBox(height: 8.0 * lines),
          },
      ],
    ),
  );
}
