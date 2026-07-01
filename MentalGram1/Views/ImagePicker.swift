import SwiftUI
import PhotosUI

/// SwiftUI wrapper for PHPickerViewController
/// Allows user to select images from photo library
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImageData: Data?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images // Only images, no videos
        config.selectionLimit = 1 // Only one image
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            
            guard let result = results.first else {
                print("📸 [PICKER] No image selected - cancelled")
                return
            }
            
            print("📸 [PICKER] Image selected, loading...")
            // Load image data
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let error = error {
                    print("❌ [PICKER] Failed to load image: \(error.localizedDescription)")
                    return
                }
                if let image = object as? UIImage {
                    // Convert to JPEG data
                    DispatchQueue.main.async {
                        let jpegData = image.jpegData(compressionQuality: 0.9)
                        self.parent.selectedImageData = jpegData
                        print("✅ [PICKER] Image loaded: \(jpegData?.count ?? 0) bytes")
                        LogManager.shared.info("Profile pic image selected: \(jpegData?.count ?? 0) bytes", category: .general)
                    }
                } else {
                    print("❌ [PICKER] Failed to convert object to UIImage")
                }
            }
        }
    }
}
