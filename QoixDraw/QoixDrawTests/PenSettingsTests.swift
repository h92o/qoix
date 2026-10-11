import Combine
import SwiftUI
import UIKit
import XCTest
@testable import QoixDraw

final class PenSettingsTests: XCTestCase {
    /// A throwaway place to remember settings, so the tests never touch the real preferences.
    private func makeDefaults() throws -> UserDefaults {
        let name = "qoixdraw-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    // MARK: Ink

    func testStartsWithTheDefaultPenAndTheFirstInk() {
        let settings = PenSettings(defaults: nil)
        XCTAssertEqual(settings.preset, AppConfig.defaultPreset)
        XCTAssertEqual(settings.colorIndex, 0)
        XCTAssertEqual(settings.paletteColor, Palette.colors[0])
    }

    func testCyclingStepsThroughEveryInkInOrderAndWrapsAround() {
        let settings = PenSettings(defaults: nil)
        var seen = [settings.paletteColor.name]
        for _ in 1..<Palette.colors.count {
            seen.append(settings.cycleColor().name)
        }
        XCTAssertEqual(seen, Palette.colors.map(\.name))
        XCTAssertEqual(settings.cycleColor(), Palette.colors[0], "after the last ink comes the first again")
        XCTAssertEqual(settings.colorIndex, 0)
    }

    func testPaletteWrapHandlesAnyInteger() {
        let count = Palette.colors.count
        XCTAssertEqual(Palette.wrap(0), 0)
        XCTAssertEqual(Palette.wrap(count), 0)
        XCTAssertEqual(Palette.wrap(-1), count - 1)
        XCTAssertEqual(Palette.wrap(count * 3 + 2), 2)
        XCTAssertEqual(Palette.wrap(-count * 2 - 1), count - 1)
    }

    func testThePaletteHasDistinctOpaqueInks() {
        let names = Palette.colors.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        for ink in Palette.colors {
            XCTAssertEqual(ink.color.alpha, 1, "\(ink.name) must be opaque")
        }
        for (index, ink) in Palette.colors.enumerated() {
            for other in Palette.colors[(index + 1)...] {
                XCTAssertNotEqual(ink.color, other.color, "\(ink.name) and \(other.name) look the same")
            }
        }
    }

    func testAnOutOfRangeSavedInkIsBroughtBackIntoRange() throws {
        let defaults = try makeDefaults()
        defaults.set(99, forKey: "penSettings.colorIndex")
        let settings = PenSettings(defaults: defaults)
        XCTAssertEqual(settings.colorIndex, Palette.wrap(99))
        XCTAssertEqual(settings.paletteColor, Palette.colors[Palette.wrap(99)])
    }

    // MARK: Remembering

    func testTheChoiceIsRememberedBetweenLaunches() throws {
        let defaults = try makeDefaults()
        let first = PenSettings(defaults: defaults)
        first.preset = .oval35
        first.preset.angleDegrees = 52
        first.colorIndex = 3

        let second = PenSettings(defaults: defaults)
        XCTAssertEqual(second.preset.name, BrushPreset.oval35.name)
        XCTAssertEqual(second.preset.shape, .ellipse)
        XCTAssertEqual(second.preset.angleDegrees, 52)
        XCTAssertEqual(second.colorIndex, 3)
    }

    func testCyclingTheInkIsRemembered() throws {
        let defaults = try makeDefaults()
        let first = PenSettings(defaults: defaults)
        first.cycleColor()
        first.cycleColor()
        XCTAssertEqual(PenSettings(defaults: defaults).colorIndex, 2)
    }

    func testASavedPenThatCannotBeReadFallsBackToTheGivenOne() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "penSettings.preset")
        let settings = PenSettings(defaults: defaults, preset: .marker)
        XCTAssertEqual(settings.preset, .marker)
    }

    func testNothingIsRememberedWithoutADefaultsObject() {
        let settings = PenSettings(defaults: nil)
        settings.cycleColor()
        settings.preset = .pointed
        XCTAssertEqual(PenSettings(defaults: nil).colorIndex, 0)
        XCTAssertEqual(PenSettings(defaults: nil).preset, AppConfig.defaultPreset)
    }

    func testObserversHearAboutChanges() {
        let settings = PenSettings(defaults: nil)
        var changes = 0
        let subscription = settings.objectWillChange.sink { _ in
            changes += 1
        }
        settings.cycleColor()
        settings.preset.angleDegrees += 5
        XCTAssertEqual(changes, 2)
        subscription.cancel()
    }

    // MARK: From a preset to a brush

    func testTheBrushUsesTheChosenInkAndConvertsPointsToPixels() {
        let settings = PenSettings(defaults: nil, preset: .chisel45)
        settings.colorIndex = 2
        let brush = settings.brush(pixelsPerPoint: 2)

        XCTAssertEqual(brush.color, Palette.colors[2].color)
        XCTAssertEqual(brush.nib.shape, .rectangle)
        XCTAssertEqual(brush.nib.length, 24, accuracy: 1e-9)
        XCTAssertEqual(brush.nib.thickness, 2.4, accuracy: 1e-9)
        XCTAssertEqual(brush.nib.angleDegrees, 45)
    }

    func testSpeedAndTaperDistancesScaleWithTheCanvasButRatiosDoNot() {
        let brush = BrushPreset.roundBrush.brush(color: .black, pixelsPerPoint: 2)
        XCTAssertEqual(brush.dynamics.referenceSpeed, 1800, accuracy: 1e-9)
        XCTAssertEqual(brush.dynamics.taperIn, 28, accuracy: 1e-9)
        XCTAssertEqual(brush.dynamics.taperOut, 56, accuracy: 1e-9)
        XCTAssertEqual(brush.dynamics.speedResponse, 0.85, accuracy: 1e-9)
        XCTAssertEqual(brush.dynamics.minScale, 0.2, accuracy: 1e-9)
        XCTAssertEqual(brush.dynamics.endScale, 0.05, accuracy: 1e-9)
    }

    func testTheBuiltInPensAreSensible() {
        let names = BrushPreset.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "names identify the pens, so they must be unique")
        XCTAssertTrue(BrushPreset.all.contains(AppConfig.defaultPreset))
        for preset in BrushPreset.all {
            XCTAssertGreaterThan(preset.lengthPoints, 0, preset.name)
            XCTAssertGreaterThan(preset.thicknessPoints, 0, preset.name)
            XCTAssertTrue((0...1).contains(preset.speedResponse), preset.name)
            XCTAssertTrue((0...1).contains(preset.contactResponse), preset.name)
            XCTAssertTrue((0...1).contains(preset.minScale), preset.name)
            XCTAssertGreaterThan(preset.referenceSpeedPoints, 0, preset.name)
        }
    }

    func testEveryPenSurvivesBeingSavedAndLoaded() throws {
        for preset in BrushPreset.all {
            let data = try JSONEncoder().encode(preset)
            XCTAssertEqual(try JSONDecoder().decode(BrushPreset.self, from: data), preset)
        }
    }

    func testTheCalligraphyPensHaveTheLookOfTheirNames() {
        // A flat pen's edge at 45 degrees points up-right on screen: strokes along it are hairlines, strokes across
        // it are broad. The edge is much longer than the pen is thick, or there would be little difference.
        XCTAssertEqual(BrushPreset.chisel45.shape, .rectangle)
        XCTAssertEqual(BrushPreset.chisel45.angleDegrees, 45)
        XCTAssertEqual(BrushPreset.chisel30.angleDegrees, 30)
        XCTAssertEqual(BrushPreset.oval35.shape, .ellipse)
        XCTAssertGreaterThan(BrushPreset.chisel45.lengthPoints, 4 * BrushPreset.chisel45.thicknessPoints)
        // Brush-like pens respond to speed and taper; the flat pens stay rigid.
        XCTAssertEqual(BrushPreset.chisel45.speedResponse, 0)
        XCTAssertGreaterThan(BrushPreset.roundBrush.speedResponse, 0.5)
        XCTAssertGreaterThan(BrushPreset.roundBrush.taperOutPoints, 0)
    }
}

@MainActor
final class BrushSettingsViewTests: XCTestCase {
    /// How many pixels in `image` are clearly ink (dark) rather than the white paper.
    private func inkedPixels(in image: UIImage) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage)
        let bytes = try XCTUnwrap(pixelBytes(of: cgImage))
        var count = 0
        var offset = 0
        while offset + 3 < bytes.count {
            if bytes[offset] < 128 {
                count += 1
            }
            offset += 4
        }
        return count
    }

    func testEveryBuiltInPenPreviewsWithInkOnPaper() throws {
        for preset in BrushPreset.all {
            let image = try XCTUnwrap(BrushPreviewRenderer.image(for: preset, color: .black), preset.name)
            XCTAssertEqual(image.cgImage?.width, 800)
            XCTAssertEqual(image.cgImage?.height, 280)
            let ink = try inkedPixels(in: image)
            XCTAssertGreaterThan(ink, 800, "\(preset.name) should leave a visible specimen")
            XCTAssertLessThan(ink, 800 * 280 / 2, "\(preset.name) should not fill the preview")
        }
    }

    func testThePreviewFollowsTheInkAndTheSize() throws {
        let thin = try inkedPixels(in: try XCTUnwrap(BrushPreviewRenderer.image(for: .marker, color: .black)))
        var bold = BrushPreset.marker
        bold.lengthPoints = 12
        bold.thicknessPoints = 12
        let thick = try inkedPixels(in: try XCTUnwrap(BrushPreviewRenderer.image(for: bold, color: .black)))
        XCTAssertGreaterThan(thick, thin * 2, "a 12 pt pen must show far more ink than a 4 pt one")

        let white = try inkedPixels(in: try XCTUnwrap(BrushPreviewRenderer.image(for: .marker, color: .white)))
        XCTAssertEqual(white, 0, "white ink on white paper leaves nothing dark")
    }

    func testTheBrushSheetBuildsAndLaysOut() {
        let settings = PenSettings(defaults: nil)
        let host = UIHostingController(rootView: BrushSettingsView(settings: settings))
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 760)
        host.view.layoutIfNeeded()
        XCTAssertFalse(host.view.subviews.isEmpty)
    }
}
