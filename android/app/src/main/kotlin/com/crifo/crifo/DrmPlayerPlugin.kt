package com.crifo.crifo

import android.content.Context
import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.hls.HlsMediaSource
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream

class DrmPlayerPlugin(
    private val messenger: DartExecutor,
    private val textureRegistry: TextureRegistry,
    private val context: Context
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.crifo.crifo/drm_player")
    private val players = mutableMapOf<Int, ExoPlayer>()
    private val entries = mutableMapOf<Int, TextureRegistry.SurfaceTextureEntry>()
    private var nextId = 0

    fun start() {
        channel.setMethodCallHandler(this)
    }

    fun destroy() {
        channel.setMethodCallHandler(null)
        players.keys.toList().forEach { disposePlayer(it) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> {
                val url = call.argument<String>("url") ?: ""
                if (url.isEmpty()) {
                    result.error("INVALID_ARG", "url is required", null)
                    return
                }
                val api = call.argument<String>("api") ?: ""
                try {
                    val data = createNativePlayer(url, api)
                    result.success(data)
                } catch (e: Exception) {
                    result.error("PLAY_ERROR", e.message ?: "Unknown error", null)
                }
            }
            "playHls" -> {
                val url = call.argument<String>("url") ?: ""
                if (url.isEmpty()) {
                    result.error("INVALID_ARG", "url is required", null)
                    return
                }
                try {
                    val data = createNativePlayer(url, "")
                    result.success(data)
                } catch (e: Exception) {
                    result.error("PLAY_ERROR", e.message ?: "Unknown error", null)
                }
            }
            "stop" -> {
                val id = call.argument<Int>("id") ?: -1
                stopPlayer(id)
                result.success(null)
            }
            "dispose" -> {
                val id = call.argument<Int>("id") ?: -1
                disposePlayer(id)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun createNativePlayer(url: String, api: String): Map<String, Any> {
        val id = nextId++
        val entry = textureRegistry.createSurfaceTexture()
        val surfaceTexture = entry.surfaceTexture()
        surfaceTexture.setDefaultBufferSize(1920, 1080)
        val surface = Surface(surfaceTexture)

        val mediaItemBuilder = MediaItem.Builder().setUri(url)

        if (api.isNotEmpty()) {
            val parts = api.split(":")
            if (parts.size == 2) {
                try {
                    val keyId = hexToBytes(parts[0])
                    val key = hexToBytes(parts[1])
                    if (keyId.size == 16 && key.size == 16) {
                        val keySetId = provisionOfflineKey(keyId, key)
                        if (keySetId != null) {
                            mediaItemBuilder
                                .setDrmUuid(C.WIDEVINE_UUID)
                                .setDrmKeySetId(keySetId)
                                .setDrmPlayClearContentWithoutKey(true)
                                .setDrmMultiSession(false)
                        }
                    }
                } catch (_: Exception) {
                    // DRM provisioning failed — play without DRM
                }
            }
        }

        val mediaItem = mediaItemBuilder.build()
        val renderersFactory = DefaultRenderersFactory(context)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
        val player = ExoPlayer.Builder(context, renderersFactory).build()

        player.setVideoSurface(surface)
        player.playWhenReady = true

        // Use explicit HLS source for .m3u8 to avoid codec detection from playlist headers
        if (url.contains(".m3u8")) {
            val httpFactory = DefaultHttpDataSource.Factory()
                .setUserAgent("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36")
                .setConnectTimeoutMs(10000)
                .setReadTimeoutMs(15000)
            val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
            val hlsSource = HlsMediaSource.Factory(dataSourceFactory)
                .setAllowChunklessPreparation(false)
                .createMediaSource(mediaItem)
            player.setMediaSource(hlsSource)
        } else {
            player.setMediaItem(mediaItem)
        }
        player.prepare()

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY) {
                    channel.invokeMethod("onReady", id)

                    // Log track info for debugging
                    val tracks = player.currentTracks
                    if (tracks != null) {
                        for (group in tracks.groups) {
                            val track = group.mediaTrackGroup?.getFormat(0)
                            if (track != null) {
                                Log.i("CriFO", "Track: ${track.sampleMimeType} ${track.codecs} ${track.width}x${track.height}")
                            }
                        }
                    }

                    // Check video after 5s — give HLS time to load first segment
                    Handler(Looper.getMainLooper()).postDelayed({
                        val p = players[id] ?: return@postDelayed
                        val fmt = p.videoFormat
                        val size = p.videoSize
                        if (fmt == null) {
                            Log.w("CriFO", "No video track detected for stream")
                            channel.invokeMethod(
                                "onError",
                                mapOf("id" to id, "error" to "No video track in this stream")
                            )
                        } else if (size.width <= 0 && size.height <= 0) {
                            Log.w("CriFO", "Video codec ${fmt.sampleMimeType}/${fmt.codecs} not supported")
                            channel.invokeMethod(
                                "onError",
                                mapOf("id" to id, "error" to "Video codec not supported on this device")
                            )
                        } else {
                            Log.i("CriFO", "Video OK: ${fmt.sampleMimeType} ${size.width}x${size.height}")
                        }
                    }, 5000)
                }
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                // No longer report error here — wait for the delayed check instead
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e("CriFO", "Player error: ${error.message}")
                channel.invokeMethod(
                    "onError",
                    mapOf("id" to id, "error" to (error.message ?: "Unknown"))
                )
            }
        })

        players[id] = player
        entries[id] = entry
        return mapOf("id" to id, "textureId" to entry.id())
    }

    private fun provisionOfflineKey(keyId: ByteArray, key: ByteArray): ByteArray? {
        return try {
            val mediaDrm = FrameworkMediaDrm.newInstance(C.WIDEVINE_UUID)
            val sessionId = mediaDrm.openSession()
            val licenseResponse = buildWidevineLicense(keyId, key)
            val keySetId = mediaDrm.provideKeyResponse(sessionId, licenseResponse)
            mediaDrm.closeSession(sessionId)
            mediaDrm.release()
            keySetId
        } catch (_: Exception) {
            null
        }
    }

    private fun buildWidevineLicense(keyId: ByteArray, key: ByteArray): ByteArray {
        val keyMsg = buildKeyMessage(keyId, key)
        val policyMsg = buildPolicyMessage()

        val now = System.currentTimeMillis() / 1000L
        val end = now + 315360000L // +10 years

        val bos = ByteArrayOutputStream()
        encodeBytes(bos, 2, policyMsg)
        encodeBytes(bos, 3, keyMsg)
        encodeVarint(bos, 4, now)
        encodeVarint(bos, 5, end)
        encodeVarint(bos, 6, 1L) // is_offline = true
        return bos.toByteArray()
    }

    private fun buildKeyMessage(keyId: ByteArray, key: ByteArray): ByteArray {
        val bos = ByteArrayOutputStream()
        encodeBytes(bos, 1, keyId)
        encodeBytes(bos, 3, key)
        encodeVarint(bos, 4, 2L) // CONTENT key type
        return bos.toByteArray()
    }

    private fun buildPolicyMessage(): ByteArray {
        val bos = ByteArrayOutputStream()
        encodeVarint(bos, 1, 1L) // can_play = true
        encodeVarint(bos, 2, 1L) // can_persist = true
        encodeVarint(bos, 3, 1L) // can_renew = true
        encodeVarint(bos, 6, 0L) // license_duration_seconds = unlimited
        return bos.toByteArray()
    }

    private fun encodeVarint(stream: ByteArrayOutputStream, fieldNumber: Int, value: Long) {
        stream.write((fieldNumber shl 3) or 0) // wire type 0 = varint
        writeRawVarint(stream, value)
    }

    private fun encodeBytes(stream: ByteArrayOutputStream, fieldNumber: Int, value: ByteArray) {
        stream.write((fieldNumber shl 3) or 2) // wire type 2 = length-delimited
        writeRawVarint(stream, value.size.toLong())
        stream.write(value)
    }

    private fun writeRawVarint(stream: ByteArrayOutputStream, value: Long) {
        var v = value
        while ((v ushr 7) != 0L) {
            stream.write(((v.toInt() and 0x7F) or 0x80))
            v = v ushr 7
        }
        stream.write(v.toInt() and 0x7F)
    }

    private fun hexToBytes(hex: String): ByteArray {
        if (hex.length % 2 != 0) return byteArrayOf()
        return try {
            hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        } catch (_: Exception) {
            byteArrayOf()
        }
    }

    private fun stopPlayer(id: Int) {
        disposePlayer(id)
    }

    private fun disposePlayer(id: Int) {
        players[id]?.let { player ->
            player.stop()
            player.release()
            players.remove(id)
        }
        entries[id]?.let { entry ->
            entry.release()
            entries.remove(id)
        }
    }
}
