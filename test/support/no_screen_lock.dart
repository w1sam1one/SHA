import 'package:sha/features/lock/app_lock.dart';

/// A phone without a screen lock: the app lock (F4) lets the app open
/// without a prompt, so tests of other screens are not stopped by it.
final class NoScreenLock implements AppLockPlatform {
  const NoScreenLock();

  @override
  Future<bool> canLock() async => false;

  @override
  Future<UnlockResult> unlock({
    required String title,
    required String text,
  }) async => UnlockResult.unavailable;
}
