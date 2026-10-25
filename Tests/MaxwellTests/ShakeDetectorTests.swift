import Foundation
import Testing
@testable import Maxwell

@Suite("Détection de la Secousse")
struct ShakeDetectorTests {
    private typealias Path = (Double) -> (x: Double, y: Double)

    /// Donne au détecteur une position toutes les 1/60 s, comme le relevé de la souris.
    /// Renvoie les instants où une Secousse est reconnue.
    private func shakes(_ detector: inout ShakeDetector, over duration: Double, path: Path) -> [Double] {
        var found: [Double] = []
        for step in 0...Int(duration * 60) {
            let time = Double(step) / 60
            let point = path(time)
            if detector.add(x: point.x, y: point.y, at: time) { found.append(time) }
        }
        return found
    }

    /// Va-et-vient autour de (500, 400) dans la direction (dx, dy) : `amplitude` points de part et d'autre,
    /// `frequency` allers-retours par seconde.
    private func wiggle(amplitude: Double, frequency: Double, dx: Double = 1, dy: Double = 0) -> Path {
        { time in
            let offset = amplitude * sin(2 * .pi * frequency * time)
            return (500 + offset * dx, 400 + offset * dy)
        }
    }

    @Test func aQuickHorizontalShakeIsRecognizedWithinHalfASecond() {
        var detector = ShakeDetector()
        let found = shakes(&detector, over: 0.5, path: wiggle(amplitude: 50, frequency: 4))
        #expect(found.count == 1)
        #expect(found.first.map { $0 < 0.45 } == true)
    }

    @Test func aVerticalShakeIsRecognized() {
        var detector = ShakeDetector()
        #expect(shakes(&detector, over: 0.6, path: wiggle(amplitude: 50, frequency: 4, dx: 0, dy: 1)).count == 1)
    }

    @Test func aDiagonalShakeIsRecognized() {
        var detector = ShakeDetector()
        let path = wiggle(amplitude: 50, frequency: 4, dx: 0.7, dy: -0.7)
        #expect(shakes(&detector, over: 0.6, path: path).count == 1)
    }

    @Test func aShakeAfterAMoveInAnotherDirectionIsRecognized() {
        // On glisse vers la droite, puis on secoue de haut en bas.
        var detector = ShakeDetector()
        let found = shakes(&detector, over: 1.2) { time in
            time < 0.4 ? (100 + 1000 * time, 400) : (500, 400 + 50 * sin(2 * .pi * 4 * (time - 0.4)))
        }
        // Reconnue pendant la secousse, pas pendant le glisser vers la droite.
        #expect(found.first.map { $0 > 0.4 && $0 < 0.9 } == true)
    }

    @Test func aStraightDragIsNotAShake() {
        var detector = ShakeDetector()
        #expect(shakes(&detector, over: 1.5) { time in (100 + 600 * time, 100 + 400 * time) }.isEmpty)
    }

    @Test func aDragThatTurnsACornerIsNotAShake() {
        var detector = ShakeDetector()
        let found = shakes(&detector, over: 1) { time in
            time < 0.5 ? (100 + 800 * time, 400) : (500, 400 + 800 * (time - 0.5))
        }
        #expect(found.isEmpty)
    }

    @Test func handTremorIsNotAShake() {
        var detector = ShakeDetector()
        #expect(shakes(&detector, over: 2, path: wiggle(amplitude: 12, frequency: 6, dx: 0.6, dy: 0.8)).isEmpty)
    }

    @Test func aSlowBackAndForthIsNotAShake() {
        var detector = ShakeDetector()
        #expect(shakes(&detector, over: 6, path: wiggle(amplitude: 120, frequency: 0.5)).isEmpty)
    }

    @Test func aLongShakeIsNotCountedOnEveryReversal() {
        // Après une Secousse, il faut de nouveau trois retours pour en reconnaître une autre.
        var detector = ShakeDetector()
        let found = shakes(&detector, over: 1.5, path: wiggle(amplitude: 50, frequency: 4))
        #expect(found.count >= 2)
        #expect(zip(found, found.dropFirst()).allSatisfy { $1 - $0 >= 0.3 })
    }

    @Test func positionsGoingBackInTimeAreIgnored() {
        var detector = ShakeDetector()
        #expect(detector.add(x: 0, y: 0, at: 1) == false)
        #expect(detector.add(x: 100, y: 0, at: 0.5) == false)
        #expect(detector.add(x: 30, y: 0, at: 1.1) == false)
    }
}
