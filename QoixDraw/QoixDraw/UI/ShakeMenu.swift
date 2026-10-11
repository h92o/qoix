import Foundation

/// What the shake menu offers, decided from the state of the canvas. Pure logic so it can be tested.
///
/// The system's own shake-to-undo alert only knows about undo and redo. This menu adds "Clear Canvas", which is
/// how you discard a drawing without saving it (clearing is itself undoable), and "Brush & Color", which opens
/// the brush sheet.
enum ShakeMenu {
    enum Item: Equatable {
        case undo
        case redo
        case clearCanvas
        case brushSettings
    }

    static func items(canUndo: Bool, canRedo: Bool, canClear: Bool) -> [Item] {
        var items: [Item] = []
        if canUndo {
            items.append(.undo)
        }
        if canRedo {
            items.append(.redo)
        }
        if canClear {
            items.append(.clearCanvas)
        }
        items.append(.brushSettings)
        return items
    }
}
