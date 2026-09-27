import Foundation
import Testing
@testable import ContextDomain

@Suite struct SwipeNavigationTests {
    @Test func leftwardFlickGoesNext() {
        var nav = SwipeNavigation()
        nav.begin()
        nav.add(deltaX: -120, deltaY: 10)
        #expect(nav.end() == .next)
    }

    @Test func rightwardFlickGoesPrevious() {
        var nav = SwipeNavigation()
        nav.begin()
        nav.add(deltaX: 120, deltaY: -5)
        #expect(nav.end() == .previous)
    }

    @Test func smallMotionIgnored() {
        var nav = SwipeNavigation()
        nav.begin()
        nav.add(deltaX: -20, deltaY: 0)
        #expect(nav.end() == nil)
    }

    @Test func verticalScrollIgnored() {
        var nav = SwipeNavigation()
        nav.begin()
        nav.add(deltaX: -120, deltaY: -200)
        #expect(nav.end() == nil)
    }

    @Test func trackpadSwipeEventMapping() {
        #expect(SwipeNavigation.swipeEventDirection(deltaX: -1) == .next)
        #expect(SwipeNavigation.swipeEventDirection(deltaX: 1) == .previous)
        #expect(SwipeNavigation.swipeEventDirection(deltaX: 0) == nil)
    }
}
