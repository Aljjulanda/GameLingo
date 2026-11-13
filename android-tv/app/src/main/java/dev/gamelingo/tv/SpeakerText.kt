package dev.gamelingo.tv

import android.graphics.Paint
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.style.CharacterStyle
import android.text.style.UpdateAppearance

internal class SpeakerColorSpan(val color: Int) : CharacterStyle(), UpdateAppearance {
    override fun updateDrawState(paint: TextPaint) {
        // Keep the existing outline color and inherit fade/text opacity.
        if (paint.style != Paint.Style.STROKE) paint.color = (color and 0x00ffffff) or (paint.alpha shl 24)
    }
}

internal object SpeakerText {
    fun inline(dialogue: String, speaker: String, enabled: Boolean, color: Int): CharSequence {
        val name = speaker.filter { it.isLetterOrDigit() || it in " '-." }.trim().take(40)
        if (!enabled || name.isEmpty()) return dialogue
        // Unicode isolates keep an English name inline at the RTL paragraph start.
        val prefix = "\u2068$name:\u2069 "
        return SpannableString(prefix+dialogue).apply {
            setSpan(SpeakerColorSpan(color),0,prefix.length,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }
}
