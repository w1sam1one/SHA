import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../chat/chat_controller.dart';
import '../chat/message_store.dart';
import '../chat/messaging_service.dart';
import '../contacts/contacts_store.dart';
import 'identity_controller.dart';

/// Shown when the identity cannot be opened because the key protecting it is
/// gone or unreadable. Retrying cannot fix that, so the user may also delete
/// everything and start over with a new identity.
class IdentityRecoveryScreen extends ConsumerStatefulWidget {
  const IdentityRecoveryScreen({super.key});

  @override
  ConsumerState<IdentityRecoveryScreen> createState() =>
      _IdentityRecoveryScreenState();
}

class _IdentityRecoveryScreenState
    extends ConsumerState<IdentityRecoveryScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _startOver() async {
    final confirmed = await _confirm(context);
    if (confirmed != true || !mounted) return;
    // Captured now: once the providers below are invalidated this screen is
    // either replaced (onboarding) or rebuilt as a new screen for a new
    // error, so its state must not be touched afterwards.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await container.read(cryptoServiceProvider).resetIdentity();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
      return;
    }
    container
      ..invalidate(chatProvider)
      ..invalidate(messagingServiceProvider)
      ..invalidate(messageStoreProvider)
      ..invalidate(contactsProvider)
      ..invalidate(keyProtectionProvider)
      ..invalidate(identityProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.gpp_bad_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Din identitet kan inte öppnas',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nyckeln som skyddar din identitet i telefonen finns inte '
                'längre eller kan inte läsas, och den går inte att återskapa. '
                'Du kan försöka igen, eller skapa en ny identitet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: ShaColors.textSecondary,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => ref.invalidate(identityProvider),
                child: const Text('Försök igen'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: ShaColors.danger,
                  side: const BorderSide(color: ShaColors.danger),
                ),
                onPressed: _busy ? null : _startOver,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Raderar och skapar ny identitet',
                        ),
                      )
                    : const Text('Skapa ny identitet…'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks the user to confirm the irreversible reset. Returns true only after
/// the checkbox is ticked and "Radera och skapa ny" is pressed.
Future<bool?> _confirm(BuildContext context) {
  var understood = false;
  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        scrollable: true,
        title: const Text('Radera och skapa ny identitet?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Din nuvarande identitet och dina kontakter raderas från den här '
              'telefonen. Alla du har träffat måste träffa dig igen och skanna '
              'din nya QR-kod. Det går inte att ångra.',
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: understood,
              onChanged: (value) => setState(() => understood = value ?? false),
              title: const Text(
                'Jag förstår att mina kontakter måste träffa mig igen',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              backgroundColor: ShaColors.danger,
              foregroundColor: ShaColors.dangerContainer,
            ),
            onPressed: understood ? () => Navigator.pop(context, true) : null,
            child: const Text('Radera och skapa ny'),
          ),
        ],
      ),
    ),
  );
}
