package dev.gamelingo.tv

data class SourceBox(val x:Double,val y:Double,val w:Double,val h:Double)
data class SubtitleEntry(val id: String, var text: String, val shownAt: Long, var until: Long,
    var source:String="",var box:SourceBox?=null,var speaker:String="")

class SubtitleState {
    val entries = mutableListOf<SubtitleEntry>()
    // A small tombstone set prevents delayed duplicates resurrecting expired entries.
    private val seen = java.util.LinkedHashSet<String>()
    private val aliases=java.util.LinkedHashMap<String,String>()
    private val visuallySuperseded=mutableSetOf<String>()
    private val semanticKeys=object:java.util.LinkedHashMap<String,String>(16,.75f,true) {
        override fun removeEldestEntry(eldest:MutableMap.MutableEntry<String,String>?):Boolean=size>16
    }
    var visualCompactions=0;private set
    var coalesced=0;private set
    private fun remember(id:String) {seen.add(id);if(seen.size>128)seen.remove(seen.first())}
    private fun sourceWords(s:String)=Regex("[+-]?\\d+(?:[.,]\\d+)*|\\p{L}+").findAll(
        java.text.Normalizer.normalize(s,java.text.Normalizer.Form.NFKC).replace('\u2212','-').lowercase(java.util.Locale.ROOT).replace(Regex("['’`]"),""))
        .map {it.value}.toList()
    private fun arabicKey(s:String)=java.text.Normalizer.normalize(s,java.text.Normalizer.Form.NFKC)
        .replace(Regex("[\\u064B-\\u065F\\u0670\\u0640]"),"").replace(Regex("[أإآٱ]"),"ا")
        .replace(Regex("[^\\p{L}\\p{N}]"),"")
    private fun oneGlyph(a:String,b:String):Boolean {
        if(minOf(a.length,b.length)<3 || kotlin.math.abs(a.length-b.length)>1)return false
        var i=0;var j=0;var edits=0
        while(i<a.length && j<b.length) {
            if(a[i]==b[j]) {i++;j++}
            else {if(++edits>1)return false;if(a.length>=b.length)i++;if(b.length>=a.length)j++}
        }
        return edits+(a.length-i)+(b.length-j)<=1
    }
    private fun sameSource(entry:SubtitleEntry,source:String,box:SourceBox?):Boolean {
        val a=sourceWords(entry.source);val b=sourceWords(source)
        if(a.isEmpty() || b.isEmpty())return false // Never deduplicate on Arabic alone.
        fun names(text:String)=Regex("[A-Za-z]+").findAll(text).drop(1).map {it.value}.filter {Regex("[A-Z][a-z]{2,}").matches(it)}.toList()
        if(names(entry.source)!=names(source))return false
        if(semanticMarkers(entry.source)!=semanticMarkers(source))return false
        val destinationA=target(entry.source);val destinationB=target(source)
        if(destinationA.isNotEmpty() && destinationB.isNotEmpty() && destinationA!=destinationB && !extension(entry.source,source) && !extension(source,entry.source))return false
        val locationsA=a.filter {it in setOf("here","there")};val locationsB=b.filter {it in setOf("here","there")}
        if(locationsA.isNotEmpty() && locationsB.isNotEmpty() && locationsA!=locationsB)return false
        if(entry.box!=null && box!=null) {
            val p=entry.box!!
            if(kotlin.math.abs(p.x+p.w/2-box.x-box.w/2)>.2 || kotlin.math.abs(p.y-box.y)>.12)return false
        }
        if(a==b)return true
        if(entry.box==null || box==null)return false
        if(a.filter {it.any(Char::isDigit)}!=b.filter {it.any(Char::isDigit)})return false
        if(a.size==b.size && a.size>=2) {
            val differences=a.zip(b).filter {it.first!=it.second}
            return differences.size==1 && oneGlyph(differences[0].first,differences[0].second)
        }
        val short=if(a.size<b.size)a else b;val long=if(a.size<b.size)b else a
        if(short.size<3 || long.size-short.size>2)return false
        var at=0
        for(word in long)if(at<short.size && word==short[at])at++
        return at==short.size
    }
    private fun target(text:String):List<String> {
        val words=sourceWords(text)
        val anchors=setOf("to","toward","towards","at","near","through","into","inside","outside","behind","follow","reach","find","visit","enter","exit","open","close")
        val at=words.indexOfLast {it in anchors}
        return if(at<0) emptyList() else words.drop(at+1).filter {it !in setOf("the","a","an","me","him","her","us","them")}.take(12)
    }
    private fun semanticKey(text:String):String {
        semanticKeys[text]?.let {return it}
        val names=Regex("[A-Za-z]+").findAll(text).drop(1).map {it.value}.filter {Regex("[A-Z][a-z]{2,}").matches(it)}.joinToString(" ")
        val key=semanticMarkers(text).joinToString(" ")+"/"+target(text).joinToString(" ")+"/"+sourceWords(text).filter {it in setOf("here","there")}.joinToString(" ")+"/"+names
        semanticKeys[text]=key;return key
    }
    private fun semanticMarkers(text:String):List<String> {
        val protected=setOf("no","not","never","dont","cannot","cant","wont","without","isnt","wasnt","didnt","shouldnt","wouldnt","couldnt","he","she","they","we","you","i","left","right","north","south","east","west","open","close","enter","exit","attack","defend","take","drop","give","keep","stop","start","push","pull","save","kill","follow","stay","leave","collect")
        return sourceWords(text).filter {it in protected || it.any(Char::isDigit)}
    }
    private fun extension(before:String,after:String):Boolean {
        val a=sourceWords(before);val b=sourceWords(after)
        return a.size>=2 && b.size>a.size && b.take(a.size)==a
    }
    fun duration(text: String, adaptive: Boolean, speed: Double, minimum: Long, maximum: Long, fixed: Long): Long {
        val chars = text.count { !it.isWhitespace() }
        return if (adaptive) (chars / speed.coerceAtLeast(1.0) * 1000).toLong().coerceIn(minimum, maximum.coerceAtLeast(minimum))
            else fixed.coerceIn(minimum, maximum.coerceAtLeast(minimum))
    }
    fun show(id: String, text: String, now: Long, duration: Long, capacity: Int,source:String="",box:SourceBox?=null,
        speaker:String="",freshEvent:Boolean=false,meaningfulCorrection:Boolean=false,boundary:String?=null,sourceGap:Long=0) {
        expire(now)
        val old = entries.firstOrNull { it.id == (aliases[id] ?: id) }
        if (old != null) {
            // Cosmetic OCR/Arabic paraphrases do not rewrite a visible card.
            // Old senders without source metadata retain their explicit updates.
            if(meaningfulCorrection || old.source.isEmpty() || source.isEmpty() || semanticMarkers(old.source)!=semanticMarkers(source) || extension(old.source,source) || !sameSource(old,source,box)) old.text = text
            if(speaker.isNotEmpty()) old.speaker=speaker
            if(source.isNotEmpty()) {old.source=source;old.box=box}
            return
        }
        // Event IDs, not translated text, identify dialogue. Distinct source
        // events may legitimately repeat or translate to identical Arabic.
        if (id in seen) return
        val provedNew=boundary=="speaker_change" || boundary=="spatial_change" || (boundary=="source_gap" && sourceGap>=750)
        val compatible:(SubtitleEntry)->Boolean={it.speaker.isEmpty() || speaker.isEmpty() || it.speaker.equals(speaker,true)}
        // Legacy fresh-event messages retain their behavior. New senders supply
        // boundary evidence; a bare new ID must not stack the same active line.
        val matching=if(provedNew || (freshEvent && boundary==null)) null else if(freshEvent) entries.lastOrNull()?.takeIf {
            it.id !in visuallySuperseded && compatible(it) && sameSource(it,source,box)
        } else entries.lastOrNull {it.id !in visuallySuperseded && compatible(it) && now-it.shownAt<=3500 && sameSource(it,source,box)}
        remember(id)
        if(matching!=null) {
            coalesced++
            if(matching===entries.lastOrNull()) {
                // OCR dropouts/corrections may allocate a fresh sender ID while
                // its equivalent sentence is still visible. Alias it, without
                // extending the original local lifetime or adding another box.
                aliases[id]=matching.id;if(aliases.size>128)aliases.remove(aliases.keys.first())
                matching.source=source;matching.box=box
                if(speaker.isNotEmpty()) matching.speaker=speaker
                return
            }
            // A genuinely repeated line after intervening dialogue becomes the
            // newest entry with its own clock; remove its older visual copy.
            entries.remove(matching)
        }
        entries.add(SubtitleEntry(id, text, now, now + duration,source,box,speaker))
        while (entries.size > capacity.coerceIn(1,3)) entries.removeAt(0)
    }
    fun expire(now: Long) { entries.removeAll { it.until <= now } }
    fun visibleEntries():List<SubtitleEntry> {
        visuallySuperseded.retainAll(entries.map {it.id}.toSet())
        val keys=mutableSetOf<String>()
        for(entry in entries.asReversed()) {
            if(entry.id in visuallySuperseded)continue
            val key=entry.speaker.lowercase(java.util.Locale.ROOT)+"/"+semanticKey(entry.source)+"/"+java.text.Normalizer.normalize(entry.text,java.text.Normalizer.Form.NFKC)
                .trim().trimEnd('.','!','?','؟','،','؛','…').replace(Regex("\\s+")," ")
            if(!keys.add(key)) {visuallySuperseded.add(entry.id);visualCompactions++}
        }
        // This is presentation compaction, not event deduplication: independent
        // IDs/deadlines remain intact. A distinct new event is always the visible
        // newest copy. Its older visual copy never reappears after it expires.
        return entries.filterNot {it.id in visuallySuperseded}
    }
    fun disappeared(id: String, now: Long, minimum: Long, grace: Long) {
        entries.firstOrNull { it.id == (aliases[id] ?: id) }?.let {
            it.until = minOf(it.until, maxOf(it.shownAt + minimum, now + grace))
        }
    }
    fun alpha(entry: SubtitleEntry, now: Long, fade: Long): Float =
        if (fade <= 0) 1f else ((entry.until-now).toFloat()/fade).coerceIn(0f,1f)
    fun clear() { entries.clear(); seen.clear();aliases.clear();visuallySuperseded.clear();semanticKeys.clear() }
}

