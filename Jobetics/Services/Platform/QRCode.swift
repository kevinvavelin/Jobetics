import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QRCode {
    /// Crisp QR code image for any string (vCard, URL…). Scanning a vCard QR with the Camera adds the contact.
    static func image(for string: String, size: CGFloat = 600) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
