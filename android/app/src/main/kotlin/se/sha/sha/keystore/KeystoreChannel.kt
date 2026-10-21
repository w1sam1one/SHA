package se.sha.sha.keystore

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.UnrecoverableKeyException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.crypto.AEADBadTagException

/**
 * In-process bridge between Dart and [KeystoreVault]. Keystore work runs on
 * a background thread (StrongBox is slow); results go back on the main thread.
 * Errors are reported with fixed codes only — never with exception messages,
 * which could describe data.
 */
class KeystoreChannel(context: Context) : MethodChannel.MethodCallHandler {
    private val vault = KeystoreVault(context)
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            val outcome: Result<Any?> = runCatching {
                when (call.method) {
                    "read" -> vault.read(call.requireName())
                    "write" -> {
                        val value = call.argument<ByteArray>("value")
                            ?: throw VaultException(VaultException.INVALID)
                        try {
                            vault.write(call.requireName(), value)
                        } finally {
                            value.fill(0)
                        }
                        null
                    }
                    "delete" -> vault.delete(call.requireName())
                    "reset" -> {
                        vault.reset()
                        // Unit cannot be encoded by the codec; reply with null.
                        null
                    }
                    "randomBytes" -> vault.randomBytes(
                        call.argument<Int>("length") ?: throw VaultException(VaultException.INVALID),
                    )
                    "protection" -> vault.protection()
                    else -> NotImplemented
                }
            }
            main.post {
                outcome.fold(
                    onSuccess = { value ->
                        if (value === NotImplemented) result.notImplemented() else result.success(value)
                        // The codec has copied the bytes; clear our copy.
                        if (call.method == "read" && value is ByteArray) value.fill(0)
                    },
                    onFailure = { error -> errorCode(error).let { result.error(it, it, null) } },
                )
            }
        }
    }

    private fun MethodCall.requireName(): String =
        argument<String>("name") ?: throw VaultException(VaultException.INVALID)

    private fun errorCode(error: Throwable): String = when (error) {
        is VaultException -> error.code
        is UserNotAuthenticatedException -> "LOCKED"
        is KeyPermanentlyInvalidatedException -> "INVALIDATED"
        is UnrecoverableKeyException -> "INVALIDATED"
        is AEADBadTagException -> "CORRUPT"
        else -> if (error.cause is UserNotAuthenticatedException) "LOCKED" else "UNAVAILABLE"
    }

    private object NotImplemented

    companion object {
        const val NAME = "se.sha/keystore"
    }
}
