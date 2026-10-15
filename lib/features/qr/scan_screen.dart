import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../crypto/crypto.dart';
import '../contacts/contacts_store.dart';
import '../onboarding/identity_controller.dart';
import 'add_contact_sheet.dart';
import 'contact_code.dart';

/// Scans another person's SHA QR code and adds them as a contact.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const ScanScreen()));

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  /// True while a scanned code is being checked or shown, so further
  /// detections are ignored.
  bool _busy = false;

  /// After a rejected or cancelled code, ignore the camera briefly so the same
  /// code still in view does not immediately pop up again.
  DateTime _ignoreCameraUntil = DateTime(0);

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null) {
        if (DateTime.now().isBefore(_ignoreCameraUntil)) return;
        _handleCode(raw);
        return;
      }
    }
  }

  Future<void> _handleCode(String raw) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final crypto = ref.read(cryptoServiceProvider);
      final PublicIdentity peer;
      try {
        peer = ContactCode.parse(raw);
      } on ContactCodeException catch (e) {
        _showError(e.message);
        return;
      }
      if (peer == ref.read(ownIdentityProvider)) {
        _showError('Det där är din egen kod.');
        return;
      }
      final existing = ref.read(contactsProvider.notifier).byId(peer.hash.hex);
      if (existing != null) {
        _showError('${existing.name} finns redan bland dina kontakter.');
        return;
      }
      // Derive once to reject invalid (e.g. low-order) keys before the user
      // is asked to trust them; the keys are destroyed straight away.
      try {
        crypto.forget(await crypto.conversationKeys(peer));
      } on CryptoException catch (e) {
        _showError(
          e.kind == CryptoErrorKind.invalidInput
              ? 'Koden innehåller en ogiltig nyckel.'
              : describeError(e),
        );
        return;
      }
      final code = await crypto.verificationCode(peer);
      if (!mounted) return;
      final contact = await showAddContactSheet(
        context,
        peer: peer,
        verificationCode: code,
      );
      if (contact == null || !mounted) return;
      ref.read(contactsProvider.notifier).add(contact);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('${contact.name} är tillagd och verifierad')),
      );
    } finally {
      _ignoreCameraUntil = DateTime.now().add(const Duration(seconds: 3));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _enterManually() async {
    assert(kDebugMode, 'Manual entry is a development aid only');
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ange kod manuellt'),
        content: TextField(
          controller: controller,
          autofocus: true,
          enableIMEPersonalizedLearning: false,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'shaid:1:…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Avbryt'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Lägg till'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw != null && raw.trim().isNotEmpty) await _handleCode(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          const _ScanFrame(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Stäng',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const Expanded(
                        child: Text(
                          'Skanna kontakt',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      ValueListenableBuilder(
                        valueListenable: _camera,
                        builder: (context, state, _) => IconButton.filledTonal(
                          tooltip: 'Ficklampa',
                          onPressed: state.isRunning
                              ? _camera.toggleTorch
                              : null,
                          icon: Icon(
                            state.torchState == TorchState.on
                                ? Icons.flashlight_off_rounded
                                : Icons.flashlight_on_rounded,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                  decoration: const BoxDecoration(
                    color: ShaColors.navBar,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _busy ? 'Kontrollerar koden …' : 'Rikta kameran mot din kontakts QR-kod i appen SHA.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.5,
                          color: ShaColors.textSecondary,
                        ),
                      ),
                      // Only in debug builds (emulators without a camera):
                      // SHA contacts are added in person, by scanning.
                      if (kDebugMode) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _busy ? null : _enterManually,
                          icon: const Icon(Icons.keyboard_rounded),
                          label: const Text('Ange kod manuellt (debug)'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: ShaColors.primary, width: 4),
            boxShadow: const [
              BoxShadow(color: Color(0x99060A0B), spreadRadius: 1000),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = error.errorCode == MobileScannerErrorCode.permissionDenied
        ? 'SHA behöver tillgång till kameran för att skanna QR-koder. '
              'Du kan ge behörighet i telefonens inställningar.'
        : 'Kameran kunde inte startas.';
    return ColoredBox(
      color: ShaColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ShaColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
