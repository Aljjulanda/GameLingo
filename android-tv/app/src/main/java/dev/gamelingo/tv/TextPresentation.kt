package dev.gamelingo.tv

/** Logical punctuation is preserved. Only the renderer inserts directional controls. */
internal object TextPresentation {
    private val controls=Regex("[\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]")
    private val token="[+\u2212-]?[\\p{IsLatin}0-9]+(?:['’.,/:+\u2013-][\\p{IsLatin}0-9]+)*%?"
    private val latin=Regex("$token(?: $token)*")
    fun clean(text:String):String=controls.replace(text,"")
    fun body(text:String):String {
        val clean=clean(text)
        if(!clean.any { it.isLetter() && (it in '\u0600'..'\u08ff' || it in '\ufb50'..'\ufeff') }) return clean
        return latin.replace(clean) { "\u2066${it.value}\u2069" }
    }
    fun name(text:String):String=clean(text).filter {it.isLetterOrDigit() || it in " '’-."}.trim().take(40)
    fun prefix(name:String):String="\u2066$name\u2069\u200f:\u00a0"
}
