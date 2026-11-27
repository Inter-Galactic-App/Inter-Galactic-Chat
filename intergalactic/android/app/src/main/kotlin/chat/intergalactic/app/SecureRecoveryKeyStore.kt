package chat.intergalactic.app

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.InvalidAlgorithmParameterException
import java.security.InvalidKeyException
import java.security.KeyStore
import java.security.ProviderException
import java.security.UnrecoverableKeyException
import java.time.Instant
import java.util.concurrent.Executor
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

private const val SECURE_RECOVERY_KEY_CHANNEL =
    "chat.intergalactic.app/secure_recovery_key"
private const val ANDROID_KEYSTORE = "AndroidKeyStore"
private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
private const val GCM_TAG_BITS = 128
private const val RECOVERY_KEY_PREFS = "secure_recovery_key_store"
private const val RECOVERY_KEY_ALIAS_PREFIX =
    "chat.intergalactic.app.secure_recovery_key."

object SecureRecoveryKeyStore {
    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURE_RECOVERY_KEY_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> handleGetStatus(activity, call, result)
                    "writeRecoveryKey" -> handleWriteRecoveryKey(activity, call, result)
                    "readRecoveryKey" -> handleReadRecoveryKey(activity, call, result)
                    "deleteRecoveryKey" -> handleDeleteRecoveryKey(activity, call, result)
                    "deleteAllRecoveryKeys" -> handleDeleteAllRecoveryKeys(activity, result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun handleGetStatus(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val accountKey = accountKeyFrom(call)
        if (accountKey == null) {
            result.error(
                "invalid_arguments",
                "Missing recovery-key account scope.",
                null,
            )
            return
        }

        val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
        val biometricStrongAvailable = canAuthenticateWithStrongBiometrics(activity)
        val record = loadRecord(activity, accountKey)
        var unavailableReason: String? = when {
            !supported -> "unsupported_platform"
            !biometricStrongAvailable -> "biometrics_unavailable"
            record == null -> "not_stored"
            else -> null
        }

        if (supported && biometricStrongAvailable && record != null) {
            try {
                initDecryptCipher(accountKey, record.iv)
            } catch (exception: Exception) {
                unavailableReason = if (isBiometryInvalidation(exception)) {
                    "biometry_changed_or_unavailable"
                } else {
                    "keychain_error"
                }
            }
        }

        val response = mutableMapOf<String, Any>(
            "platform" to "android",
            "supported" to supported,
            "biometricAvailable" to biometricStrongAvailable,
            "biometricStrongAvailable" to biometricStrongAvailable,
            "stored" to (record != null),
            "biometryType" to if (biometricStrongAvailable) {
                resolveBiometryType(activity)
            } else {
                "none"
            },
        )

        if (unavailableReason != null) {
            response["unavailableReason"] = unavailableReason
        }
        record?.lastUpdatedAt?.let { response["lastUpdatedAt"] = it }
        record?.hardwareBacked?.let { response["hardwareBacked"] = it }
        record?.strongBoxBacked?.let { response["strongBoxBacked"] = it }

        result.success(response)
    }

    private fun handleWriteRecoveryKey(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val accountKey = accountKeyFrom(call)
        val recoveryKey = call.argument<String>("recoveryKey")?.trim()
        if (accountKey == null || recoveryKey.isNullOrEmpty()) {
            result.error(
                "invalid_arguments",
                "Missing recovery-key write arguments.",
                null,
            )
            return
        }
        if (!canAuthenticateWithStrongBiometrics(activity)) {
            result.error(
                "biometrics_unavailable",
                "Strong biometric unlock is not available.",
                null,
            )
            return
        }

        val cipher = try {
            initEncryptCipher(activity, accountKey)
        } catch (exception: Exception) {
            if (!isBiometryInvalidation(exception)) {
                result.error("keychain_error", "Secure recovery-key write failed.", null)
                return
            }

            try {
                deleteKeyStoreEntry(accountKey)
                initEncryptCipher(activity, accountKey)
            } catch (retryException: Exception) {
                resultForException(result, retryException)
                return
            }
        }

        authenticateWithCipher(
            activity = activity,
            title = "Store your Matrix recovery key",
            cipher = cipher,
            result = result,
        ) { authenticatedCipher ->
            val plaintext = recoveryKey.toByteArray(Charsets.UTF_8)
            try {
                val ciphertext = authenticatedCipher.doFinal(plaintext)
                val metadata = inspectKeyMetadata(accountKey)
                val stored = storeRecord(
                    activity = activity,
                    accountKey = accountKey,
                    iv = authenticatedCipher.iv,
                    ciphertext = ciphertext,
                    metadata = metadata,
                )
                if (stored) {
                    result.success(true)
                } else {
                    result.error(
                        "keychain_error",
                        "Secure recovery-key metadata could not be stored.",
                        null,
                    )
                }
            } catch (exception: Exception) {
                resultForException(result, exception)
            } finally {
                plaintext.fill(0)
            }
        }
    }

    private fun handleReadRecoveryKey(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val accountKey = accountKeyFrom(call)
        if (accountKey == null) {
            result.error(
                "invalid_arguments",
                "Missing recovery-key account scope.",
                null,
            )
            return
        }
        if (!canAuthenticateWithStrongBiometrics(activity)) {
            result.error(
                "biometry_changed_or_unavailable",
                "Strong biometric unlock is not available for this stored key.",
                null,
            )
            return
        }

        val record = loadRecord(activity, accountKey)
        if (record == null) {
            result.error("not_found", "No stored recovery key was found.", null)
            return
        }

        val cipher = try {
            initDecryptCipher(accountKey, record.iv)
        } catch (exception: Exception) {
            resultForException(result, exception)
            return
        }

        val reason = call.argument<String>("reason")
            ?.takeIf { it.isNotBlank() }
            ?: "Unlock your stored Matrix recovery key"

        authenticateWithCipher(
            activity = activity,
            title = reason,
            cipher = cipher,
            result = result,
        ) { authenticatedCipher ->
            var plaintext: ByteArray? = null
            try {
                plaintext = authenticatedCipher.doFinal(record.ciphertext)
                val recoveryKey = plaintext.toString(Charsets.UTF_8).trim()
                if (recoveryKey.isEmpty()) {
                    result.error(
                        "keychain_error",
                        "The stored recovery key could not be decoded.",
                        null,
                    )
                } else {
                    result.success(recoveryKey)
                }
            } catch (exception: Exception) {
                resultForException(result, exception)
            } finally {
                plaintext?.fill(0)
            }
        }
    }

    private fun handleDeleteRecoveryKey(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val accountKey = accountKeyFrom(call)
        if (accountKey == null) {
            result.error(
                "invalid_arguments",
                "Missing recovery-key account scope.",
                null,
            )
            return
        }

        return try {
            deleteRecord(activity, accountKey)
            deleteKeyStoreEntry(accountKey)
            result.success(true)
        } catch (exception: Exception) {
            result.error(
                "keychain_error",
                "Secure recovery-key delete failed.",
                null,
            )
        }
    }

    private fun handleDeleteAllRecoveryKeys(
        activity: Activity,
        result: MethodChannel.Result,
    ) {
        try {
            val prefsCleared = prefs(activity).edit().clear().commit()
            if (!prefsCleared) {
                result.error(
                    "keychain_error",
                    "Secure recovery-key metadata cleanup failed.",
                    null,
                )
                return
            }
            deleteAllKeyStoreEntries()
            result.success(true)
        } catch (exception: Exception) {
            result.error(
                "keychain_error",
                "Secure recovery-key cleanup failed.",
                null,
            )
        }
    }

    private fun authenticateWithCipher(
        activity: Activity,
        title: String,
        cipher: Cipher,
        result: MethodChannel.Result,
        onSuccess: (Cipher) -> Unit,
    ) {
        if (activity !is FragmentActivity) {
            result.error(
                "keychain_error",
                "Secure recovery-key biometric prompt is unavailable.",
                null,
            )
            return
        }

        val executor: Executor = ContextCompat.getMainExecutor(activity)
        var resultSubmitted = false

        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult,
                ) {
                    if (resultSubmitted) {
                        return
                    }
                    resultSubmitted = true
                    val authenticatedCipher =
                        authenticationResult.cryptoObject?.cipher
                    if (authenticatedCipher == null) {
                        result.error(
                            "keychain_error",
                            "Secure recovery-key authentication did not return a cipher.",
                            null,
                        )
                        return
                    }

                    onSuccess(authenticatedCipher)
                }

                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence,
                ) {
                    if (resultSubmitted) {
                        return
                    }
                    resultSubmitted = true
                    result.error(
                        biometricPromptErrorCode(errorCode),
                        errString.toString(),
                        null,
                    )
                }
            },
        )

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title.takeIf { it.isNotBlank() } ?: "Authenticate with biometrics")
            .setNegativeButtonText("Cancel")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()

        activity.runOnUiThread {
            prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(cipher))
        }
    }

    private fun initEncryptCipher(activity: Activity, accountKey: String): Cipher {
        val key = getOrCreateSecretKey(activity, accountKey)
        return Cipher.getInstance(AES_GCM_TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, key)
        }
    }

    private fun initDecryptCipher(accountKey: String, iv: ByteArray): Cipher {
        val key = getSecretKey(accountKey)
            ?: throw KeyPermanentlyInvalidatedException()
        return Cipher.getInstance(AES_GCM_TRANSFORMATION).apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        }
    }

    private fun getOrCreateSecretKey(activity: Activity, accountKey: String): SecretKey {
        val existingKey = getSecretKey(accountKey)
        if (existingKey != null) {
            return existingKey
        }
        return generateSecretKey(activity, accountKey)
    }

    private fun getSecretKey(accountKey: String): SecretKey? {
        val keyStore = keyStore()
        return keyStore.getKey(aliasFor(accountKey), null) as? SecretKey
    }

    private fun generateSecretKey(activity: Activity, accountKey: String): SecretKey {
        val strongBoxAvailable =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                activity.packageManager.hasSystemFeature(
                    PackageManager.FEATURE_STRONGBOX_KEYSTORE,
                )

        if (strongBoxAvailable) {
            try {
                return generateSecretKeyInternal(accountKey, strongBoxBacked = true)
            } catch (_: StrongBoxUnavailableException) {
            } catch (_: ProviderException) {
            } catch (_: InvalidAlgorithmParameterException) {
            }
        }

        return generateSecretKeyInternal(accountKey, strongBoxBacked = false)
    }

    private fun generateSecretKeyInternal(
        accountKey: String,
        strongBoxBacked: Boolean,
    ): SecretKey {
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        val builder = KeyGenParameterSpec.Builder(
            aliasFor(accountKey),
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setInvalidatedByBiometricEnrollment(true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && strongBoxBacked) {
            builder.setIsStrongBoxBacked(true)
        }

        keyGenerator.init(builder.build())
        return keyGenerator.generateKey()
    }

    private fun inspectKeyMetadata(accountKey: String): KeyMetadata {
        val key = getSecretKey(accountKey)
        if (key == null) {
            return KeyMetadata(hardwareBacked = null, strongBoxBacked = null)
        }

        return try {
            val factory = SecretKeyFactory.getInstance(
                key.algorithm,
                ANDROID_KEYSTORE,
            )
            val keyInfo = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
            val strongBoxBacked =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    keyInfo.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
                } else {
                    null
                }
            KeyMetadata(
                hardwareBacked = keyInfo.isInsideSecureHardware,
                strongBoxBacked = strongBoxBacked,
            )
        } catch (_: Exception) {
            KeyMetadata(hardwareBacked = null, strongBoxBacked = null)
        }
    }

    private fun loadRecord(activity: Activity, accountKey: String): StoredRecord? {
        val prefs = prefs(activity)
        val ivRaw = prefs.getString(prefKey(accountKey, "iv"), null) ?: return null
        val ciphertextRaw =
            prefs.getString(prefKey(accountKey, "ciphertext"), null) ?: return null

        return try {
            StoredRecord(
                iv = Base64.decode(ivRaw, Base64.NO_WRAP),
                ciphertext = Base64.decode(ciphertextRaw, Base64.NO_WRAP),
                lastUpdatedAt = prefs.getString(prefKey(accountKey, "last_updated_at"), null),
                hardwareBacked = optionalBoolean(prefs, prefKey(accountKey, "hardware_backed")),
                strongBoxBacked = optionalBoolean(prefs, prefKey(accountKey, "strong_box_backed")),
            )
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun storeRecord(
        activity: Activity,
        accountKey: String,
        iv: ByteArray,
        ciphertext: ByteArray,
        metadata: KeyMetadata,
    ): Boolean {
        val editor = prefs(activity).edit()
            .putString(
                prefKey(accountKey, "iv"),
                Base64.encodeToString(iv, Base64.NO_WRAP),
            )
            .putString(
                prefKey(accountKey, "ciphertext"),
                Base64.encodeToString(ciphertext, Base64.NO_WRAP),
            )
            .putString(prefKey(accountKey, "last_updated_at"), Instant.now().toString())
            .putInt(prefKey(accountKey, "schema_version"), 1)

        putOptionalBoolean(editor, prefKey(accountKey, "hardware_backed"), metadata.hardwareBacked)
        putOptionalBoolean(
            editor,
            prefKey(accountKey, "strong_box_backed"),
            metadata.strongBoxBacked,
        )
        return editor.commit()
    }

    private fun deleteRecord(activity: Activity, accountKey: String): Boolean {
        return prefs(activity).edit()
            .remove(prefKey(accountKey, "iv"))
            .remove(prefKey(accountKey, "ciphertext"))
            .remove(prefKey(accountKey, "last_updated_at"))
            .remove(prefKey(accountKey, "schema_version"))
            .remove(prefKey(accountKey, "hardware_backed"))
            .remove(prefKey(accountKey, "strong_box_backed"))
            .commit()
    }

    private fun deleteKeyStoreEntry(accountKey: String) {
        val keyStore = keyStore()
        val alias = aliasFor(accountKey)
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
        }
    }

    private fun deleteAllKeyStoreEntries() {
        val keyStore = keyStore()
        val aliases = keyStore.aliases()
        while (aliases.hasMoreElements()) {
            val alias = aliases.nextElement()
            if (alias.startsWith(RECOVERY_KEY_ALIAS_PREFIX)) {
                keyStore.deleteEntry(alias)
            }
        }
    }

    private fun keyStore(): KeyStore {
        return KeyStore.getInstance(ANDROID_KEYSTORE).apply {
            load(null)
        }
    }

    private fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(RECOVERY_KEY_PREFS, Context.MODE_PRIVATE)
    }

    private fun accountKeyFrom(call: MethodCall): String? {
        return call.argument<String>("accountKey")?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun aliasFor(accountKey: String): String {
        return "$RECOVERY_KEY_ALIAS_PREFIX$accountKey"
    }

    private fun prefKey(accountKey: String, field: String): String {
        return "$accountKey.$field"
    }

    private fun optionalBoolean(prefs: SharedPreferences, key: String): Boolean? {
        return if (prefs.contains(key)) prefs.getBoolean(key, false) else null
    }

    private fun putOptionalBoolean(
        editor: SharedPreferences.Editor,
        key: String,
        value: Boolean?,
    ) {
        if (value == null) {
            editor.remove(key)
        } else {
            editor.putBoolean(key, value)
        }
    }

    private fun canAuthenticateWithStrongBiometrics(activity: Activity): Boolean {
        val manager = BiometricManager.from(activity)
        return manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun biometricPromptErrorCode(errorCode: Int): String {
        return when (errorCode) {
            BiometricPrompt.ERROR_NEGATIVE_BUTTON,
            BiometricPrompt.ERROR_USER_CANCELED,
            BiometricPrompt.ERROR_CANCELED -> "auth_cancelled"
            BiometricPrompt.ERROR_NO_BIOMETRICS,
            BiometricPrompt.ERROR_HW_NOT_PRESENT,
            BiometricPrompt.ERROR_HW_UNAVAILABLE,
            BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED -> "biometrics_unavailable"
            else -> "auth_failed"
        }
    }

    private fun resultForException(result: MethodChannel.Result, exception: Exception) {
        if (isBiometryInvalidation(exception)) {
            result.error(
                "biometry_changed_or_unavailable",
                "The stored recovery key can no longer be unlocked with this biometric set.",
                null,
            )
            return
        }

        result.error("keychain_error", "Secure recovery-key operation failed.", null)
    }

    private fun isBiometryInvalidation(exception: Exception): Boolean {
        return exception is KeyPermanentlyInvalidatedException ||
            exception is UnrecoverableKeyException ||
            exception is InvalidKeyException
    }
}

private data class StoredRecord(
    val iv: ByteArray,
    val ciphertext: ByteArray,
    val lastUpdatedAt: String?,
    val hardwareBacked: Boolean?,
    val strongBoxBacked: Boolean?,
)

private data class KeyMetadata(
    val hardwareBacked: Boolean?,
    val strongBoxBacked: Boolean?,
)
