import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show Uint8List;
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
import 'my_qr_screen.dart';

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
      final ScannedCode scanned;
      try {
        scanned = ContactCode.parse(raw);
      } on ContactCodeException catch (e) {
        _showError(e.message);
        return;
      }
      final Uint8List ownOlmKey;
      final Contact? existing;
      try {
        ownOlmKey = await crypto.olm.ensureAccount();
        if (_sameKey(scanned.bundle.identityKey, ownOlmKey) ||
            scanned.addressingKey == ref.read(ownIdentityProvider)) {
          _showError('Det där är din egen kod.');
          return;
        }
        existing = ref
            .read(contactsProvider.notifier)
            .byId(_hex(await crypto.sha256(scanned.bundle.identityKey)));
        if (existing != null) {
          // A new scan starts a new session, which is sent on at once
          // (0006 (b)). The same QR display gives none (0004 §2).
          await crypto.olm.startSession(scanned.bundle);
          _showError('${existing.name} finns redan bland dina kontakter.');
          return;
        }
        // Derive once to reject invalid (e.g. low-order) addressing keys
        // before the user is asked to trust them; destroyed straight away.
        crypto.forget(await crypto.conversationKeys(scanned.addressingKey));
      } on CryptoException catch (e) {
        _showError(
          e.kind == CryptoErrorKind.invalidInput
              ? 'Koden innehåller en ogiltig nyckel.'
              : describeError(e),
        );
        return;
      }
      final code = await crypto.olm.verificationCode(
        scanned.bundle.identityKey,
      );
      if (!mounted) return;
      final accepted = await showAddContactSheet(
        context,
        peer: scanned.addressingKey,
        verificationCode: code,
      );
      if (accepted == null || !mounted) return;
      final Contact contact;
      try {
        contact = await ref
            .read(contactsProvider.notifier)
            .addScanned(
              bundle: scanned.bundle,
              addressingKey: scanned.addressingKey,
              name: accepted.name,
              metAt: accepted.verifiedAt,
            );
      } on CryptoException catch (e) {
        _showError(describeError(e));
        return;
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final screenReader = MediaQuery.accessibleNavigationOf(context);
      final navigator = Navigator.of(context)..pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${contact.name} är tillagd.'),
          duration: const Duration(seconds: 8),
          // A snackbar with an action would otherwise never time out. Keep
          // that only for screen-reader users, so they can reach the action.
          persist: screenReader,
          action: SnackBarAction(
            label: 'Visa min QR',
            onPressed: () => navigator.push(
              MaterialPageRoute<void>(builder: (_) => const MyQrScreen()),
            ),
          ),
        ),
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

bool _sameKey(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
