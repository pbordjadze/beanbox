import PhotosUI
import SwiftUI
import UIKit

/// "Add photo" plus the photos already added, shared by every tab. Selecting one makes it the
/// photo `tab` works on.
struct PhotoStrip: View {
    let tab: AppTab
    @Environment(Project.self) private var project
    @State private var isShowingCamera = false
    @State private var isBrowsing = false
    @State private var picked: PhotosPickerItem?
    @State private var deleting: PhotoRecord?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                addButton
                ForEach(project.data.photos.reversed()) { photo in
                    thumbnail(photo)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .photosPicker(isPresented: $isBrowsing, selection: $picked, matching: .images, preferredItemEncoding: .current)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { data in
                Task { await project.addPhoto(data, for: tab) }
            } onFailure: {
                project.problem = "The camera didn’t return a photo."
            }
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    project.problem = "That photo couldn’t be loaded from your library."
                    return
                }
                await project.addPhoto(data, for: tab)
            }
        }
        .confirmationDialog(
            "Delete this photo?", isPresented: .constant(deleting != nil), titleVisibility: .visible, presenting: deleting
        ) { photo in
            Button("Delete Photo", role: .destructive) {
                project.deletePhoto(photo.id)
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { _ in
            Text("Colours already measured from it are kept.")
        }
    }

    private var addButton: some View {
        Menu {
            if cameraAvailable {
                Button("Take Photo", systemImage: "camera") { isShowingCamera = true }
            }
            Button("Choose Photo", systemImage: "photo.on.rectangle") { isBrowsing = true }
        } label: {
            Group {
                if project.isImporting {
                    ProgressView()
                } else {
                    Label("Add Photo", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.title2.weight(.semibold))
                }
            }
            .frame(width: 64, height: 64)
            .foregroundStyle(.white)
            .background(Theme.ink, in: .rect(cornerRadius: 12))
        }
        .disabled(project.isImporting)
        .accessibilityIdentifier("add-photo")
    }

    private func thumbnail(_ photo: PhotoRecord) -> some View {
        let selected = project.focus[tab] == photo.id
        return Button {
            project.focus[tab] = photo.id
        } label: {
            Group {
                if let image = project.thumbnails[photo.id] {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Theme.hairline
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.ink : Theme.hairline, lineWidth: selected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "Photo, selected" : "Photo")
        .contextMenu {
            Button("Delete Photo", systemImage: "trash", role: .destructive) { deleting = photo }
        }
    }
}

/// The system camera; hands back the photo as JPEG data (orientation preserved in EXIF), or
/// reports that the shot couldn't be used.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onFailure: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
                parent.onCapture(data)
            } else {
                parent.onFailure()
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
