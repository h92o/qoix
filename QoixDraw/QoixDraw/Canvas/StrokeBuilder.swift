import CoreGraphics
import Foundation

/// One position of the pen tip along a stroke, and how large the tip is there (1 = full size).
struct StrokeStep: Equatable {
    var center: CGPoint
    var scale: CGFloat
}

/// Turns the points of one stroke into the sequence of pen-tip positions to paint.
///
/// Points go in one at a time as the finger moves, and finished steps come out the other side. It is
/// *causal*: a step is only ever appended, never changed afterwards, so the part of a stroke already painted
/// stays valid while the rest is still being drawn. It is also *deterministic*: the same points always give the
/// same steps, which is what lets undo repaint a stroke exactly as it was drawn.
///
/// What it does to the raw finger samples:
/// - smooths the path (the pen follows the finger a little behind it, which evens out jitter),
/// - joins the points with quadratic curves that run from midpoint to midpoint, sampled finely,
/// - sizes the tip from speed and finger contact area, if the brush's dynamics ask for that,
/// - tapers the start and, when the finger lifts, adds a tail to the end.
final class StrokeBuilder {
    /// The brush's `followTime` is kept within these limits (seconds).
    static let followTimeRange: ClosedRange<CGFloat> = 0.001...0.5
    /// How quickly the speed estimate and the tip size react (seconds).
    static let speedTimeConstant: CGFloat = 0.06
    static let scaleTimeConstant: CGFloat = 0.08
    /// Points closer together than this (canvas pixels) are treated as jitter and skipped.
    static let minimumStep: CGFloat = 0.25
    /// Distance between pen-tip positions along the path (canvas pixels).
    static let stepLength: CGFloat = 1.5
    /// The tip never shrinks below this fraction of its size.
    static let minimumScale: CGFloat = 0.03
    /// The shortest time between two samples that is believed, so a burst of events can't mean infinite speed.
    static let minimumDelta: CGFloat = 1.0 / 240.0
    /// A guard against absurdly long single jumps producing absurdly many steps.
    static let maximumStepsPerSpan = 400

    let brush: Brush
    /// The pen-tip positions so far. Only ever appended to.
    private(set) var steps: [StrokeStep] = []

    /// How quickly the pen catches up with the finger (seconds). Smaller follows more tightly.
    private let followTime: CGFloat

    private var lastRaw: StrokePoint
    private var smoothed: CGPoint
    private var lastMid: CGPoint
    private var speed: CGFloat = 0
    private var responsiveScale: CGFloat = 1
    private var travelled: CGFloat = 0
    private var heading = CGVector(dx: 1, dy: 0)
    private var contactAverage: CGFloat = 0
    private var contactSamples = 0
    private var isFinished = false

    init(brush: Brush, start: StrokePoint) {
        self.brush = brush
        self.followTime = min(max(CGFloat(brush.dynamics.followTime), StrokeBuilder.followTimeRange.lowerBound),
                              StrokeBuilder.followTimeRange.upperBound)
        self.lastRaw = start
        self.smoothed = start.cgPoint
        self.lastMid = start.cgPoint
        noteContact(start.radius)
        steps = [StrokeStep(center: start.cgPoint, scale: taperScale(travelled: 0))]
    }

    /// Adds the next point of the stroke. Returns false (and changes nothing) if it is too close to the
    /// previous point to matter.
    @discardableResult
    func add(_ point: StrokePoint) -> Bool {
        guard !isFinished else { return false }
        let dx = CGFloat(point.x - lastRaw.x)
        let dy = CGFloat(point.y - lastRaw.y)
        guard dx * dx + dy * dy >= Self.minimumStep * Self.minimumStep else { return false }

        let dt = max(CGFloat(point.time - lastRaw.time), Self.minimumDelta)
        advance(toward: point.cgPoint, dt: dt, radius: point.radius)
        lastRaw = point
        return true
    }

    /// Ends the stroke: lets the pen catch up with where the finger lifted, then adds the tail if the brush has
    /// one. Nothing can be added afterwards.
    func finish() {
        guard !isFinished else { return }
        isFinished = true

        if steps.count == 1 {
            // A tap, not a stroke: a dot at full size, not the pointed start of a stroke that never went anywhere.
            steps[0].scale = 1
        }

        // Each catch-up step closes half of the remaining gap, however much smoothing the brush has, so the
        // stroke always ends where the finger lifted.
        let end = lastRaw.cgPoint
        let catchUp: CGFloat = followTime * 0.693147 // ln 2: a step this long closes exactly half the gap
        var iterations = 0
        while hypot(end.x - smoothed.x, end.y - smoothed.y) > 0.5 && iterations < 12 {
            advance(toward: end, dt: catchUp, radius: lastRaw.radius)
            iterations += 1
        }
        if hypot(smoothed.x - lastMid.x, smoothed.y - lastMid.y) > 0.01 {
            let control = CGPoint(x: (lastMid.x + smoothed.x) / 2, y: (lastMid.y + smoothed.y) / 2)
            appendSpan(from: lastMid, control: control, to: smoothed)
            lastMid = smoothed
        }
        addTail()
    }

    // MARK: Steps

    private func advance(toward target: CGPoint, dt: CGFloat, radius: Double) {
        let previous = smoothed
        let follow = Self.blend(dt: dt, constant: followTime)
        smoothed = CGPoint(x: previous.x + (target.x - previous.x) * follow,
                           y: previous.y + (target.y - previous.y) * follow)

        let moved = hypot(smoothed.x - previous.x, smoothed.y - previous.y)
        speed += (moved / dt - speed) * Self.blend(dt: dt, constant: Self.speedTimeConstant)
        noteContact(radius)
        let wanted = speedScale() * contactFactor(radius)
        responsiveScale += (wanted - responsiveScale) * Self.blend(dt: dt, constant: Self.scaleTimeConstant)

        let mid = CGPoint(x: (previous.x + smoothed.x) / 2, y: (previous.y + smoothed.y) / 2)
        appendSpan(from: lastMid, control: previous, to: mid)
        lastMid = mid
    }

    /// Appends pen-tip positions along the quadratic curve from `start` to `end` (pulled toward `control`).
    private func appendSpan(from start: CGPoint, control: CGPoint, to end: CGPoint) {
        let length = hypot(control.x - start.x, control.y - start.y) + hypot(end.x - control.x, end.y - control.y)
        let startScale = steps[steps.count - 1].scale
        let endScale = max(responsiveScale * taperScale(travelled: travelled + length), Self.minimumScale)
        let count = max(1, min(Int((length / Self.stepLength).rounded(.up)), Self.maximumStepsPerSpan))

        for index in 1...count {
            let t = CGFloat(index) / CGFloat(count)
            let u = 1 - t
            let center = CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                                 y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
            steps.append(StrokeStep(center: center, scale: startScale + (endScale - startScale) * t))
        }

        travelled += length
        let tangent = CGVector(dx: end.x - control.x, dy: end.y - control.y)
        let size = hypot(tangent.dx, tangent.dy)
        if size > 0.0001 {
            heading = CGVector(dx: tangent.dx / size, dy: tangent.dy / size)
        }
    }

    /// The tail a brush leaves when the finger lifts: the stroke carries on in the same direction, shrinking.
    private func addTail() {
        let dynamics = brush.dynamics
        guard dynamics.taperOut > 0, travelled > Self.stepLength * 2 else { return }

        let last = steps[steps.count - 1]
        let length = CGFloat(dynamics.taperOut)
        let count = max(1, min(Int((length / Self.stepLength).rounded(.up)), Self.maximumStepsPerSpan))
        let target = min(CGFloat(dynamics.endScale), last.scale)

        for index in 1...count {
            let t = CGFloat(index) / CGFloat(count)
            let eased = t * t * (3 - 2 * t)
            let center = CGPoint(x: last.center.x + heading.dx * length * t,
                                 y: last.center.y + heading.dy * length * t)
            steps.append(StrokeStep(center: center, scale: max(last.scale + (target - last.scale) * eased, Self.minimumScale)))
        }
    }

    // MARK: Tip size

    /// The size the tip wants to be at the current speed: full when slow, smaller when fast.
    private func speedScale() -> CGFloat {
        let dynamics = brush.dynamics
        let normalized = min(max(speed / CGFloat(max(dynamics.referenceSpeed, 1)), 0), 1)
        return 1 - CGFloat(dynamics.speedResponse) * (1 - CGFloat(dynamics.minScale)) * normalized
    }

    /// Pressing harder (a larger contact area than usual for this stroke) makes the tip larger.
    private func contactFactor(_ radius: Double) -> CGFloat {
        let response = CGFloat(brush.dynamics.contactResponse)
        guard response > 0, radius > 0, contactAverage > 0 else { return 1 }
        let ratio = min(max(CGFloat(radius) / contactAverage, 0.5), 1.6)
        return pow(ratio, response)
    }

    /// The tip starts small and grows to full size over `taperIn` pixels.
    private func taperScale(travelled: CGFloat) -> CGFloat {
        let dynamics = brush.dynamics
        guard dynamics.taperIn > 0 else { return 1 }
        let progress = min(max(travelled / CGFloat(dynamics.taperIn), 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        let start = CGFloat(dynamics.startScale)
        return start + (1 - start) * eased
    }

    /// What a finger's contact area is normally like for this stroke, measured over its first few samples, so
    /// "pressing harder" means harder than usual rather than relying on absolute numbers.
    private func noteContact(_ radius: Double) {
        guard radius > 0, contactSamples < 8 else { return }
        contactAverage = (contactAverage * CGFloat(contactSamples) + CGFloat(radius)) / CGFloat(contactSamples + 1)
        contactSamples += 1
    }

    /// The fraction of the way a value moves toward its target after `dt` seconds, for a given time constant.
    private static func blend(dt: CGFloat, constant: CGFloat) -> CGFloat {
        1 - exp(-dt / constant)
    }
}
