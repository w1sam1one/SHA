package se.sha.sha

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import se.sha.sha.app.AppSignatureChannel
import se.sha.sha.keystore.KeystoreChannel
import se.sha.sha.lock.AppLockChannel

class MainActivity : FlutterActivity() {
    private var appLock: AppLockChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep messages and identity out of screenshots, screen recordings
        // and the recent-apps thumbnail.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KeystoreChannel.NAME)
            .setMethodCallHandler(KeystoreChannel(applicationContext))
        // The app lock (F4) needs the activity: the prompt is shown over it.
        val lock = AppLockChannel(this)
        appLock = lock
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AppLockChannel.NAME)
            .setMethodCallHandler(lock)
        // The app's own signing certificate for "Teknisk information" (F14).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AppSignatureChannel.NAME)
            .setMethodCallHandler(AppSignatureChannel(applicationContext))
    }

    // The PIN screen on Android 9-10 answers through this.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (appLock?.onActivityResult(requestCode, resultCode) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
