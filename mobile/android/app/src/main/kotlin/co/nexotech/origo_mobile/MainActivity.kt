package co.nexotech.origo_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream

class MainActivity : FlutterActivity(), RecognitionListener {
    companion object {
        private const val VOICE_CHANNEL = "co.nexotech.origo/offline_voice"
        private const val NETWORK_CHANNEL = "co.nexotech.origo/network"
        private const val PERMISSION_REQUEST_AUDIO = 1001
        private const val MODEL_ASSET_ZIP = "model-es.zip"
        private const val MODEL_MARKER_FILE = ".origo_vosk_es_ready"
    }

    private var voiceChannel: MethodChannel? = null
    private var networkChannel: MethodChannel? = null
    private val executor = Executors.newSingleThreadExecutor()

    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    @Volatile
    private var model: Model? = null
    @Volatile
    private var isModelLoading = false

    private var speechService: SpeechService? = null
    private var pendingStartAfterPermission = false
    private val accumulatedText = StringBuilder()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Canal 1: Voz 100% Offline (Vosk)
        voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL)
        voiceChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initModel" -> {
                    ensureModelLoaded()
                    result.success(model != null)
                }
                "startListening" -> {
                    startOfflineListening(result)
                }
                "stopListening" -> {
                    stopOfflineListening()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Canal 2: Monitoreo real de conectividad Android (Wi-Fi / Datos / Modo Avión)
        networkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_CHANNEL)
        networkChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isOnline" -> result.success(isCurrentlyOnline())
                else -> result.notImplemented()
            }
        }
        registerNetworkMonitor()

        // Precargar modelo acústico en segundo plano al abrir la app
        ensureModelLoaded()
    }

    private fun isCurrentlyOnline(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val active = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(active) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))
    }

    private fun registerNetworkMonitor() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        connectivityManager = cm
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                sendNetworkEvent(true)
            }

            override fun onLost(network: Network) {
                sendNetworkEvent(isCurrentlyOnline())
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                val online = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                sendNetworkEvent(online)
            }
        }
        networkCallback = callback
        try {
            cm.registerDefaultNetworkCallback(callback)
        } catch (_: Exception) {}
    }

    private fun sendNetworkEvent(isOnline: Boolean) {
        runOnUiThread {
            networkChannel?.invokeMethod("onConnectivityChanged", isOnline)
        }
    }

    private fun ensureModelLoaded() {
        if (model != null) {
            sendVoiceEvent("onModelStatus", "ready")
            return
        }
        if (isModelLoading) return
        isModelLoading = true
        sendVoiceEvent("onModelStatus", "loading")

        executor.execute {
            try {
                val targetBaseDir = File(filesDir, "vosk-model-es")
                val marker = File(targetBaseDir, MODEL_MARKER_FILE)
                if (!marker.exists()) {
                    if (targetBaseDir.exists()) targetBaseDir.deleteRecursively()
                    targetBaseDir.mkdirs()
                    unzipAssetToDir(MODEL_ASSET_ZIP, targetBaseDir)
                    marker.createNewFile()
                }
                val modelRoot = findModelRoot(targetBaseDir) ?: targetBaseDir
                model = Model(modelRoot.absolutePath)
                isModelLoading = false
                sendVoiceEvent("onModelStatus", "ready")
            } catch (e: Exception) {
                isModelLoading = false
                sendVoiceEvent("onModelStatus", "error:${e.message ?: "Error cargando modelo offline"}")
            }
        }
    }

    private fun findModelRoot(dir: File): File? {
        if (File(dir, "conf").exists() || File(dir, "am").exists()) return dir
        dir.listFiles()?.forEach { child ->
            if (child.isDirectory) {
                val found = findModelRoot(child)
                if (found != null) return found
            }
        }
        return null
    }

    private fun unzipAssetToDir(assetName: String, destDir: File) {
        val canonicalDest = destDir.canonicalPath
        assets.open(assetName).use { rawStream ->
            ZipInputStream(BufferedInputStream(rawStream)).use { zis ->
                val buffer = ByteArray(16384)
                var entry = zis.nextEntry
                while (entry != null) {
                    val outFile = File(destDir, entry.name)
                    if (!outFile.canonicalPath.startsWith(canonicalDest)) {
                        throw SecurityException("Zip entry outside target dir")
                    }
                    if (entry.isDirectory) {
                        outFile.mkdirs()
                    } else {
                        outFile.parentFile?.mkdirs()
                        FileOutputStream(outFile).use { fos ->
                            var len: Int
                            while (zis.read(buffer).also { len = it } > 0) {
                                fos.write(buffer, 0, len)
                            }
                        }
                    }
                    zis.closeEntry()
                    entry = zis.nextEntry
                }
            }
        }
    }

    private fun startOfflineListening(result: MethodChannel.Result) {
        val hasPerm = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasPerm) {
            pendingStartAfterPermission = true
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                PERMISSION_REQUEST_AUDIO
            )
            result.success("requesting_permission")
            return
        }

        val loadedModel = model
        if (loadedModel == null) {
            ensureModelLoaded()
            result.success("loading_model")
            return
        }

        try {
            stopSpeechServiceOnly()
            accumulatedText.clear()
            val recognizer = Recognizer(loadedModel, 16000.0f)
            speechService = SpeechService(recognizer, 16000.0f)
            speechService?.startListening(this)
            result.success("listening")
        } catch (e: Exception) {
            sendVoiceEvent("onError", "Error iniciando micrófono: ${e.message}")
            result.success("error")
        }
    }

    private fun stopOfflineListening() {
        speechService?.stop()
    }

    private fun stopSpeechServiceOnly() {
        speechService?.stop()
        speechService?.shutdown()
        speechService = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_AUDIO) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted && pendingStartAfterPermission) {
                pendingStartAfterPermission = false
                val loadedModel = model
                if (loadedModel != null) {
                    try {
                        stopSpeechServiceOnly()
                        accumulatedText.clear()
                        val recognizer = Recognizer(loadedModel, 16000.0f)
                        speechService = SpeechService(recognizer, 16000.0f)
                        speechService?.startListening(this)
                        sendVoiceEvent("onListeningStarted", true)
                    } catch (e: Exception) {
                        sendVoiceEvent("onError", "No se pudo abrir el micrófono: ${e.message}")
                    }
                }
            } else {
                pendingStartAfterPermission = false
                sendVoiceEvent("onError", "Permiso de micrófono denegado.")
            }
        }
    }

    override fun onPartialResult(hypothesis: String?) {
        if (hypothesis.isNullOrBlank()) return
        try {
            val partial = JSONObject(hypothesis).optString("partial", "").trim()
            val combined = buildCombined(partial)
            if (combined.isNotEmpty()) {
                sendVoiceEvent("onPartial", combined)
            }
        } catch (_: Exception) {}
    }

    override fun onResult(hypothesis: String?) {
        if (hypothesis.isNullOrBlank()) return
        try {
            val text = JSONObject(hypothesis).optString("text", "").trim()
            if (text.isNotEmpty()) {
                if (accumulatedText.isNotEmpty()) accumulatedText.append(' ')
                accumulatedText.append(text)
                sendVoiceEvent("onPartial", accumulatedText.toString())
            }
        } catch (_: Exception) {}
    }

    override fun onFinalResult(hypothesis: String?) {
        try {
            if (!hypothesis.isNullOrBlank()) {
                val text = JSONObject(hypothesis).optString("text", "").trim()
                if (text.isNotEmpty()) {
                    if (accumulatedText.isNotEmpty()) accumulatedText.append(' ')
                    accumulatedText.append(text)
                }
            }
        } catch (_: Exception) {}

        val finalPhrase = accumulatedText.toString().trim()
        accumulatedText.clear()
        speechService?.shutdown()
        speechService = null
        sendVoiceEvent("onFinal", finalPhrase)
    }

    override fun onError(exception: Exception?) {
        speechService?.shutdown()
        speechService = null
        sendVoiceEvent("onError", exception?.message ?: "Error en reconocimiento de voz")
    }

    override fun onTimeout() {
        stopOfflineListening()
    }

    private fun buildCombined(partial: String): String {
        val base = accumulatedText.toString().trim()
        if (base.isEmpty()) return partial
        if (partial.isEmpty()) return base
        return "$base $partial"
    }

    private fun sendVoiceEvent(method: String, argument: Any?) {
        runOnUiThread {
            voiceChannel?.invokeMethod(method, argument)
        }
    }

    override fun onDestroy() {
        networkCallback?.let { cb ->
            try { connectivityManager?.unregisterNetworkCallback(cb) } catch (_: Exception) {}
        }
        stopSpeechServiceOnly()
        model?.close()
        model = null
        executor.shutdownNow()
        super.onDestroy()
    }
}
