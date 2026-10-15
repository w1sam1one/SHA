import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../crypto/crypto.dart';

class IdentityState {
  const IdentityState({required this.identity, required this.firstLaunch});

  final PublicIdentity identity;

  /// True until the user has seen the "identity created" screen.
  final bool firstLaunch;
}

/// Loads this device's identity, creating one on first launch.
class IdentityController extends AsyncNotifier<IdentityState> {
  @override
  Future<IdentityState> build() async {
    final crypto = ref.watch(cryptoServiceProvider);
    final existing = await crypto.loadIdentity();
    if (existing != null) {
      return IdentityState(identity: existing, firstLaunch: false);
    }
    return IdentityState(
      identity: await crypto.createIdentity(),
      firstLaunch: true,
    );
  }

  void completeOnboarding() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      IdentityState(identity: current.identity, firstLaunch: false),
    );
  }
}

final identityProvider =
    AsyncNotifierProvider<IdentityController, IdentityState>(
      IdentityController.new,
      // Key-store failures should surface to the user, not be retried blindly.
      retry: (_, _) => null,
    );

/// This device's public identity. Only read once [identityProvider] has data.
final ownIdentityProvider = Provider<PublicIdentity>(
  (ref) => ref.watch(identityProvider).requireValue.identity,
);
