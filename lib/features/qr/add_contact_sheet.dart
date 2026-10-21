import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../crypto/crypto.dart';
import '../../ui/hash_format.dart';
import '../../ui/identicon.dart';
import '../contacts/contacts_store.dart';

/// Asks for a name and has the user confirm that both phones show the same
/// verification code. Returns the new contact, or null if cancelled.
Future<Contact?> showAddContactSheet(
  BuildContext context, {
  required PublicIdentity peer,
  required String verificationCode,
}) {
  return showModalBottomSheet<Contact>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ShaColors.navBar,
    builder: (_) => _AddContactSheet(peer: peer, code: verificationCode),
  );
}

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet({required this.peer, required this.code});

  final PublicIdentity peer;
  final String code;

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF234441),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Identicon(
                  hash: widget.peer.hash,
                  size: 30,
                  color: const Color(0xFFC9EDE6),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ny kontakt hittad',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      shortHash(widget.peer.hash),
                      style: const TextStyle(
                        fontFamily: ShaFonts.mono,
                        fontSize: 13,
                        letterSpacing: 0.6,
                        color: ShaColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 64,
            enableIMEPersonalizedLearning: false,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Namn på kontakten',
              border: OutlineInputBorder(),
              // The theme outline is too faint (1.8:1) on the sheet.
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: ShaColors.fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: ShaColors.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: ShaColors.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GEMENSAM KONTROLLKOD',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: ShaColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                for (final line in verificationCodeLines(widget.code))
                  Text(
                    line,
                    style: const TextStyle(
                      fontFamily: ShaFonts.mono,
                      fontSize: 26,
                      height: 36 / 26,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 3,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Kontrollera att ${name.isEmpty ? 'den andras' : _genitive(name)} '
                  'telefon visar exakt samma 20 siffror.',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: ShaColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Be ${name.isEmpty ? 'den andra' : name} också skanna din QR-kod, '
            'annars kan ni inte skriva till varandra.',
            style: const TextStyle(fontSize: 13.5, color: ShaColors.text),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Stämmer inte'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: name.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          Contact(
                            identity: widget.peer,
                            name: name,
                            verifiedAt: DateTime.now(),
                          ),
                        ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Ja, lägg till'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Swedish genitive: "Eriks", but "Jonas" stays "Jonas".
String _genitive(String name) =>
    RegExp(r'[sxzSXZ]$').hasMatch(name) ? name : '${name}s';
