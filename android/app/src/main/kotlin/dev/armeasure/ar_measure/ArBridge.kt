package dev.armeasure.ar_measure

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Glue between the Flutter engine and the (single) AR platform view.
 *
 * Frames are sent to Dart as one [FloatArray] per camera frame, see [ArMeasureView.process]
 * for the layout. A single flat array is the cheapest thing the standard codec can carry.
 */
class ArBridge : EventChannel.StreamHandler {
    companion object {
        const val VIEW_TYPE = "armeasure/view"
        const val CONTROL_CHANNEL = "armeasure/control"
        const val FRAMES_CHANNEL = "armeasure/frames"
    }

    @Volatile
    var view: ArMeasureView? = null

    private val main = Handler(Looper.getMainLooper())
    @Volatile
    private var sink: EventChannel.EventSink? = null

    // Drop frames instead of queueing them if Dart can't keep up.
    private val inFlight = AtomicBoolean(false)

    fun publish(frame: FloatArray) {
        if (sink == null || !inFlight.compareAndSet(false, true)) return
        main.post {
            try {
                sink?.success(frame)
            } finally {
                inFlight.set(false)
            }
        }
    }

    fun resume() {
        view?.resume()
    }

    fun pause() {
        view?.pause()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}

class ArViewFactory(private val bridge: ArBridge) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val view = ArMeasureView(context, bridge)
        bridge.view = view
        return view
    }
}
