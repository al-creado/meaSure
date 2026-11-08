package dev.armeasure.ar_measure

import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val bridge = ArBridge()
    private var installRequested = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        flutterEngine.platformViewsController.registry
            .registerViewFactory(ArBridge.VIEW_TYPE, ArViewFactory(bridge))

        EventChannel(messenger, ArBridge.FRAMES_CHANNEL).setStreamHandler(bridge)

        MethodChannel(messenger, ArBridge.CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureArCore" -> result.success(ensureArCore())
                "place" -> {
                    val view = bridge.view
                    if (view == null) result.success(-1)
                    else view.place(call.argument<Int>("snapId"), result)
                }
                "capture" -> {
                    val view = bridge.view
                    if (view == null) result.success(null) else view.capture(result)
                }
                "remove" -> {
                    bridge.view?.remove(call.argument<Int>("id") ?: -1)
                    result.success(null)
                }
                "clear" -> {
                    bridge.view?.clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Returns "ready", "installing", "declined" or "unsupported". */
    private fun ensureArCore(): String {
        return try {
            val availability = ArCoreApk.getInstance().checkAvailability(this)
            if (availability.isUnsupported) return "unsupported"
            when (ArCoreApk.getInstance().requestInstall(this, !installRequested)) {
                ArCoreApk.InstallStatus.INSTALLED -> "ready"
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    installRequested = true
                    "installing"
                }
            }
        } catch (e: UnavailableUserDeclinedInstallationException) {
            "declined"
        } catch (e: UnavailableDeviceNotCompatibleException) {
            "unsupported"
        } catch (e: Exception) {
            "unsupported"
        }
    }

    override fun onResume() {
        super.onResume()
        bridge.resume()
    }

    override fun onPause() {
        bridge.pause()
        super.onPause()
    }
}
