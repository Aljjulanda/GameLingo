package dev.gamelingo.tv

import org.junit.Assert.*
import org.junit.Test

class SourceLifetimeTest {
    @Test fun sourceRemainsVisibleThenExpiresWithoutFreshEvidence() {
        val state=SubtitleState()
        state.sourcePresent("a",1,0)
        state.show("a","نص طويل",0,8000,3)
        for(time in 1000L..20000L step 1000L) {state.sourcePresent("a",1,time);state.expire(time)}
        assertEquals(1,state.entries.size)
        state.expire(21801);assertTrue(state.entries.isEmpty())
    }
    @Test fun disappearanceTombstonesPendingOutputAndOldClearCannotDeleteNewGeneration() {
        val state=SubtitleState()
        state.sourcePresent("a",2,0);state.show("a","جديد",0,8000,3)
        assertTrue(state.sourceGone("a",1));assertEquals(1,state.entries.size)
        assertTrue(state.sourceGone("a",2));assertTrue(state.entries.isEmpty())
        assertFalse(state.sourceShow("a",2,200))
        state.sourcePresent("a",3,300);state.show("a","متأخر",300,8000,3)
        assertTrue(state.entries.isEmpty())
        state.sourceGone("pending",8)
        assertFalse(state.sourceShow("pending",8,400))
    }
    @Test fun staleCorrectionCannotRenewOrOverwriteCurrentSource() {
        val state=SubtitleState()
        state.sourcePresent("a",4,0)
        assertFalse(state.sourceShow("a",3,100))
        assertTrue(state.sourceShow("a",4,100))
        state.show("a","صحيح",100,8000,3)
        assertEquals(1800L,state.entries.single().until)
    }
}
