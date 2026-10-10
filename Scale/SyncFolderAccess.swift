import Foundation

/// 同步只能访问应用沙盒中的本地目录或系统标记的 iCloud 项目。
/// 不根据文件夹名称猜测提供商；无法验证归属的文件夹也拒绝访问。
enum SyncFolderAccess {
    enum ValidationError: LocalizedError {
        case notDirectory
        case unsupportedProvider

        var errorDescription: String? {
            switch self {
            case .notDirectory: return "请选择文件夹，而不是文件。"
            case .unsupportedProvider: return "请选择「iCloud 云盘」中的文件夹。为保护测量数据，不支持第三方文件服务或无法验证来源的目录。"
            }
        }
    }

    static func validate(_ url: URL) throws {
        guard url.isFileURL else { throw ValidationError.unsupportedProvider }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw ValidationError.unsupportedProvider }
        guard values.isDirectory == true else { throw ValidationError.notDirectory }
        if isAppLocalDirectory(url) { return }
        guard values.isUbiquitousItem == true else { throw ValidationError.unsupportedProvider }
    }

    static func isAppLocalDirectory(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).contains { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }
}
