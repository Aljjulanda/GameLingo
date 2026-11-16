package dev.gamelingo.tv
import org.junit.Assert.*
import org.junit.Test

class PunctuationTraceTest {
    @Test fun distinguishesUnicodeOrderFromParagraphDirectionWithoutText() {
        val trace = PunctuationTrace.signature("Arthur: (هل أنت هنا)؟",-1)
        assertTrue(trace.contains("visual=RTL")); assertTrue(trace.contains("first=L"))
        assertTrue(trace.contains("(:middle")); assertTrue(trace.contains("؟:end"))
        assertFalse(trace.contains("Arthur")); assertFalse(trace.contains("أنت"))
        assertEquals("visual=LTR; logical first=none; ",PunctuationTrace.signature("123",1))
        assertTrue(PunctuationTrace.signature("(نعم!)",1).contains("first=R"))
        assertTrue(PunctuationTrace.signature("Ⅳ: نعم",-1).contains("first=L"))
        assertTrue(PunctuationTrace.signature("𞸀!",-1).contains("first=R"))
    }
    @Test fun signatureIsBounded() {
        val trace = PunctuationTrace.signature("!".repeat(2400),-1)
        assertTrue(trace.length < 1024)
        assertEquals(64,trace.split("!:middle").size-1 + if(trace.contains("!:start")) 1 else 0)
    }
}
