import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'time_format.dart';

// The only place that decides how "verified in person" looks and reads.
// Every contact exists only because two people met and scanned each other's
// codes, so a contact is verified by definition: there is no unverified or
// changed-key state to show. Green and this icon mean exactly that, nothing
// else (enforced by test/security/trust_display_test.dart).

const String verifiedInPersonLabel = 'Verifierad i person';

const Color _verifiedColor = ShaColors.success;
const IconData _verifiedIcon = Icons.verified_rounded;

/// `Möttes 12 okt`
String metOnLine(DateTime verifiedAt) => 'Möttes ${formatDay(verifiedAt)}';

/// Section header above the contact list.
String verifiedSectionTitle(int count) => 'Verifierade i person · $count';

String _spokenLabel(DateTime verifiedAt) =>
    '$verifiedInPersonLabel, möttes ${formatDay(verifiedAt)}';

/// Icon + "Verifierad i person · Möttes 12 okt".
class VerifiedInPerson extends StatelessWidget {
  const VerifiedInPerson({
    super.key,
    required this.verifiedAt,
    this.fontSize = 13,
  });

  final DateTime verifiedAt;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _spokenLabel(verifiedAt),
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(_verifiedIcon, size: fontSize + 2, color: _verifiedColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: verifiedInPersonLabel,
                    style: TextStyle(
                      color: _verifiedColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' · ${metOnLine(verifiedAt)}'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                color: ShaColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small badge drawn on every contact's avatar.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: verifiedInPersonLabel,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: ShaColors.background,
          shape: BoxShape.circle,
        ),
        child: Icon(_verifiedIcon, size: size * 0.85, color: _verifiedColor),
      ),
    );
  }
}
