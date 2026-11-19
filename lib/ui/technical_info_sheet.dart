import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Technical details for people who want them. This is the only screen that
/// names algorithms. Every statement must match the code or the docs:
/// - identity, hashing: lib/crypto/src/types.dart, sha_crypto_service.dart
/// - key storage: android/.../keystore/KeystoreVault.kt
/// - randomness: lib/crypto/src/entropy.dart
/// - Olm, sessions, saving: lib/crypto/src/sha_olm_service.dart, 0003,
///   0004 §6, 0005
/// - QR code, verification code: lib/features/qr/contact_code.dart, 0004 §1
/// - mailbox IDs: lib/crypto/src/key_agreement.dart, 0004 §3 (A)
/// - padding, packets: lib/crypto/src/olm_padding.dart,
///   olm_wire_format.dart, 0004 §4 and §5
/// - the server: lib/features/transport/, relay/README.md, 0002
/// - software-only warning: lib/features/home/home_shell.dart
/// - "Finns inte än": docs/ROADMAP.md
/// The user sees "servern", never "relayn" (0004 §10).
Future<void> showTechnicalInfoSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ShaColors.navBar,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: const SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Teknisk information',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              _Section(
                title: 'Identitet',
                lines: [
                  'Appen har två nyckelpar: ett Olm-konto för meddelandena och '
                      'ett X25519-nyckelpar för brevlådorna. Det som visas som din '
                      'identitet är SHA-256 av den offentliga X25519-nyckeln.',
                  'Det som sparas krypteras med AES-256-GCM av en nyckel '
                      'i Android Keystore – i StrongBox om telefonen har det, '
                      'annars i TEE om den finns. Saknas båda skyddas nyckeln bara '
                      'av mjukvara, och då varnar appen. Keystore-nyckeln kan inte '
                      'exporteras och fungerar bara när telefonen är upplåst '
                      '(Android 9 och senare).',
                  'Nyckelparet skapas från två slumpkällor, Dart och Android, '
                      'som blandas med HKDF-SHA256.',
                ],
              ),
              _Section(
                title: 'Kontakter',
                lines: [
                  'En kontakt läggs bara till när ni möts och skannar varandras '
                      'QR-koder. Koden innehåller Olm-identitetsnyckeln, en ny '
                      'engångsnyckel och en X25519-nyckel för brevlådorna.',
                  'Kontrollkoden är 20 siffror som räknas fram med SHA-256 av '
                      'era två Olm-identitetsnycklar.',
                ],
              ),
              _Section(
                title: 'Meddelanden',
                lines: [
                  'Meddelanden krypteras med Olm (vodozemac), samma protokoll '
                      'som Matrix använder. Varje meddelande får en ny nyckel.',
                  'Varje meddelande fylls ut till en av fem fasta storlekar '
                      'innan det krypteras.',
                  'Kontot, sessionerna och kontakterna sparas i en enda post '
                      'som krypteras med en nyckel i Android Keystore. Ett '
                      'meddelande ligger där tills det har skickats eller '
                      'visats.',
                  'Historiken sparas i egna poster, krypterade med samma '
                      'nyckel, så länge du har valt under Inställningar. Sedan '
                      'tas den bort ur appen. Kopior kan finnas kvar i '
                      'telefonens minne tills du avinstallerar appen. Väljer du '
                      '"Spara inte" finns ett meddelande bara i minnet tills '
                      'appen stängs.',
                ],
              ),
              _Section(
                title: 'Servern',
                lines: [
                  'Meddelanden går via en server som du ställer in. Servern kan '
                      'bara lämna och hämta paket. Den har inga konton och '
                      'skickar inga notiser.',
                  'Ett paket är adresserat till ett brevlåde-id som byts varje '
                      'dygn och skiljer sig per kontakt och riktning. Servern ser '
                      'brevlåde-id, paketets storlek, när paketet kom fram och '
                      'din IP-adress.',
                  'Appen hämtar bara när den är öppen, varje brevlåda vid en '
                      'egen slumpad tid i varje runda. En runda är det intervall '
                      'du har valt, eller längre om du har många kontakter.',
                ],
              ),
              _Section(
                title: 'Finns inte än',
                lines: [
                  'Ingen säkerhetskopia. Tappar du telefonen måste ni träffas '
                      'och skanna varandras QR-koder på nytt.',
                  'Inget app-lås med biometri eller PIN.',
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontSize: 14.5)),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.45,
                        color: ShaColors.textSecondary,
                      ),
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
