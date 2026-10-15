package com.cocoscout.app.door

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.view.HapticFeedbackConstants
import android.view.View
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/**
 * The sound and buzz for each result, the same as the door page makes in a
 * browser and the iOS app makes (DoorFeedback.swift): a short rising chirp
 * when someone's in, a low buzz for anything else, so the door never has to
 * read the screen.
 */
class DoorFeedback {
    private val chirp = tone(frequency = 880.0, seconds = 0.15, square = false)
    private val buzz = tone(frequency = 220.0, seconds = 0.4, square = true)

    fun play(tone: DoorResult.Tone, view: View) {
        val track = if (tone == DoorResult.Tone.ADMITTED) chirp else buzz
        runCatching {
            track.stop()
            track.reloadStaticData()
            track.play()
        }
        val haptic = when {
            android.os.Build.VERSION.SDK_INT >= 30 && tone == DoorResult.Tone.ADMITTED -> HapticFeedbackConstants.CONFIRM
            android.os.Build.VERSION.SDK_INT >= 30 -> HapticFeedbackConstants.REJECT
            else -> HapticFeedbackConstants.LONG_PRESS
        }
        view.performHapticFeedback(haptic)
    }

    fun release() {
        chirp.release()
        buzz.release()
    }

    /** A tone made on the spot, with a few milliseconds of fade at each end so it doesn't click. */
    private fun tone(frequency: Double, seconds: Double, square: Boolean): AudioTrack {
        val rate = 44_100
        val count = (rate * seconds).toInt()
        val fade = rate * 0.005
        val samples = ShortArray(count) { index ->
            var value = sin(2 * PI * frequency * index / rate)
            if (square) value = if (value >= 0) 1.0 else -1.0
            val edge = min(1.0, min(index.toDouble(), (count - index).toDouble()) / fade)
            (value * 0.3 * edge * Short.MAX_VALUE).toInt().toShort()
        }
        return AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(count * 2)
            .build()
            .also { it.write(samples, 0, count) }
    }
}
