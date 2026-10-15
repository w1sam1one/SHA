import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../ui/hash_format.dart';
import '../onboarding/identity_controller.dart';
import 'contact_code.dart';
import 'scan_screen.dart';

/// Shows this device's identity as a QR code for someone to scan in person.
class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(ownIdentityProvider);
    final code = ContactCode.encode(identity);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Min QR'),
        actions: [
          IconButton(
            tooltip: 'Kopiera koden som text',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Koden kopierad')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            decoration: BoxDecoration(
              color: ShaColors.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                const Text(
                  'Låt den du möter skanna koden',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ShaColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                Semantics(
                  label: 'QR-kod med din identitet',
                  child: Container(
                    width: 262,
                    height: 262,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ShaColors.qrBackground,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        QrImageView(
                          data: code,
                          padding: EdgeInsets.zero,
                          // High error correction leaves room for the logo.
                          errorCorrectionLevel: QrErrorCorrectLevel.H,
                          backgroundColor: ShaColors.qrBackground,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: ShaColors.background,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: ShaColors.background,
                          ),
                        ),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: ShaColors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.verified_user_outlined,
                            color: ShaColors.primary,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Din identitet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  shortHash(identity.hash),
                  style: const TextStyle(
                    fontFamily: ShaFonts.mono,
                    fontSize: 13,
                    letterSpacing: 0.8,
                    color: ShaColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: ShaColors.textSecondary,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Koden innehåller bara din offentliga nyckel och dess '
                    'SHA-256-hash. Den hemliga nyckeln stannar alltid i telefonen.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 20 / 13.5,
                      color: ShaColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => ScanScreen.open(context),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Skanna en kontakts kod'),
          ),
        ],
      ),
    );
  }
}
