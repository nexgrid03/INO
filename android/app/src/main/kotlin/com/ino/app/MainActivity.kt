package com.ino.app

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

// FlutterFragmentActivity (not FlutterActivity) is required by the local_auth
// plugin - its BiometricPrompt needs a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "ino/biometric"
    private val secureChannelName = "ino/secure_screen"
    private val upiChannelName = "ino/upi_apps"

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

        // Payment-app discovery for scanned UPI QRs (UpiAppService.dart). The
        // list comes from the OS, not from a hard-coded table, so any UPI app
        // the user has installed shows up - including ones this code has never
        // heard of.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, upiChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "list" -> result.success(listUpiApps())
                    "launch" -> {
                        val id = call.argument<String>("id")
                        val uri = call.argument<String>("uri")
                        if (id.isNullOrEmpty() || uri.isNullOrEmpty()) {
                            result.success(false)
                        } else {
                            result.success(launchUpiApp(id, uri))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Every installed app that can handle a `upi://pay` link, with its real
    /// label and launcher icon.
    ///
    /// Requires the matching `<queries>` entry in AndroidManifest.xml - without
    /// it Android 11+ package visibility hides every result and this silently
    /// returns an empty list.
    private fun listUpiApps(): List<Map<String, Any?>> {
        val pm = packageManager
        // Two probes, merged. A bare `upi://pay` misses apps whose intent
        // filter is written against a fully-formed payment URI, and the
        // realistic one misses any app registered for the bare action - so ask
        // for both and union the results.
        val probes = listOf(
            "upi://pay",
            "upi://pay?pa=test@upi&pn=Test&cu=INR",
        )

        val seen = mutableSetOf<String>()
        val apps = mutableListOf<Map<String, Any?>>()
        for (probeUri in probes) {
            val probe = Intent(Intent.ACTION_VIEW, Uri.parse(probeUri))
            val matches = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.queryIntentActivities(probe, PackageManager.ResolveInfoFlags.of(0L))
                } else {
                    @Suppress("DEPRECATION")
                    pm.queryIntentActivities(probe, 0)
                }
            } catch (e: Exception) {
                continue
            }
            for (info in matches) {
                val pkg = info.activityInfo?.packageName ?: continue
                // An app can register several matching activities, and the two
                // probes overlap; the user thinks in apps, so collapse to one
                // entry each.
                if (!seen.add(pkg)) continue
                apps.add(
                    mapOf(
                        "id" to pkg,
                        "name" to info.loadLabel(pm).toString(),
                        "icon" to iconPng(info.loadIcon(pm)),
                    )
                )
            }
        }
        return apps
    }

    /// Rasterises a launcher icon to PNG bytes for the Flutter picker. Drawing
    /// into a fixed-size canvas (rather than casting to BitmapDrawable) is what
    /// makes adaptive icons work - they are layered drawables with no single
    /// backing bitmap.
    private fun iconPng(drawable: Drawable?, size: Int = 144): ByteArray? {
        if (drawable == null) return null
        return try {
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            bitmap.recycle()
            stream.toByteArray()
        } catch (e: Exception) {
            // An icon we can't render is not worth failing the whole list for -
            // the picker falls back to a lettered avatar.
            null
        }
    }

    /// Opens the payment URI in ONE named app. `setPackage` is the whole point:
    /// without it Android would show its own chooser and the in-app picker the
    /// user just used would have meant nothing.
    private fun launchUpiApp(packageName: String, uri: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                setPackage(packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
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
