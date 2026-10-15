import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../crypto/crypto.dart';

const _palette = [
  (Color(0xFF2B3F55), Color(0xFFD6E4F2)),
  (Color(0xFF3A3352), Color(0xFFE2DBF7)),
  (Color(0xFF234441), Color(0xFFC9EDE6)),
  (Color(0xFF4A2F3A), Color(0xFFF3D9E2)),
  (Color(0xFF33402A), Color(0xFFDCE9CF)),
  (Color(0xFF4A3A2A), Color(0xFFF0DFCB)),
  (Color(0xFF2E3A40), Color(0xFFD5E0E6)),
];

/// Initials avatar with a colour picked from the contact's identity hash and
/// an optional "verified" badge.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.name,
    required this.hash,
    this.size = 44,
    this.verified = false,
  });

  final String name;
  final IdentityHash hash;
  final double size;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _palette[hash.bytes[0] % _palette.length];
    final badge = size * 0.44;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: bg,
            child: Text(
              initials(name),
              style: TextStyle(
                color: fg,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (verified)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: badge,
                height: badge,
                decoration: BoxDecoration(
                  color: ShaColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: ShaColors.background, width: 3),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: badge * 0.6,
                  color: ShaColors.onSuccess,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final letters = parts.take(2).map((p) => p.characters.first.toUpperCase());
    return letters.join();
  }
}
