import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Technical details for people who want them. This is the only screen that
/// names algorithms. Every statement must match the code or
/// README.md / docs/SECURITY_REVIEW.md:
/// - identity, hashing: lib/crypto/src/types.dart, sha_crypto_service.dart
/// - key storage: android/.../keystore/KeystoreVault.kt
/// - randomness: lib/crypto/src/entropy.dart
/// - contact keys, code: lib/crypto/src/key_agreement.dart, sha_crypto_service.dart
/// - messages, packets: lib/crypto/src/aes_gcm.dart, padding.dart, wire_format.dart,
///   lib/features/chat/messaging_service.dart (payload); what a relay sees:
///   docs/SECURITY_REVIEW.md ("Vad en angripare kan och inte kan")
/// - software-only warning: lib/features/home/home_shell.dart
/// - "Finns inte än": README.md "Nästa steg", docs/SECURITY_REVIEW.md
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
                  'Din identitet är ett X25519-nyckelpar. Det som visas som din '
                      'identitet är SHA-256 av den offentliga nyckeln. QR-koden '
                      'innehåller både den offentliga nyckeln och hashen.',
                  'Den privata nyckeln krypteras med AES-256-GCM av en nyckel '
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
                  'För varje kontakt tas nycklar fram med X25519 och '
                      'HKDF-SHA256, en uppsättning för varje riktning.',
                  'Kontrollkoden är 20 siffror som räknas fram med SHA-256 av '
                      'era två offentliga nycklar.',
                ],
              ),
              _Section(
                title: 'Meddelanden',
                lines: [
                  'Varje meddelande fylls ut till en av fem fasta storlekar och '
                      'krypteras med AES-256-GCM med ett nytt slumpmässigt nonce.',
                  'Paketformatet är förberett för reläer: ett paket är adresserat '
                      'till ett brevlåde-id som byts varje dygn och skiljer sig per '
                      'kontakt och riktning. Paketet innehåller inga identiteter; '
                      'meddelandets id, tid och text finns bara inuti krypteringen. '
                      'Ett relä skulle se brevlåde-id, paketstorlek, när paketet kom '
                      'fram och IP-adresser.',
                ],
              ),
              _Section(
                title: 'Finns inte än',
                lines: [
                  'Meddelanden skickas inte – det finns ingen överföring än.',
                  'Ingen forward secrecy (Double Ratchet saknas). Om en '
                      'identitetsnyckel läcker kan sparade meddelanden läsas.',
                  'Kontakter och meddelanden finns bara i minnet och försvinner '
                      'när appen stängs. Din identitet sparas.',
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
