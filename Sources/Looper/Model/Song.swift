import Foundation

/// One step of a song: a memory played `repeats` times.
struct SongStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var memory: Int
    var repeats: Int
}

/// A chain of memories (song mode). Stored in the user defaults.
struct Song: Codable, Equatable {
    var steps: [SongStep] = []
    var repeatSong = false

    static func load() -> Song {
        guard let data = UserDefaults.standard.data(forKey: "song"),
              let s = try? JSONDecoder().decode(Song.self, from: data) else { return Song() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "song") }
    }
}
