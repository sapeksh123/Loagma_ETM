import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'calculator_dialog.dart';

OverlayEntry? _calculatorOverlayEntry;

void hideCalculatorOverlay() {
  _calculatorOverlayEntry?.remove();
  _calculatorOverlayEntry = null;
}

void showCalculatorOverlay(BuildContext context) {
  if (_calculatorOverlayEntry != null) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  if (overlay == null) return;

  _calculatorOverlayEntry = OverlayEntry(
    builder: (overlayContext) {
      final media = MediaQuery.of(overlayContext);
      final topOffset = media.padding.top + kToolbarHeight + 8;
      final popupWidth = math.min(420.0, media.size.width - 20);

      return Positioned(
        top: topOffset,
        right: 10,
        child: SizedBox(
          width: popupWidth,
          child: CalculatorDialog(
            asDialog: false,
            onClose: hideCalculatorOverlay,
          ),
        ),
      );
    },
  );

  overlay.insert(_calculatorOverlayEntry!);
}

Widget buildCalculatorAppBarAction(BuildContext context) {
  return IconButton(
    icon: const Icon(Icons.calculate_outlined),
    tooltip: 'Calculator',
    onPressed: () {
      if (_calculatorOverlayEntry != null) {
        hideCalculatorOverlay();
      } else {
        showCalculatorOverlay(context);
      }
    },
  );
}
