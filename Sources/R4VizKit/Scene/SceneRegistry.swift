import Foundation

/// Holds the set of available scenes. Add a scene by dropping a file in
/// `Scenes/` and appending it in ``SceneRegistry/makeDefault()``.
public final class SceneRegistry {

    public private(set) var scenes: [R4Scene]

    public init(scenes: [R4Scene]) {
        self.scenes = scenes
    }

    public func scene(withID id: String) -> R4Scene? {
        scenes.first { $0.id == id }
    }

    public func register(_ scene: R4Scene) {
        scenes.append(scene)
    }

    /// The scenes bundled with this scaffold — reinterpretations of real R4
    /// scenes by Gordon Williams (RabidHamster).
    public static func makeDefault() -> SceneRegistry {
        SceneRegistry(scenes: [
            SpinnerScene(),
            ThumperScene(),
            CubeFieldScene(),
            SpectrumScene(),
            MedusaScene(),
        ])
    }
}
