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
    private data class Key(val text:String,val name:String,val enabled:Boolean,val color:Int)
    // Canvas/UI-thread only. Repeated fades do not re-run presentation regexes.
    private val cache=object:java.util.LinkedHashMap<Key,CharSequence>(16,.75f,true) {
        override fun removeEldestEntry(eldest:MutableMap.MutableEntry<Key,CharSequence>?):Boolean=size>12
    }
    fun inline(dialogue: String, speaker: String, enabled: Boolean, color: Int): CharSequence {
        val key=Key(dialogue,speaker,enabled,color)
        cache[key]?.let {return it}
        val name=TextPresentation.name(speaker)
        val body=TextPresentation.body(dialogue)
        val result:CharSequence=if(!enabled || name.isEmpty()) body else {
            // The name is LTR; the separator belongs to the surrounding RTL run.
            // A colon inside the English isolate appears on the name's far side.
            SpannableString(TextPresentation.prefix(name)+body).apply {
                setSpan(SpeakerColorSpan(color),1,1+name.length,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
        cache[key]=result
        return result
    }
}
