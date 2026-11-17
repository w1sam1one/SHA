import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';

import '../chat/chats_screen.dart';
import '../contacts/contacts_screen.dart';
import '../qr/my_qr_screen.dart';
import '../settings/settings_screen.dart';
import '../transport/transport_lifecycle.dart';

/// Bottom navigation: Chattar · Kontakter · Min QR · Inställningar. The
/// transport runs only while this is in front ([TransportLifecycle]).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 1;

  /// Counts the times "Min QR" was chosen: each time is a new screen, and so
  /// a new one-time key (0004 §1). The tab is not kept alive in the stack.
  int _qrShown = 0;

  @override
  Widget build(BuildContext context) {
    final protection = ref.watch(keyProtectionProvider).value;
    final warning = protection == null
        ? null
        : !protection.deviceSecure
        ? 'Telefonen har inget skärmlås. Utan skärmlås kan den som har '
              'telefonen i handen läsa dina meddelanden. Ställ in PIN-kod '
              'eller lösenord.'
        : !protection.isHardwareBacked
        ? 'Telefonen saknar säkerhetshårdvara för nycklar. Din nyckel '
              'skyddas bara av mjukvara.'
        : null;
    return TransportLifecycle(child: _scaffold(warning));
  }

  Widget _scaffold(String? warning) {
    return Scaffold(
      body: Column(
        children: [
          if (warning != null)
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                color: ShaColors.warningContainer,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: ShaColors.warning,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        warning,
                        style: const TextStyle(
                          color: ShaColors.warning,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: warning != null,
              child: IndexedStack(
                index: _index,
                children: [
                  const ChatsScreen(),
                  const ContactsScreen(),
                  if (_index == 2)
                    MyQrScreen(key: ValueKey(_qrShown))
                  else
                    const SizedBox.shrink(),
                  const SettingsScreen(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          if (i == 2 && _index != 2) _qrShown++;
          _index = i;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: 'Chattar',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            label: 'Kontakter',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_2_rounded),
            label: 'Min QR',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Inställningar',
          ),
        ],
      ),
    );
  }
}
