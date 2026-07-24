package frezzy.gonow.features.chat

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

data class VoiceRecording(val file: File, val durationSeconds: Double)

class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var output: File? = null
    private var startedAt: Long = 0

    fun start() {
        check(recorder == null) { "Recording is already active" }
        val target = File.createTempFile("gonow-voice-", ".m4a", context.cacheDir)
        val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION") MediaRecorder()
        }
        mediaRecorder.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioEncodingBitRate(96_000)
            setAudioSamplingRate(44_100)
            setOutputFile(target.absolutePath)
            prepare()
            start()
        }
        output = target
        recorder = mediaRecorder
        startedAt = System.nanoTime()
    }

    fun stop(): VoiceRecording? {
        val active = recorder ?: return null
        val file = output
        val duration = (System.nanoTime() - startedAt) / 1_000_000_000.0
        return try {
            active.stop()
            file?.takeIf { it.length() > 0 }?.let { VoiceRecording(it, duration) }
        } finally {
            active.release()
            recorder = null
            output = null
        }
    }

    fun cancel() {
        runCatching { recorder?.stop() }
        recorder?.release()
        recorder = null
        output?.delete()
        output = null
    }
}
