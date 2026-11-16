import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../crypto/crypto.dart';
import '../contacts/contacts_store.dart';
import '../transport/transport.dart';
import 'message_store.dart';
import 'messaging_service.dart';
import 'notice_texts.dart';

/// What an open chat shows: the messages and the collected failure lines
/// (0004 §10).
class ChatView {
  const ChatView({required this.messages, this.notices = const []});

  final List<ChatMessage> messages;
  final List<String> notices;
}

/// One open conversation. Auto-disposed when the chat closes.
///
/// - A message counts as shown when it is in this view: it is then removed
///   from the inbox on disk (0005 (i)).
/// - The failure counters are read, shown while the chat is open, and then
///   taken off the saved counters (0004 §10).
class ChatController extends Notifier<ChatView> {
  ChatController(this.contactId);

  final String contactId;
  OlmFailureCounts _shown = const OlmFailureCounts();

  Contact get _contact {
    final contact = ref.read(contactsProvider.notifier).byId(contactId);
    if (contact == null) throw StateError('Unknown contact');
    return contact;
  }

  @override
  ChatView build() {
    ref.listen(messageStoreProvider.select((all) => all[contactId]), (_, list) {
      state = ChatView(messages: list ?? const [], notices: state.notices);
      unawaited(_markShown());
    });
    ref.listen(failureTickProvider, (_, _) => unawaited(_readFailures()));
    scheduleMicrotask(() {
      unawaited(_markShown());
      unawaited(_readFailures());
    });
    return ChatView(
      messages: ref.read(messageStoreProvider.notifier).forContact(contactId),
    );
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final (_, message) = await ref
        .read(messagingServiceProvider)
        .send(contact: _contact, text: trimmed);
    ref.read(messageStoreProvider.notifier).add(contactId, message);
    unawaited(ref.read(transportProvider).sendPending());
  }

  Future<void> _markShown() async {
    final olm = ref.read(cryptoServiceProvider).olm;
    for (final m in state.messages) {
      final saved = m.savedId;
      if (m.outgoing || m.shown || saved == null) continue;
      await olm.markShown(saved);
      if (!ref.mounted) return;
      ref
          .read(messageStoreProvider.notifier)
          .update(
            contactId,
            m.id,
            (m) => m.copyWith(shown: true, clearSavedId: true),
          );
    }
  }

  /// One read at a time, so the same counts are never added twice.
  Future<void> _readFailures() =>
      _reading = _reading.then((_) => _readFailuresNow());
  Future<void> _reading = Future.value();

  Future<void> _readFailuresNow() async {
    final contact = ref.read(contactsProvider.notifier).byId(contactId);
    final key = contact?.olm?.identityKey;
    if (contact == null || key == null) return;
    final olm = ref.read(cryptoServiceProvider).olm;
    final counts = await olm.failureCounts(key);
    if (!ref.mounted) return;
    if (counts.unreadable + counts.tooLate + counts.gapTooBig == 0) return;
    _shown = OlmFailureCounts(
      unreadable: _shown.unreadable + counts.unreadable,
      tooLate: _shown.tooLate + counts.tooLate,
      gapTooBig: _shown.gapTooBig + counts.gapTooBig,
    );
    state = ChatView(
      messages: state.messages,
      notices: NoticeTexts.failures(contact.name, _shown),
    );
    await olm.clearFailureCounts(key, counts);
  }
}

final chatProvider = NotifierProvider.autoDispose
    .family<ChatController, ChatView, String>(ChatController.new);
