import Foundation

/// A graph of ``R4Module``s with a single output module, flattened into a
/// back-to-front render order (inputs before the modules that consume them).
public final class ModuleGraph {

    /// The module whose result is displayed (R4 Construct: the last module).
    public let output: R4Module

    /// Modules in render order: dependencies first, `output` last.
    private let order: [R4Module]

    public init(output: R4Module) {
        self.output = output
        // Post-order DFS so every module renders after its inputs, de-duplicated.
        var seen = Set<ObjectIdentifier>()
        var ordered: [R4Module] = []
        func visit(_ m: R4Module) {
            let key = ObjectIdentifier(m)
            guard !seen.contains(key) else { return }
            seen.insert(key)
            m.inputs.forEach(visit)
            ordered.append(m)
        }
        visit(output)
        self.order = ordered
    }

    /// The module names in render order (inputs first) — useful for inspection.
    public var renderOrder: [String] { order.map { $0.name } }

    public func reset() { order.forEach { $0.reset() } }

    public func render(_ audio: AudioFrame, gl: GL) {
        for module in order { module.render(audio, gl: gl) }
    }
}

/// Adapts a ``ModuleGraph`` to the ``R4Scene`` interface so graph-built scenes
/// drop straight into the registry alongside hand-written scenes.
public final class GraphScene: R4Scene {
    public let id: String
    public let name: String
    public let author: String
    private let graph: ModuleGraph

    public init(id: String, name: String, author: String = "", output: R4Module) {
        self.id = id
        self.name = name
        self.author = author
        self.graph = ModuleGraph(output: output)
    }

    public func reset() { graph.reset() }
    public func render(_ audio: AudioFrame, gl: GL) { graph.render(audio, gl: gl) }
}
