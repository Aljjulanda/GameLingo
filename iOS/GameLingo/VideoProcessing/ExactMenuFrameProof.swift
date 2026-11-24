import Foundation
import CoreVideo
import CryptoKit

/// Only for a slow, real OCR read: identical decoded pixels can prove that its
/// input is still visible in a newly arrived frame. This is never an OCR read
/// or an extra stability confirmation. No sampled/perceptual comparison.
enum ExactMenuFrameProof {
    static func matches(_ input: CVPixelBuffer, _ current: CVPixelBuffer) -> Bool {
        guard CVPixelBufferGetWidth(input) == CVPixelBufferGetWidth(current),
              CVPixelBufferGetHeight(input) == CVPixelBufferGetHeight(current),
              CVPixelBufferGetPixelFormatType(input) == CVPixelBufferGetPixelFormatType(current),
              let before = digest(input), let after = digest(current) else { return false }
        return before == after
    }
    private static func digest(_ buffer: CVPixelBuffer) -> Data? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard [kCVPixelFormatType_32BGRA,kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,kCVPixelFormatType_420YpCbCr8BiPlanarFullRange].contains(format),
              CVPixelBufferGetWidth(buffer) > 0, CVPixelBufferGetHeight(buffer) > 0,
              CVPixelBufferLockBaseAddress(buffer,.readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        var hash = SHA256()
        if format == kCVPixelFormatType_32BGRA {
            guard !CVPixelBufferIsPlanar(buffer), let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let bytes = CVPixelBufferGetWidth(buffer)*4, stride = CVPixelBufferGetBytesPerRow(buffer)
            guard stride >= bytes else { return nil }
            for row in 0..<CVPixelBufferGetHeight(buffer) {
                hash.update(data:Data(bytes:base.advanced(by:row*stride),count:bytes))
            }
        } else {
            guard CVPixelBufferIsPlanar(buffer), CVPixelBufferGetPlaneCount(buffer) == 2 else { return nil }
            for plane in 0..<2 {
                guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer,plane) else { return nil }
                let bytes = CVPixelBufferGetWidthOfPlane(buffer,plane)*(plane == 0 ? 1 : 2)
                let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer,plane)
                let height = CVPixelBufferGetHeightOfPlane(buffer,plane)
                guard stride >= bytes, bytes > 0, height > 0 else { return nil }
                for row in 0..<height {
                    hash.update(data:Data(bytes:base.advanced(by:row*stride),count:bytes))
                }
            }
        }
        // Only active pixels are included; allocator padding is not image data.
        return Data(hash.finalize())
    }
}
