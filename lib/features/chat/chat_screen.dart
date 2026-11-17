import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../ui/avatar.dart';
import '../../ui/technical_info_sheet.dart';
import '../../ui/time_format.dart';
import '../../ui/trust_display.dart';
import '../contacts/contacts_store.dart';
import '../transport/transport.dart';
import 'chat_controller.dart';
import 'message_store.dart';
import 'messaging_service.dart';
import 'notice_texts.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.contactId});

  final String contactId;

  static Future<void> open(BuildContext context, String contactId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(contactId: contactId),
        ),
      );

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(chatProvider(widget.contactId).notifier).send(text);
      _input.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is MessageTooLongException
                  ? 'Meddelandet är för långt.'
                  : describeError(e),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contact = ref.watch(
      contactsProvider.select(
        (all) => all.where((c) => c.id == widget.contactId).firstOrNull,
      ),
    );
    if (contact == null) {
      return const Scaffold(body: Center(child: Text('Kontakten finns inte.')));
    }
    final view = ref.watch(chatProvider(widget.contactId));
    final status = ref.watch(serverStatusProvider);
    final settings = ref.watch(transportSettingsProvider).value;
    final statusText = _statusText(
      noServer: settings != null && settings.server == null,
      status: status,
      waiting: view.messages.any((m) => m.pending),
    );
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        shape: const Border(bottom: BorderSide(color: ShaColors.divider)),
        title: Row(
          children: [
            ContactAvatar(
              name: contact.name,
              hash: contact.identity.hash,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  VerifiedInPerson(
                    verifiedAt: contact.verifiedAt,
                    fontSize: 12.5,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                for (final m in view.messages.reversed) _Bubble(message: m),
                for (final n in view.notices.reversed) _ChatNotice(text: n),
                const SizedBox(height: 8),
                _E2eNotice(name: contact.name),
              ],
            ),
          ),
          if (statusText != null) _StatusNotice(text: statusText),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: MessagingService.maxTextLength,
                      buildCounter: _hideCounter,
                      // Ask the keyboard not to learn from what is typed.
                      enableIMEPersonalizedLearning: false,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Skriv ett meddelande',
                        filled: true,
                        fillColor: ShaColors.surfaceHigh,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Skicka',
                    iconSize: 22,
                    style: IconButton.styleFrom(fixedSize: const Size(52, 52)),
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the chat says about the server (0004 §10). "No server" comes from
/// the settings. "Full" is shown only in a chat with a message waiting.
/// Nothing when all is well or when there is no answer: messages then wait
/// in the outbox, and each one says it is not sent yet.
String? _statusText({
  required bool noServer,
  required ServerStatus status,
  required bool waiting,
}) {
  if (noServer) {
    return 'Ingen server är inställd än. Meddelanden sparas och skickas när '
        'du har skrivit in serverns adress under Inställningar.';
  }
  return switch (status) {
    ServerStatus.busy => NoticeTexts.serverBusy,
    ServerStatus.full when waiting => NoticeTexts.serverFull,
    _ => null,
  };
}

Widget? _hideCounter(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) => null;

/// The server's state, above the text field. Neutral (not a warning): the
/// app keeps the message and tries again by itself.
class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ShaColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: ShaColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 18 / 13,
                color: ShaColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A collected line about messages that could not be read (0004 §10).
class _ChatNotice extends StatelessWidget {
  const _ChatNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ShaColors.navBar,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            height: 18 / 12.5,
            color: ShaColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _E2eNotice extends StatelessWidget {
  const _E2eNotice({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ShaColors.navBar,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: ShaColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meddelanden är krypterade. Bara du och $name kan läsa dem.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 18 / 12.5,
                      color: ShaColors.textSecondary,
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () => showTechnicalInfoSheet(context),
                    child: const Text('Teknisk information'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final out = message.outgoing;
    final failed = message.text == null;
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: out ? ShaColors.primaryContainer : ShaColors.surfaceHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(out ? 20 : 6),
            bottomRight: Radius.circular(out ? 6 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              failed ? 'Meddelandet kunde inte läsas.' : message.text!,
              style: TextStyle(
                fontSize: 15,
                height: 21 / 15,
                fontStyle: failed ? FontStyle.italic : null,
                color: out ? ShaColors.bubbleOutgoingText : ShaColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message.pending
                  ? 'Inte skickat än · ${formatTime(message.sentAt)}'
                  : formatTime(message.sentAt),
              style: TextStyle(
                fontSize: 11,
                color: out
                    ? ShaColors.bubbleOutgoingMeta
                    : ShaColors.bubbleIncomingMeta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
