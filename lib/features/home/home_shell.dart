import 'package:flutter/material.dart';

import '../chat/chats_screen.dart';
import '../contacts/contacts_screen.dart';
import '../qr/my_qr_screen.dart';

/// Bottom navigation: Chattar · Kontakter · Min QR.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [ChatsScreen(), ContactsScreen(), MyQrScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
        ],
      ),
    );
  }
}
