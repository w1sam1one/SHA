import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../ui/avatar.dart';
import '../../ui/time_format.dart';
import '../contacts/contacts_store.dart';
import 'chat_controller.dart';
import 'messaging_service.dart';

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
    final messages = ref.watch(chatProvider(widget.contactId));
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
              verified: true,
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
                  const Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: ShaColors.success,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Verifierad kontakt',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: ShaColors.success,
                        ),
                      ),
                    ],
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
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(describeError(error), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(chatProvider(widget.contactId)),
                        child: const Text('Försök igen'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (list) => ListView(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                children: [
                  for (final m in list.reversed) _Bubble(message: m),
                  const SizedBox(height: 8),
                  _E2eNotice(name: contact.name),
                ],
              ),
            ),
          ),
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
                        hintText: 'Krypterat meddelande',
                        filled: true,
                        fillColor: ShaColors.surfaceHigh,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        suffixIcon: const Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: Color(0xFF8F989E),
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

Widget? _hideCounter(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) => null;

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
              child: Text(
                'Meddelanden krypteras med AES-256-GCM. '
                'Bara du och $name har nyckeln.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 18 / 12.5,
                  color: ShaColors.textSecondary,
                ),
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
              failed ? 'Meddelandet kunde inte verifieras' : message.text!,
              style: TextStyle(
                fontSize: 15,
                height: 21 / 15,
                fontStyle: failed ? FontStyle.italic : null,
                color: out ? ShaColors.bubbleOutgoingText : ShaColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatTime(message.sentAt),
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
