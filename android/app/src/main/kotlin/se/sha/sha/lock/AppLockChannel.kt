package se.sha.sha.lock

import android.annotation.TargetApi
import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.os.SystemClock
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's own lock for the app lock (F4, step 1 of (B) in 0011): the
 * platform's BiometricPrompt from Android 11, with the phone's PIN, pattern
 * or password as the alternative, and KeyguardManager's PIN screen on
 * Android 9-10 (minSdk 28, 0014). Android 10's BiometricPrompt can cancel at once or fail to
 * show the PIN on phones without biometric hardware (review of #47, as
 * androidx.biometric works around), so it is not used there. No library and
 * no key: the answer is only "unlocked", "cancelled" or "unavailable", and the
 * system's error text is never passed on.
 */
class AppLockChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val NAME = "se.sha.sha/app_lock"
        private const val REQUEST = 0x5A1
    }

    private var pending: MethodChannel.Result? = null

    /** Counts the requests, so that a late answer to an old one is dropped. */
    private var request = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canLock" -> result.success(keyguard().isDeviceSecure)
            // Time since the phone started, deep sleep included: nobody can
            // set it back, unlike the wall clock (review of #47).
            "elapsed" -> result.success(SystemClock.elapsedRealtime())
            "unlock" -> unlock(
                call.argument<String>("title") ?: "",
                call.argument<String>("text") ?: "",
                result,
            )
            else -> result.notImplemented()
        }
    }

    private fun keyguard(): KeyguardManager =
        activity.getSystemService(KeyguardManager::class.java)

    private fun unlock(title: String, text: String, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("BUSY", "An unlock is already shown", null)
            return
        }
        if (!keyguard().isDeviceSecure) {
            result.success("unavailable")
            return
        }
        pending = result
        val id = ++request
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    prompt(id, title, text)
                } catch (e: RuntimeException) {
                    // A framework bug in BiometricPrompt: the phone's PIN
                    // screen instead, so the app can still be unlocked
                    // (second review of #47). The text is not kept.
                    confirmCredential(id, title, text)
                }
            } else {
                confirmCredential(id, title, text)
            }
        } catch (e: RuntimeException) {
            // Neither could be shown: answer, so that "Lås upp" can ask
            // again (review of #47).
            finish(id, "cancelled")
        }
    }

    // A platform annotation: no androidx library is added for it.
    @TargetApi(Build.VERSION_CODES.R)
    private fun prompt(id: Int, title: String, text: String) {
        BiometricPrompt.Builder(activity)
            .setTitle(title)
            .setDescription(text)
            .setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
            .build()
            .authenticate(
                CancellationSignal(),
                activity.mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        authResult: BiometricPrompt.AuthenticationResult,
                    ) = finish(id, "unlocked")

                    // A wrong finger is not the end: the prompt asks again.
                    // An error (cancelled, too many tries) ends it; its text
                    // is not passed on.
                    override fun onAuthenticationError(code: Int, message: CharSequence) =
                        finish(id, "cancelled")
                },
            )
    }

    private fun confirmCredential(id: Int, title: String, text: String) {
        @Suppress("DEPRECATION")
        val intent: Intent? = keyguard().createConfirmDeviceCredentialIntent(title, text)
        if (intent == null) {
            finish(id, "unavailable")
            return
        }
        activity.startActivityForResult(intent, REQUEST)
    }

    /** From MainActivity: true if the result was the PIN screen's. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST) return false
        finish(request, if (resultCode == Activity.RESULT_OK) "unlocked" else "cancelled")
        return true
    }

    /** Answers request [id] once; an answer to an older request is dropped. */
    private fun finish(id: Int, answer: String) {
        if (id != request) return
        val result = pending ?: return
        pending = null
        result.success(answer)
    }
}
