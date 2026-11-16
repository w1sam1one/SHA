import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'transport.dart';

/// Runs the [Transport] only while the app is in front (0002): it stops
/// when the app goes to the background or the phone is locked, and starts
/// a new round when the app comes back.
class TransportLifecycle extends ConsumerStatefulWidget {
  const TransportLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TransportLifecycle> createState() => _TransportLifecycleState();
}

class _TransportLifecycleState extends ConsumerState<TransportLifecycle> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: _changed);
    // After the first frame: providers may not change while building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final now = WidgetsBinding.instance.lifecycleState;
      if (mounted && (now == null || now == AppLifecycleState.resumed)) {
        ref.read(transportProvider).resume();
      }
    });
  }

  void _changed(AppLifecycleState state) {
    final transport = ref.read(transportProvider);
    if (state == AppLifecycleState.resumed) {
      transport.resume();
    } else {
      transport.pause();
    }
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
