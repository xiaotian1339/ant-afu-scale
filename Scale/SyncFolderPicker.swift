import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 使用原生目录选择回调，避免 SwiftUI fileImporter 在 iOS 26 上无法完成空目录选择。
@MainActor
struct SyncFolderPicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 必须打开原目录；复制目录不会保留后续跨设备同步所需的访问授权。
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onSelect: (URL) -> Void
        private let onCancel: () -> Void
        private var completed = false

        init(onSelect: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !completed else { return }
            completed = true
            guard let url = urls.first else { onCancel(); return }
            // 在关闭选择器之前创建安全书签，避免依赖已释放的临时文件授权。
            onSelect(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !completed else { return }
            completed = true
            onCancel()
        }
    }
}
