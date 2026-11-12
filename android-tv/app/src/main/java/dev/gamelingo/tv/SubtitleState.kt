package dev.gamelingo.tv

data class SubtitleEntry(val id: String, var text: String, val shownAt: Long, var until: Long)

class SubtitleState {
    val entries = mutableListOf<SubtitleEntry>()
    fun duration(text: String, adaptive: Boolean, speed: Double, minimum: Long, maximum: Long, fixed: Long): Long {
        val chars = text.count { !it.isWhitespace() }
        return if (adaptive) (chars / speed.coerceAtLeast(1.0) * 1000).toLong().coerceIn(minimum, maximum.coerceAtLeast(minimum))
            else fixed.coerceIn(minimum, maximum.coerceAtLeast(minimum))
    }
    fun show(id: String, text: String, now: Long, duration: Long, capacity: Int) {
        expire(now)
        val old = entries.firstOrNull { it.id == id }
        if (old != null) {
            old.text = text // Corrections and duplicates retain their original visible-time clock.
            return
        }
        if (entries.lastOrNull()?.text == text) return
        entries.add(SubtitleEntry(id, text, now, now + duration))
        while (entries.size > capacity.coerceIn(1,3)) entries.removeAt(0)
    }
    fun expire(now: Long) { entries.removeAll { it.until <= now } }
    fun clear() { entries.clear() }
}

