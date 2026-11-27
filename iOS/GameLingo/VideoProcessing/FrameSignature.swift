import Foundation
import CoreVideo

/// A tiny edge mask from the decoder's existing luma plane; no rendered image or full-frame copy.
struct FrameSignature {
    /// 64-bit relative luma dHash; samples existing planes without a screenshot.
    static func perceptualHash(_ buffer: CVPixelBuffer) -> String {
        guard CVPixelBufferIsPlanar(buffer), CVPixelBufferGetPlaneCount(buffer) > 0 else { return "" }
        CVPixelBufferLockBaseAddress(buffer,.readOnly); defer{CVPixelBufferUnlockBaseAddress(buffer,.readOnly)}
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer,0) else { return "" }
        let w = CVPixelBufferGetWidthOfPlane(buffer,0), h = CVPixelBufferGetHeightOfPlane(buffer,0), stride = CVPixelBufferGetBytesPerRowOfPlane(buffer,0)
        guard w > 9, h > 8 else { return "" }
        let bytes = base.assumingMemoryBound(to:UInt8.self)
        var value: UInt64 = 0
        for y in 0..<8 { for x in 0..<8 {
            let row = (y*h/8)*stride
            value = (value << 1) | (bytes[row+x*w/9] > bytes[row+(x+1)*w/9] ? 1 : 0)
        } }
        return String(value,radix:16)
    }
    private var previous: [UInt8]?
    private var verified: TimeInterval = 0
    mutating func shouldRecognize(_ buffer: CVPixelBuffer, roi: SourceBox, now: TimeInterval, hasText: Bool) -> Bool {
        guard CVPixelBufferIsPlanar(buffer), CVPixelBufferGetPlaneCount(buffer) >= 2 else { return true }
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        guard let address = CVPixelBufferGetBaseAddressOfPlane(buffer,0) else { return true }
        let width = CVPixelBufferGetWidthOfPlane(buffer,0), height = CVPixelBufferGetHeightOfPlane(buffer,0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer,0), bytes = address.assumingMemoryBound(to:UInt8.self)
        guard width > 1, height > 1, roi.isValid else { return true }
        let columns = 96, rows = 32
        var samples = [UInt8](repeating:0,count:columns*rows)
        for row in 0..<rows {
            let y = min(height-1,max(0,Int((roi.y+roi.h*Double(row)/Double(rows))*Double(height))))
            for column in 0..<columns {
                let x = min(width-1,max(0,Int((roi.x+roi.w*Double(column)/Double(columns))*Double(width))))
                samples[row*columns+column] = bytes[y*stride+x]
            }
        }
        var edges = [UInt8](repeating:0,count:samples.count)
        for row in 0..<rows-1 {
            for column in 0..<columns-1 {
                let i = row*columns+column
                edges[i] = abs(Int(samples[i])-Int(samples[i+1])) >= 24 || abs(Int(samples[i])-Int(samples[i+columns])) >= 24 ? 1 : 0
            }
        }
        let changed = previous.map { old in zip(old,edges).filter { pair in pair.0 != pair.1 }.count > 3 } ?? true
        let periodic = now-verified >= (hasText ? 0.65 : 1.2)
        if changed || periodic { previous = edges; verified = now; return true }
        return false
    }
}
