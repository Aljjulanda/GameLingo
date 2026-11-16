package dev.gamelingo.tv

import org.json.JSONObject

/** Optional source-controlled presentation; absent fields retain the old renderer. */
internal data class SubtitleQuality(
    val arabicName:String="", val cue:String="", val cueOnly:Boolean=false,
    val provenance:String="", val basis:String="", val arabicParagraphDirection:Boolean=false
) {
    val badge:String get()=when(if(provenance=="reuse") basis else provenance) {
        "packExact","packNormalized","packPunctuationless" -> "حزمة"
        "userCorrection" -> "تصحيح"
        else -> ""
    }
    val decorated:Boolean get()=arabicName.isNotEmpty() || cue.isNotEmpty() || badge.isNotEmpty() || arabicParagraphDirection
    companion object {
        fun parse(message:JSONObject):SubtitleQuality {
            fun text(value:Any?,limit:Int):String=if(value is String && value.length<=limit) TextPresentation.clean(value) else ""
            val speaker=message.optJSONObject("speaker")
            return SubtitleQuality(
                arabicName=text(speaker?.opt("arabic"),100),cue=text(message.opt("cue"),160).takeIf {!it.contains('\n') && !it.contains('\r')} ?: "",
                cueOnly=message.opt("cue_only")==true,
                provenance=text(message.opt("provenance"),32),basis=text(message.opt("provenance_basis"),32),
                arabicParagraphDirection=message.opt("arabic_paragraph_direction")==true
            )
        }
    }
}

internal object QualityRenderPolicy {
    fun hasArabicLetters(text:String):Boolean = text.codePoints().anyMatch {
        Character.isLetter(it) && Character.UnicodeScript.of(it)==Character.UnicodeScript.ARABIC
    }
    fun rtl(text:String,quality:SubtitleQuality):Boolean = !quality.arabicParagraphDirection || hasArabicLetters(text)
    // Physical left/right stays fixed when paragraph direction changes.
    fun normalAlignment(alignment:String,rtl:Boolean):Boolean = if(alignment=="right") rtl else !rtl
}
