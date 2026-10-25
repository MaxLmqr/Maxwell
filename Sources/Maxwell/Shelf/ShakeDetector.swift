import Foundation

/// Reconnaît une Secousse : la souris fait plusieurs allers-retours vifs et francs, dans n'importe quelle direction
/// (horizontale, verticale, en diagonale ou en zigzag).
/// Il ne dépend que des positions qu'on lui donne, pour pouvoir être testé sans souris.
struct ShakeDetector {
    /// Distance minimale d'un trajet avant qu'il compte, en points.
    var minimumSwing: Double = 30
    /// Retours nécessaires : 3 font aller-retour-aller-retour.
    var requiredReversals = 3
    /// Délai maximal pour les enchaîner, en secondes.
    var window: TimeInterval = 0.75
    /// Un trajet est un retour s'il repart à plus de 120° du précédent (cosinus de -0,5).
    var reversalCosine = -0.5

    /// Direction du trajet en cours (vecteur unitaire), inconnue tant que la souris n'a pas assez bougé.
    private var direction: (dx: Double, dy: Double)?
    /// Point de départ, puis point le plus avancé du trajet en cours.
    private var turningPoint: (x: Double, y: Double, time: TimeInterval)?
    private var reversalTimes: [TimeInterval] = []
    private var lastTime = -Double.infinity

    /// Ajoute une position ; renvoie true au moment où la Secousse est reconnue.
    mutating func add(x: Double, y: Double, at time: TimeInterval) -> Bool {
        guard time >= lastTime else { return false }
        lastTime = time
        guard let turn = turningPoint else {
            turningPoint = (x, y, time)
            return false
        }

        let dx = x - turn.x
        let dy = y - turn.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 0 else { return false }
        guard let current = direction else {
            // Le premier trajet franc fixe la direction.
            if distance >= minimumSwing { startSegment(dx / distance, dy / distance, at: (x, y, time)) }
            return false
        }

        let cosine = (dx * current.dx + dy * current.dy) / distance
        if cosine >= 0.5 {
            // La souris continue à peu près dans le même sens : le point le plus avancé la suit.
            turningPoint = (x, y, time)
        } else if distance >= minimumSwing {
            if cosine <= reversalCosine {
                // Retour franc, daté au moment où la souris a tourné.
                reversalTimes.append(turn.time)
                reversalTimes.removeAll { time - $0 > window }
                if reversalTimes.count >= requiredReversals {
                    reset()
                    return true
                }
            }
            // Retour ou simple virage : un nouveau trajet commence ici.
            startSegment(dx / distance, dy / distance, at: (x, y, time))
        }
        return false
    }

    mutating func reset() {
        direction = nil
        turningPoint = nil
        reversalTimes = []
        lastTime = -Double.infinity
    }

    private mutating func startSegment(_ dx: Double, _ dy: Double, at point: (x: Double, y: Double, time: TimeInterval)) {
        direction = (dx, dy)
        turningPoint = point
    }
}
