package dev.gamelingo.tv

/** Content-free logical signature and the actual StaticLayout paragraph sign.
 * Visual placement alone is never treated as a reversed Unicode string. */
internal object PunctuationTrace {
    fun signature(value: String, paragraphDirection: Int): String {
        val text = TextPresentation.clean(value).trim()
        val first = text.codePoints().toArray().asSequence().map { Character.getDirectionality(it) }.firstOrNull {
            it == Character.DIRECTIONALITY_LEFT_TO_RIGHT || it == Character.DIRECTIONALITY_RIGHT_TO_LEFT || it == Character.DIRECTIONALITY_RIGHT_TO_LEFT_ARABIC
        }
        val direction = when(first) {
            null -> "none"
            Character.DIRECTIONALITY_LEFT_TO_RIGHT -> "L"
            else -> "R"
        }
        val marks = "()[]:\"'?؟!.…،؛«»-—"
        val positions = text.mapIndexedNotNull { index, c ->
            if(c !in marks) null else "$c:${if(index == 0) "start" else if(index == text.lastIndex) "end" else "middle"}"
        }.take(64)
        return "visual=${if(paragraphDirection < 0) "RTL" else "LTR"}; logical first=$direction; " + positions.joinToString(" ")
    }
}
