import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../transport/transport.dart';
import '../transport/transport_settings.dart';

/// The server address and how often to fetch (P6, 0002).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _address = TextEditingController();
  bool _filled = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _save(TransportSettings current, {Uri? server}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(transportSettingsProvider.notifier)
          .save(current.copyWith(server: server));
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAddress(TransportSettings current) async {
    final Uri server;
    try {
      server = TransportSettings.parseServer(_address.text);
    } on ServerAddressException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    _address.text = server.toString();
    await _save(current, server: server);
    if (mounted && _error == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Adressen är sparad.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(transportSettingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inställningar', style: TextStyle(fontSize: 26)),
      ),
      body: switch (settings) {
        AsyncData(:final value) => _form(value),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(describeError(error), textAlign: TextAlign.center),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _form(TransportSettings current) {
    if (!_filled) {
      _filled = true;
      _address.text = current.server?.toString() ?? '';
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text(
          'Server',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Meddelanden går via servern på den här adressen.',
          style: TextStyle(color: ShaColors.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(
            labelText: 'Serverns adress',
            hintText: 'https://server.example.se',
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _saveAddress(current),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy ? null : () => _saveAddress(current),
            child: const Text('Spara adressen'),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Hämta nya meddelanden',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Appen hämtar bara när den är öppen. Inga notiser.',
          style: TextStyle(color: ShaColors.textSecondary),
        ),
        RadioGroup<FetchInterval>(
          groupValue: current.interval,
          onChanged: (i) {
            if (i != null && !_busy) _save(current.copyWith(interval: i));
          },
          child: Column(
            children: [
              for (final i in FetchInterval.values)
                RadioListTile<FetchInterval>(
                  contentPadding: EdgeInsets.zero,
                  value: i,
                  title: Text(i.label),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Licenser'),
          subtitle: const Text('Programvara och typsnitt som SHA bygger på'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () =>
              showLicensePage(context: context, applicationName: 'SHA'),
        ),
      ],
    );
  }
}
