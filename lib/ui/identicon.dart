import 'package:flutter/material.dart';

import '../crypto/crypto.dart';

/// 5×5 mirrored pattern drawn from the identity hash, so two identities are
/// easy to tell apart at a glance.
class Identicon extends StatelessWidget {
  const Identicon({super.key, required this.hash, this.size = 54, this.color});

  final IdentityHash hash;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cell = size / 5;
    final fill = color ?? Theme.of(context).colorScheme.onPrimaryContainer;
    bool on(int row, int col) {
      final c = col < 3 ? col : 4 - col;
      final bit = row * 3 + c;
      return (hash.bytes[bit ~/ 8] >> (bit % 8)) & 1 == 1;
    }

    return Semantics(
      label: 'Bild som är unik för identiteten',
      child: SizedBox.square(
        dimension: size,
        child: Column(
          children: [
            for (var row = 0; row < 5; row++)
              Row(
                children: [
                  for (var col = 0; col < 5; col++)
                    Padding(
                      padding: EdgeInsets.all(cell * 0.09),
                      child: Container(
                        width: cell * 0.82,
                        height: cell * 0.82,
                        decoration: BoxDecoration(
                          color: on(row, col) ? fill : Colors.transparent,
                          borderRadius: BorderRadius.circular(cell * 0.2),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
