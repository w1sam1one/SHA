package se.sha.sha.app

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * The certificate the app is signed with (F14, 0014 (2c)), as Android
 * reports it: the SHA-256 of each signing certificate, in keytool's form
 * (upper case, with colons), and whether this is a debug build. With
 * minSdk 28 `signingInfo` is always there. With one signer and a rotated
 * key, the current certificate is the last in the history. Errors give a
 * fixed code only.
 */
class AppSignatureChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "read") {
            result.notImplemented()
            return
        }
        val answer = try {
            read()
        } catch (e: Exception) {
            null
        }
        if (answer == null) result.error("unavailable", null, null) else result.success(answer)
    }

    private fun read(): Map<String, Any> {
        @Suppress("DEPRECATION") // the PackageInfoFlags form needs API 33
        val info = context.packageManager.getPackageInfo(
            context.packageName,
            PackageManager.GET_SIGNING_CERTIFICATES,
        )
        val signing = info.signingInfo ?: throw IllegalStateException()
        val current = if (signing.hasMultipleSigners()) {
            signing.apkContentsSigners.toList()
        } else {
            listOf(signing.signingCertificateHistory.last())
        }
        val digest = MessageDigest.getInstance("SHA-256")
        val fingerprints = current.map { certificate ->
            digest.digest(certificate.toByteArray()).joinToString(":") { "%02X".format(it) }
        }
        val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        return mapOf("sha256" to fingerprints, "debuggable" to debuggable)
    }

    companion object {
        const val NAME = "se.sha.sha/app_signature"
    }
}
