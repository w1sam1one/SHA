import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../ui/hash_format.dart';
import '../onboarding/identity_controller.dart';
import 'contact_code.dart';
import 'scan_screen.dart';

/// Shows this device's identity as a QR code for someone to scan in person.
///
/// Every time the screen opens it shows a new one-time key, which is saved
/// before the code is drawn (0004 §1, §6 and §8). HomeShell makes a new
/// screen each time the tab is chosen.
class MyQrScreen extends ConsumerStatefulWidget {
  const MyQrScreen({super.key});

  @override
  ConsumerState<MyQrScreen> createState() => _MyQrScreenState();
}

class _MyQrScreenState extends ConsumerState<MyQrScreen> {
  late final Future<String> _code = _makeCode();

  Future<String> _makeCode() async {
    final olm = ref.read(cryptoServiceProvider).olm;
    await olm.ensureAccount();
    final bundle = await olm.publishBundle();
    return ContactCode.encode(bundle, ref.read(ownIdentityProvider));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _code,
    builder: (context, snapshot) => _build(
      context,
      snapshot.data,
      snapshot.hasError ? describeError(snapshot.error!) : null,
    ),
  );

  Widget _build(BuildContext context, String? code, String? error) {
    final identity = ref.watch(ownIdentityProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Min QR'),
        // Copying puts your public key on the clipboard, readable by other
        // apps; only allowed in debug builds for emulator testing.
        actions: [
          if (kDebugMode && code != null)
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
                  child: ContactQrCode(code: code, error: error),
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
                    'Koden är inte hemlig. Den innehåller bara offentliga '
                    'nycklar och kan visas för den du träffar. Dina hemliga '
                    'nycklar lämnar aldrig telefonen.',
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

/// The QR card on "Min QR": the code, or the progress or error while there is
/// none, with the logo in the middle. Its own widget, so that a test draws
/// exactly this and reads it with the scanner (0012 (C1),
/// test/features/qr_decoder_test.dart).
class ContactQrCode extends StatelessWidget {
  const ContactQrCode({super.key, required this.code, this.error});

  final String? code;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final code = this.code;
    final error = this.error;
    return Container(
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
          if (code == null)
            error == null
                ? const CircularProgressIndicator()
                : Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ShaColors.background),
                  )
          else
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
          if (code != null)
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
    );
  }
}
