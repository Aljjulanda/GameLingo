package dev.gamelingo.tv

/** Content-free logical signature and the actual StaticLayout paragraph sign.
 * Visual placement alone is never treated as a reversed Unicode string. */
internal object PunctuationTrace {
    fun signature(value: String, paragraphDirection: Int): String {
        val text = TextPresentation.clean(value).trim()
        val first = text.codePoints().toArray().firstOrNull { Character.isLetter(it) }
        val direction = if(first == null) "none" else when(Character.getDirectionality(first)) {
            Character.DIRECTIONALITY_RIGHT_TO_LEFT, Character.DIRECTIONALITY_RIGHT_TO_LEFT_ARABIC -> "R"
            else -> "L"
        }
        val marks = "()[]:\"'?؟!.…،؛«»-—"
        val positions = text.mapIndexedNotNull { index, c ->
            if(c !in marks) null else "$c:${if(index == 0) "start" else if(index == text.lastIndex) "end" else "middle"}"
        }.take(64)
        return "visual=${if(paragraphDirection < 0) "RTL" else "LTR"}; logical first=$direction; " + positions.joinToString(" ")
    }
}
