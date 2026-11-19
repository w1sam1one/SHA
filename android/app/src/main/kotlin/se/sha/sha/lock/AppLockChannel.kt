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
 * Android 7-10. Android 10's BiometricPrompt can cancel at once or fail to
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
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                prompt(title, text)
            } else {
                confirmCredential(title, text)
            }
        } catch (e: RuntimeException) {
            // A framework bug while showing the prompt: answer, so that
            // "Lås upp" can ask again (review of #47). The text is not kept.
            finish("cancelled")
        }
    }

    // A platform annotation: no androidx library is added for it.
    @TargetApi(Build.VERSION_CODES.R)
    private fun prompt(title: String, text: String) {
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
                    ) = finish("unlocked")

                    // A wrong finger is not the end: the prompt asks again.
                    // An error (cancelled, too many tries) ends it; its text
                    // is not passed on.
                    override fun onAuthenticationError(code: Int, message: CharSequence) =
                        finish("cancelled")
                },
            )
    }

    private fun confirmCredential(title: String, text: String) {
        @Suppress("DEPRECATION")
        val intent: Intent? = keyguard().createConfirmDeviceCredentialIntent(title, text)
        if (intent == null) {
            finish("unavailable")
            return
        }
        activity.startActivityForResult(intent, REQUEST)
    }

    /** From MainActivity: true if the result was the PIN screen's. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST) return false
        finish(if (resultCode == Activity.RESULT_OK) "unlocked" else "cancelled")
        return true
    }

    private fun finish(answer: String) {
        val result = pending ?: return
        pending = null
        result.success(answer)
    }
}
