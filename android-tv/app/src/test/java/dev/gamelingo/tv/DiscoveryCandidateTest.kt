package dev.gamelingo.tv
import org.junit.Assert.*
import org.junit.Test
class DiscoveryCandidateTest {
    @Test fun discoveryRequiresAnAlreadySavedFullPin() {
        val pin="a".repeat(64)
        assertTrue(DiscoveryCandidate.matches(pin,"GameLingo-${pin.take(12)}"))
        assertTrue(DiscoveryCandidate.matches(pin,"GameLingo-${pin.take(12)} (2)"))
        assertFalse(DiscoveryCandidate.matches(pin.take(12),"GameLingo-${pin.take(12)}"))
        assertFalse(DiscoveryCandidate.matches(pin,"GameLingo-${"b".repeat(12)}"))
        assertFalse(DiscoveryCandidate.matches(pin,"GameLingo-${pin.take(12)}-attacker"))
    }
}
