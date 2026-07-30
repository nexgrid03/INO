package com.example.inoapp

import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by the local_auth
// plugin - its BiometricPrompt needs a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "ino/biometric"
    private val secureChannelName = "ino/secure_screen"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openEnrollment" -> {
                        openBiometricEnrollment()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Screenshot / screen-recording protection for sensitive screens (the
        // view-once document viewer). FLAG_SECURE is enforced by the OS: the
        // system refuses to screenshot the window, blanks it in screen
        // recordings and in the recents thumbnail, and blocks mirroring to
        // non-secure displays.
        //
        // Scoped, not global: it is switched on only while such a screen is up,
        // so nothing about the rest of the app changes.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        setSecure(true)
                        result.success(true)
                    }
                    "disable" -> {
                        setSecure(false)
                        result.success(true)
                    }
                    // Android has no "is being captured" query - FLAG_SECURE
                    // already blanks any capture, so there is nothing to report.
                    "isCaptured" -> result.success(false)
                    else -> result.notImplemented()
                }
            }
    }

    /// Adds or clears FLAG_SECURE. Window flags must be touched on the UI
    /// thread; MethodChannel handlers already run there, but runOnUiThread keeps
    /// it correct if that ever changes.
    private fun setSecure(secure: Boolean) {
        runOnUiThread {
            if (secure) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }

    /// Opens the OS biometric-enrollment screen so the user can register a
    /// fingerprint / face. We never build a custom enrollment UI. Falls back
    /// gracefully on older Android versions / OEM variations.
    private fun openBiometricEnrollment() {
        val intent = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                Intent(Settings.ACTION_BIOMETRIC_ENROLL).apply {
                    // BIOMETRIC_STRONG (0x0F) | DEVICE_CREDENTIAL (0x8000)
                    putExtra(
                        Settings.EXTRA_BIOMETRIC_AUTHENTICATORS_ALLOWED,
                        0x0000000F or 0x00008000,
                    )
                }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ->
                Intent(Settings.ACTION_FINGERPRINT_ENROLL)
            else -> Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
            } catch (e2: Exception) {
                startActivity(Intent(Settings.ACTION_SETTINGS))
            }
        }
    }
}
