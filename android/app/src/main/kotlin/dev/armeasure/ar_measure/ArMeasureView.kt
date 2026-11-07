package dev.armeasure.ar_measure

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import com.google.ar.core.Anchor
import com.google.ar.core.CameraConfig
import com.google.ar.core.CameraConfigFilter
import com.google.ar.core.Config
import com.google.ar.core.DepthPoint
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.Point
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingFailureReason
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.EnumSet
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.sqrt

/**
 * Hosts the ARCore session and the camera preview. It owns *all* AR state; Flutter only
 * receives a flat float array per frame (see [process]) and draws the overlay itself.
 *
 * Everything that touches [Session] runs on the GL thread (via [GLSurfaceView.queueEvent])
 * because the session is not thread safe.
 *
 * ## Accuracy measures implemented here
 *  1. Hardware depth (ToF) camera config is requested when the device has one.
 *  2. Depth API (`DepthMode.AUTOMATIC`) is enabled when supported, so hit-tests land on real
 *     geometry rather than sparse feature points.
 *  3. Only hits on tracked, in-polygon planes, depth points and oriented feature points are used.
 *  4. When a depth point and a detected plane agree within 2 cm the (smoother) plane wins.
 *  5. The reported point is the per-axis *median* of the last few hits, which removes outliers
 *     and jitter without the lag of a low-pass filter. The same value is what gets placed.
 *  6. Points are anchored to the trackable they hit, so ARCore keeps correcting them as its
 *     map of the world improves.
 *  7. Tracking state / failure reason, hit distance and stability are reported so the UI can
 *     tell the user when a measurement would be unreliable.
 */
class ArMeasureView(private val context: Context, private val bridge: ArBridge) :
    PlatformView, GLSurfaceView.Renderer {

    private companion object {
        // Layout of the float array sent to Dart. Keep in sync with lib/ar/ar_frame.dart.
        const val HEADER = 53
        const val NEAR = 0.05f
        const val FAR = 30f

        const val STATE_NONE = 0f
        const val STATE_TRACKING = 1f
        const val STATE_PAUSED = 2f
        const val STATE_ERROR = 3f

        const val HIT_NONE = 0f
        const val HIT_PLANE = 1f
        const val HIT_DEPTH = 2f
        const val HIT_POINT = 3f

        const val MAX_ANCHORS = 96
        const val SAMPLE_COUNT = 5
        const val SAMPLE_MAX_AGE_NS = 250_000_000L
        const val SAMPLE_GATHER_RADIUS = 0.03f // metres
        const val PLANE_PREFERENCE_WINDOW = 0.02f // metres
        const val STABLE_DEVIATION = 0.012f // metres

        // ARCore needs real sideways motion (parallax) to lock in metric scale.
        const val SCAN_KEYFRAME_STEP = 0.03f // metres between counted camera positions
        const val SCAN_REQUIRED = 0.6f // metres of camera travel before measuring is allowed
    }

    private class Sample(val pos: FloatArray, val timestamp: Long)

    private val glView = GLSurfaceView(context)
    private val background = BackgroundRenderer()
    private val main = Handler(Looper.getMainLooper())

    private var session: Session? = null
    private var sessionFailed = false
    private var depthLevel = 0f // 0 none, 1 software depth, 2 hardware (ToF) depth
    private var resumed = false

    private var viewportChanged = false
    private var viewWidth = 0
    private var viewHeight = 0

    private val anchors = LinkedHashMap<Int, Anchor>()
    private var nextAnchorId = 1

    private val samples = ArrayList<Sample>()
    private var lastHit: HitResult? = null
    private var lastHitPos: FloatArray? = null // median position of the latest hit

    private var scanPath = 0f
    private var scanKeyframe: FloatArray? = null

    init {
        glView.preserveEGLContextOnPause = true
        glView.setEGLContextClientVersion(2)
        glView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        glView.setRenderer(this)
        glView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        glView.setWillNotDraw(false)

        try {
            val s = Session(context)
            configure(s)
            session = s
        } catch (e: Exception) {
            sessionFailed = true
        }
        // The platform view is created while the activity is already resumed.
        resume()
    }

    private fun configure(s: Session) {
        // Prefer a camera config backed by a hardware depth sensor (ToF / stereo) when present.
        try {
            val filter = CameraConfigFilter(s)
                .setDepthSensorUsage(EnumSet.of(CameraConfig.DepthSensorUsage.REQUIRE_AND_USE))
            val withSensor = s.getSupportedCameraConfigs(filter)
            if (withSensor.isNotEmpty()) {
                s.cameraConfig = withSensor[0]
                depthLevel = 2f
            }
        } catch (e: Throwable) {
        }

        val config = Config(s)
        if (s.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
            config.depthMode = Config.DepthMode.AUTOMATIC
            if (depthLevel == 0f) depthLevel = 1f
        }
        config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
        config.focusMode = Config.FocusMode.AUTO
        config.lightEstimationMode = Config.LightEstimationMode.DISABLED // not needed, saves work
        config.updateMode = Config.UpdateMode.BLOCKING
        s.configure(config)
    }

    // --- Lifecycle ---------------------------------------------------------------------------

    fun resume() {
        val s = session ?: return
        if (resumed) return
        try {
            s.resume()
            resumed = true
            viewportChanged = true
            glView.onResume()
        } catch (e: CameraNotAvailableException) {
            sessionFailed = true
        } catch (e: Exception) {
            sessionFailed = true
        }
    }

    fun pause() {
        if (!resumed) return
        resumed = false
        glView.onPause()
        session?.pause()
    }

    override fun getView(): View = glView

    override fun dispose() {
        pause()
        glView.queueEvent {
            anchors.values.forEach { it.detach() }
            anchors.clear()
        }
        session?.close()
        session = null
        if (bridge.view === this) bridge.view = null
    }

    // --- Commands from Flutter ---------------------------------------------------------------

    /**
     * Drops an anchor at the current reticle position. Replies with the new anchor id,
     * or -1 when there is no reliable surface under the reticle.
     */
    fun place(snapId: Int?, result: MethodChannel.Result) {
        glView.queueEvent {
            var id = -1
            try {
                val s = session
                if (s != null && anchors.size < MAX_ANCHORS) {
                    val snap = snapId?.let { anchors[it] }
                    val pos = lastHitPos
                    val hit = lastHit
                    val anchor: Anchor? = when {
                        snap != null && snap.trackingState == TrackingState.TRACKING ->
                            s.createAnchor(snap.pose)
                        hit != null && pos != null -> createAnchorAt(s, hit, pos)
                        else -> null
                    }
                    if (anchor != null) {
                        id = nextAnchorId++
                        anchors[id] = anchor
                    }
                }
            } catch (e: Exception) {
                id = -1
            }
            main.post { result.success(id) }
        }
    }

    private fun createAnchorAt(s: Session, hit: HitResult, pos: FloatArray): Anchor {
        val pose = Pose.makeTranslation(pos[0], pos[1], pos[2])
        return try {
            // Attached to the trackable => ARCore refines it as tracking improves.
            hit.trackable.createAnchor(pose)
        } catch (e: Exception) {
            s.createAnchor(pose)
        }
    }

    fun remove(id: Int) {
        glView.queueEvent { anchors.remove(id)?.detach() }
    }

    fun clear() {
        glView.queueEvent {
            anchors.values.forEach { it.detach() }
            anchors.clear()
        }
    }

    // --- GL renderer -------------------------------------------------------------------------

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        background.createOnGlThread()
        session?.setCameraTextureName(background.textureId)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        viewWidth = width
        viewHeight = height
        viewportChanged = true
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val s = session
        if (s == null || sessionFailed) {
            bridge.publish(FloatArray(HEADER).also { it[0] = STATE_ERROR })
            return
        }
        if (!resumed || viewWidth == 0 || viewHeight == 0) return

        if (viewportChanged) {
            s.setDisplayGeometry(displayRotation(), viewWidth, viewHeight)
            viewportChanged = false
        }

        val frame: Frame = try {
            s.update()
        } catch (e: CameraNotAvailableException) {
            return
        } catch (e: Exception) {
            return
        }

        background.draw(frame)
        process(frame)
    }

    @Suppress("DEPRECATION")
    private fun displayRotation(): Int =
        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.rotation

    // --- Per-frame work ----------------------------------------------------------------------

    private fun process(frame: Frame) {
        val camera = frame.camera
        val tracking = camera.trackingState == TrackingState.TRACKING
        val camPos = camera.pose.translation

        // Camera travel: only counts steps between positions >= 3 cm apart, so sensor
        // noise while holding still never adds up.
        if (tracking) {
            val key = scanKeyframe
            if (key == null) {
                scanKeyframe = camPos
            } else {
                val step = dist(key, camPos)
                if (step >= SCAN_KEYFRAME_STEP) {
                    scanPath += step
                    scanKeyframe = camPos
                }
            }
        }

        // Forget anchors ARCore has given up on.
        val iter = anchors.entries.iterator()
        while (iter.hasNext()) {
            val e = iter.next()
            if (e.value.trackingState == TrackingState.STOPPED) {
                e.value.detach()
                iter.remove()
            }
        }

        var hitKind = HIT_NONE
        var hit: HitResult? = null
        if (tracking) {
            val picked = pickHit(frame)
            if (picked != null) {
                hit = picked.first
                hitKind = picked.second
            }
        }

        // Rolling window of recent hits => median position + stability estimate.
        var median: FloatArray? = null
        var stability = 0f
        if (hit != null) {
            val p = hit.hitPose.translation
            samples.removeAll { frame.timestamp - it.timestamp > SAMPLE_MAX_AGE_NS }
            // A big jump means the user moved to a different surface: start over.
            if (samples.isNotEmpty() && dist(samples.last().pos, p) > SAMPLE_GATHER_RADIUS * 2) {
                samples.clear()
            }
            samples.add(Sample(p.copyOf(), frame.timestamp))
            while (samples.size > SAMPLE_COUNT) samples.removeAt(0)

            val near = samples.filter { dist(it.pos, p) <= SAMPLE_GATHER_RADIUS }
            val m = floatArrayOf(
                medianOf(near.map { it.pos[0] }),
                medianOf(near.map { it.pos[1] }),
                medianOf(near.map { it.pos[2] }),
            )
            if (near.size >= 3) {
                val maxDev = near.maxOf { dist(it.pos, m) }
                stability = (1f - maxDev / STABLE_DEVIATION).coerceIn(0f, 1f)
            }
            median = m
            lastHit = hit
            lastHitPos = m
        } else {
            samples.clear()
            lastHit = null
            lastHitPos = null
        }

        val live = anchors.filterValues { it.trackingState == TrackingState.TRACKING }
        val out = FloatArray(HEADER + live.size * 4)
        out[0] = when {
            sessionFailed -> STATE_ERROR
            tracking -> STATE_TRACKING
            camera.trackingState == TrackingState.PAUSED -> STATE_PAUSED
            else -> STATE_NONE
        }
        out[1] = failureCode(camera.trackingFailureReason)
        out[2] = depthLevel
        out[3] = hitKind
        if (hit != null && median != null) {
            out[4] = dist(median, camPos)
            out[5] = median[0]; out[6] = median[1]; out[7] = median[2]
            val n = hit.hitPose.getTransformedAxis(1, 1f) // surface normal (pose +Y)
            out[8] = n[0]; out[9] = n[1]; out[10] = n[2]
        }
        out[11] = stability
        out[12] = live.size.toFloat()
        out[45] = viewWidth.toFloat()
        out[46] = viewHeight.toFloat()
        try {
            val cc = session?.cameraConfig
            if (cc != null) {
                out[47] = cc.imageSize.width.toFloat(); out[48] = cc.imageSize.height.toFloat()
                out[49] = cc.textureSize.width.toFloat(); out[50] = cc.textureSize.height.toFloat()
            }
        } catch (e: Exception) {
        }
        out[51] = displayRotation().toFloat()
        out[52] = (scanPath / SCAN_REQUIRED).coerceIn(0f, 1f)
        camera.getViewMatrix(out, 13)
        camera.getProjectionMatrix(out, 29, NEAR, FAR)
        var i = HEADER
        for ((id, anchor) in live) {
            val t = anchor.pose.translation
            out[i] = id.toFloat(); out[i + 1] = t[0]; out[i + 2] = t[1]; out[i + 3] = t[2]
            i += 4
        }
        bridge.publish(out)
    }

    /**
     * Hit-tests the screen centre and returns the best result with its kind.
     *
     * Results are sorted by distance, so the first usable result is what is physically
     * closest to the camera (e.g. the top of a box, not the table behind it). If that is a
     * depth/feature point and a detected plane lies within [PLANE_PREFERENCE_WINDOW] of it,
     * the plane hit is used because planes are much less noisy.
     */
    private fun pickHit(frame: Frame): Pair<HitResult, Float>? {
        var first: HitResult? = null
        var firstKind = HIT_NONE
        for (hit in frame.hitTest(viewWidth / 2f, viewHeight / 2f)) {
            val t = hit.trackable
            val kind = when {
                t is Plane && t.trackingState == TrackingState.TRACKING &&
                    t.isPoseInPolygon(hit.hitPose) -> HIT_PLANE
                t is DepthPoint && t.trackingState == TrackingState.TRACKING -> HIT_DEPTH
                t is Point && t.trackingState == TrackingState.TRACKING &&
                    t.orientationMode == Point.OrientationMode.ESTIMATED_SURFACE_NORMAL -> HIT_POINT
                else -> HIT_NONE
            }
            if (kind == HIT_NONE) continue
            val f = first
            if (f == null) {
                first = hit
                firstKind = kind
                if (kind == HIT_PLANE) break
            } else if (hit.distance - f.distance > PLANE_PREFERENCE_WINDOW) {
                break
            } else if (kind == HIT_PLANE) {
                return hit to HIT_PLANE
            }
        }
        return first?.let { it to firstKind }
    }

    private fun failureCode(r: TrackingFailureReason): Float = when (r) {
        TrackingFailureReason.NONE -> 0f
        TrackingFailureReason.BAD_STATE -> 1f
        TrackingFailureReason.INSUFFICIENT_LIGHT -> 2f
        TrackingFailureReason.EXCESSIVE_MOTION -> 3f
        TrackingFailureReason.INSUFFICIENT_FEATURES -> 4f
        TrackingFailureReason.CAMERA_UNAVAILABLE -> 5f
        else -> 1f
    }

    private fun dist(a: FloatArray, b: FloatArray): Float {
        val dx = a[0] - b[0]
        val dy = a[1] - b[1]
        val dz = a[2] - b[2]
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private fun medianOf(values: List<Float>): Float {
        val sorted = values.sorted()
        val n = sorted.size
        return if (n % 2 == 1) sorted[n / 2] else (sorted[n / 2 - 1] + sorted[n / 2]) / 2f
    }
}
