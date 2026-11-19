package se.sha.sha.lock

import android.annotation.TargetApi
import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's own lock for the app lock (F4, step 1 of (B) in 0011): the
 * platform's BiometricPrompt from Android 10, with the phone's PIN as the
 * alternative, and KeyguardManager's PIN screen on Android 7-9, where
 * BiometricPrompt cannot offer the PIN. No library and no key: the answer is
 * only "unlocked", "cancelled" or "unavailable". The system's error text is
 * never passed on.
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            prompt(title, text, result)
        } else {
            confirmCredential(title, text, result)
        }
    }

    // A platform annotation: no androidx library is added for it.
    @TargetApi(Build.VERSION_CODES.Q)
    private fun prompt(title: String, text: String, result: MethodChannel.Result) {
        val builder = BiometricPrompt.Builder(activity)
            .setTitle(title)
            .setDescription(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setDeviceCredentialAllowed(true)
        }
        pending = result
        builder.build().authenticate(
            CancellationSignal(),
            activity.mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authResult: BiometricPrompt.AuthenticationResult,
                ) = finish("unlocked")

                // A wrong finger is not the end: the prompt asks again. An
                // error (cancelled, too many tries) ends it; its text is not
                // passed on.
                override fun onAuthenticationError(code: Int, message: CharSequence) =
                    finish("cancelled")
            },
        )
    }

    private fun confirmCredential(title: String, text: String, result: MethodChannel.Result) {
        @Suppress("DEPRECATION")
        val intent: Intent? = keyguard().createConfirmDeviceCredentialIntent(title, text)
        if (intent == null) {
            result.success("unavailable")
            return
        }
        pending = result
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
