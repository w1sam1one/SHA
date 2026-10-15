package se.sha.sha.keystore

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import java.security.ProviderException
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/**
 * Encrypted storage for SHA's long-term secrets.
 *
 * - One AES-256-GCM wrapping key, generated inside the Android Keystore:
 *   StrongBox when available, otherwise the TEE. It is non-exportable,
 *   bound to this app's UID, and (API 28+) only usable while the phone is
 *   unlocked.
 * - Each secret is stored as `version || ivLength || iv || ciphertext+tag` in
 *   `noBackupFilesDir/sha_keys/`, which is private to the app and never
 *   backed up. The entry name is GCM associated data, so blobs cannot be
 *   swapped between entries.
 * - Nothing here logs, and errors carry fixed codes only.
 */
class KeystoreVault(context: Context) {
    private val appContext = context.applicationContext
    private val dir = File(appContext.noBackupFilesDir, DIRECTORY)
    private val random = SecureRandom()

    fun read(name: String): ByteArray? {
        val bytes = try {
            AtomicFile(fileFor(name)).readFully()
        } catch (_: FileNotFoundException) {
            return null
        }
        if (bytes.size < 2 + GCM_TAG_BYTES || bytes[0] != FORMAT_VERSION) {
            throw VaultException(VaultException.CORRUPT)
        }
        val ivLength = bytes[1].toInt()
        if (ivLength !in 12..16 || bytes.size < 2 + ivLength + GCM_TAG_BYTES) {
            throw VaultException(VaultException.CORRUPT)
        }
        val key = existingKey() ?: throw VaultException(VaultException.INVALIDATED)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(GCM_TAG_BYTES * 8, bytes, 2, ivLength),
        )
        cipher.updateAAD(aad(name))
        return cipher.doFinal(bytes, 2 + ivLength, bytes.size - 2 - ivLength)
    }

    fun write(name: String, value: ByteArray) {
        val key = existingKey() ?: generateKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        // The Keystore picks a fresh random IV; callers cannot supply one.
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(aad(name))
        val sealed = cipher.doFinal(value)
        val iv = cipher.iv
        val blob = ByteArray(2 + iv.size + sealed.size)
        blob[0] = FORMAT_VERSION
        blob[1] = iv.size.toByte()
        iv.copyInto(blob, 2)
        sealed.copyInto(blob, 2 + iv.size)

        if (!dir.isDirectory && !dir.mkdirs()) throw VaultException(VaultException.UNAVAILABLE)
        val file = AtomicFile(fileFor(name))
        val out = file.startWrite()
        try {
            out.write(blob)
            file.finishWrite(out)
        } catch (e: Exception) {
            file.failWrite(out)
            throw e
        }
    }

    fun delete(name: String) {
        AtomicFile(fileFor(name)).delete()
    }

    /** Bytes from the platform CSPRNG (Conscrypt/BoringSSL, kernel-seeded). */
    fun randomBytes(length: Int): ByteArray {
        require(length in 1..1024)
        return ByteArray(length).also(random::nextBytes)
    }

    fun protection(): Map<String, Any> {
        val keyguard = appContext.getSystemService(KeyguardManager::class.java)
        val key = existingKey()
        return mapOf(
            "level" to (key?.let(::securityLevel) ?: "unknown"),
            "deviceSecure" to (keyguard?.isDeviceSecure == true),
            "unlockedDeviceRequired" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P),
        )
    }

    private fun fileFor(name: String): File {
        if (!NAME.matches(name)) throw VaultException(VaultException.INVALID)
        return File(dir, "$name.bin")
    }

    private fun aad(name: String) = "SHA/vault/v1/$name".toByteArray(Charsets.UTF_8)

    private fun existingKey(): SecretKey? {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        return keyStore.getKey(KEY_ALIAS, null) as SecretKey?
    }

    private fun generateKey(): SecretKey {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                return generateKey(strongBox = true)
            } catch (_: StrongBoxUnavailableException) {
                // Fall through to the TEE.
            } catch (_: ProviderException) {
                // Some StrongBox implementations reject the parameters.
            }
        }
        return generateKey(strongBox = false)
    }

    private fun generateKey(strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            spec.setIsStrongBoxBacked(strongBox)
            spec.setUnlockedDeviceRequired(true)
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(spec.build())
        return generator.generateKey()
    }

    @Suppress("DEPRECATION")
    private fun securityLevel(key: SecretKey): String {
        val info = SecretKeyFactory.getInstance(key.algorithm, ANDROID_KEYSTORE)
            .getKeySpec(key, KeyInfo::class.java) as KeyInfo
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "tee"
                KeyProperties.SECURITY_LEVEL_UNKNOWN_SECURE -> "secure_hardware"
                KeyProperties.SECURITY_LEVEL_SOFTWARE -> "software"
                else -> "unknown"
            }
        }
        return if (info.isInsideSecureHardware) "secure_hardware" else "software"
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "se.sha.vault.wrap.v1"
        private const val DIRECTORY = "sha_keys"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BYTES = 16
        private const val FORMAT_VERSION: Byte = 1
        private val NAME = Regex("^[a-z0-9][a-z0-9._-]{0,63}$")
    }
}

class VaultException(val code: String) : Exception(code) {
    companion object {
        const val CORRUPT = "CORRUPT"
        const val INVALIDATED = "INVALIDATED"
        const val INVALID = "INVALID"
        const val UNAVAILABLE = "UNAVAILABLE"
    }
}
