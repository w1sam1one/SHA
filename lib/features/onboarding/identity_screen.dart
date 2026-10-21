import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../crypto/crypto.dart';
import '../../ui/hash_format.dart';
import '../../ui/identicon.dart';
import '../../ui/technical_info_sheet.dart';
import 'identity_controller.dart';

/// Shown once, right after the identity has been generated.
class IdentityScreen extends ConsumerWidget {
  const IdentityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(ownIdentityProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 12),
                  const _Brand(),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _ring(176, const Color(0xFF1B2327)),
                        _ring(136, const Color(0xFF253035)),
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: ShaColors.primaryContainer,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          alignment: Alignment.center,
                          child: Identicon(hash: identity.hash),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Din identitet är skapad',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'SHA har skapat en unik nyckel åt dig, direkt i telefonen. '
                    'Den hemliga delen lämnar aldrig enheten – det är bara du '
                    'som äger den.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 22 / 15,
                      color: ShaColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _HashCard(
                    lines: hashLines(identity.hash),
                    hex: identity.hash.hex,
                  ),
                  const SizedBox(height: 22),
                  _Point(
                    icon: Icons.memory_rounded,
                    text: switch (ref.watch(keyProtectionProvider)) {
                      AsyncData(:final value) => describeProtection(value),
                      _ => 'Kontrollerar telefonens säkra lagring …',
                    },
                  ),
                  const _Point(
                    icon: Icons.phonelink_erase_rounded,
                    text: 'Inget telefonnummer eller e-post behövs',
                  ),
                  const _Point(
                    icon: Icons.people_alt_outlined,
                    text: 'Kontakter läggs bara till när ni ses på riktigt',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => showTechnicalInfoSheet(context),
                      child: const Text('Teknisk information'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: () => ref
                        .read(identityProvider.notifier)
                        .completeOnboarding(),
                    child: const Text('Fortsätt'),
                  ),
                  TextButton(
                    onPressed: () => _explainHash(context),
                    child: const Text('Vad är min identitet?'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _ring(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color),
    ),
  );

  void _explainHash(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: ShaColors.navBar,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Text(
          'Din identitet är ett unikt fingeravtryck av din nyckel. Det är '
          'inte hemligt – det är din adress i SHA och det som din QR-kod '
          'visar. När ni ses jämför ni koderna, så att ni vet att nyckeln '
          'tillhör rätt person.',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified_user_outlined, color: ShaColors.primary, size: 22),
        SizedBox(width: 8),
        Text(
          'SHA',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.7,
          ),
        ),
      ],
    );
  }
}

class _HashCard extends StatelessWidget {
  const _HashCard({required this.lines, required this.hex});

  final List<String> lines;
  final String hex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 16),
      decoration: BoxDecoration(
        color: ShaColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'DIN IDENTITET',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: ShaColors.textSecondary,
                  ),
                ),
              ),
              if (kDebugMode)
                IconButton(
                  tooltip: 'Kopiera identitetshash',
                  color: ShaColors.textSecondary,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: hex));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Identitetshash kopierad')),
                    );
                  },
                ),
            ],
          ),
          for (final line in lines)
            Text(
              line,
              style: const TextStyle(
                fontFamily: ShaFonts.mono,
                fontSize: 18,
                height: 28 / 18,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.9,
                color: Color(0xFFEEF0F2),
              ),
            ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: ShaColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: ShaColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: Color(0xFFD5DADD)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest description of where the identity key is protected.
String describeProtection(KeyProtection p) {
  final where = switch (p.level) {
    KeyProtectionLevel.strongBox =>
      'Nyckeln skyddas av ett separat säkerhetschip',
    KeyProtectionLevel.trustedEnvironment =>
      'Nyckeln skyddas i telefonens isolerade säkerhetsmiljö',
    KeyProtectionLevel.secureHardware =>
      'Nyckeln skyddas i telefonens säkerhetshårdvara',
    KeyProtectionLevel.software || KeyProtectionLevel.unknown =>
      'Varning: telefonen saknar säkerhetshårdvara för nyckeln',
  };
  return p.deviceSecure ? where : '$where – men skärmlås saknas';
}
