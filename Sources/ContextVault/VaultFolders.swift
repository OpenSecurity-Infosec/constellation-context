import Foundation

/// Folder projection shared by base and linked filesystem vaults.
public enum VaultFolders {
    public static func paths(in notes: [VaultNoteSummary]) -> [String] {
        var paths = Set<String>()
        for note in notes {
            var path = (note.ref.noteID as NSString).deletingLastPathComponent
            while !path.isEmpty && path != "." {
                paths.insert(path)
                path = (path as NSString).deletingLastPathComponent
            }
        }
        return paths.sorted()
    }

    public static func contains(_ noteID: String, in folder: String) -> Bool {
        noteID.hasPrefix(folder + "/")
    }
}
