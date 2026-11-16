package dev.gamelingo.tv

import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.RelativeSizeSpan

internal object QualitySubtitleText {
    private data class Key(val body:String,val speaker:String,val showSpeaker:Boolean,val speakerColor:Int,val mutedColor:Int,val quality:SubtitleQuality)
    private val cache=object:java.util.LinkedHashMap<Key,CharSequence>(16,.75f,true) {
        override fun removeEldestEntry(eldest:MutableMap.MutableEntry<Key,CharSequence>?):Boolean=size>12
    }
    fun inline(dialogue:String,speaker:String,showSpeaker:Boolean,speakerColor:Int,mutedColor:Int,quality:SubtitleQuality):CharSequence {
        if(!quality.decorated) return SpeakerText.inline(dialogue,speaker,showSpeaker,speakerColor)
        val key=Key(dialogue,speaker,showSpeaker,speakerColor,mutedColor,quality)
        cache[key]?.let {return it}
        val result=SpannableStringBuilder()
        fun styled(value:String,color:Int,small:Boolean=false) {
            val start=result.length
            result.append(value)
            result.setSpan(SpeakerColorSpan(color),start,result.length,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            if(small) result.setSpan(RelativeSizeSpan(.60f),start,result.length,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        val body=TextPresentation.body(dialogue)
        val cue=TextPresentation.clean(quality.cue).trim()
        val cueOnly=quality.cueOnly && cue.isNotEmpty() && TextPresentation.clean(dialogue).trim()==cue
        if(cue.isNotEmpty()) { styled("\u2067$cue\u2069",mutedColor);result.append('\u00a0') }
        // Preserve explicitly authored Arabic spelling, including vowel marks;
        // prevent controls/line breaks from creating a separate name row.
        val arabicName=TextPresentation.clean(quality.arabicName).filter {!it.isISOControl() && it!='\u2028' && it!='\u2029'}.trim().take(100)
        val name=arabicName.ifEmpty { TextPresentation.name(speaker) }
        if(showSpeaker && name.isNotEmpty()) {
            // FSI accepts either Arabic spelling or the legacy English name.
            styled("\u2068$name\u2069",speakerColor)
            if(!cueOnly) {
                if(QualityRenderPolicy.rtl(dialogue,quality)) result.append('\u200f')
                result.append(":\u00a0")
            }
        }
        // A malformed optional cue_only must never erase a different dialogue.
        if(!cueOnly) result.append(body)
        if(quality.badge.isNotEmpty()) { result.append('\u00a0');styled("\u2067◆ ${quality.badge}\u2069",mutedColor,small=true) }
        cache[key]=result
        return result
    }
}
