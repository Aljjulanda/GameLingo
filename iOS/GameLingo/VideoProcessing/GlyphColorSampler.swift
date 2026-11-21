import CoreImage
import CoreVideo

/// Approximate sRGB glyph color after stream decoding. Background is estimated
/// from the perimeter; only contrasted interior pixels with a local edge vote.
/// This is not a measurement of the television's HDR output or original font.
enum GlyphColorSampler {
    static func sample(_ buffer: CVPixelBuffer, box: SourceBox, context: CIContext) -> String? {
        guard box.isValid else { return nil }
        let image = CIImage(cvPixelBuffer:buffer), width = image.extent.width, height = image.extent.height
        let rect = CGRect(x:box.x*width,y:(1-box.y-box.h)*height,width:box.w*width,height:box.h*height).integral
        guard let cg = context.createCGImage(image.cropped(to:rect),from:rect) else { return nil }
        let w = 160, h = 32
        var pixels = [UInt8](repeating:0,count:w*h*4)
        let result: String? = pixels.withUnsafeMutableBytes { raw in
            guard let canvas = CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            canvas.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
            let bytes = raw.bindMemory(to:UInt8.self)
            func rgb(_ x: Int,_ y: Int) -> [Int] { let i = (y*w+x)*4; return [Int(bytes[i]),Int(bytes[i+1]),Int(bytes[i+2])] }
            let border = (0..<w).flatMap { [rgb($0,0),rgb($0,h-1)] }
            let bg = (0..<3).map { channel in border.map{$0[channel]}.sorted()[border.count/2] }
            var buckets: [Int:(Int,[Int])] = [:]
            for y in 2..<h-2 { for x in 2..<w-2 {
                let c = rgb(x,y), neighbor = rgb(x+1,y)
                guard zip(c,bg).map({abs($0-$1)}).max()! > 65, zip(c,neighbor).map({abs($0-$1)}).max()! > 18 else { continue }
                let key = (c[0]/32)*64+(c[1]/32)*8+c[2]/32
                let previous = buckets[key] ?? (0,[0,0,0])
                buckets[key] = (previous.0+1,zip(previous.1,c).map(+))
            } }
            guard let cluster = buckets.values.max(by:{$0.0 < $1.0}), cluster.0 >= 6 else { return nil }
            let c = cluster.1.map{$0/cluster.0}
            return String(format:"#%02X%02X%02X",c[0],c[1],c[2])
        }
        return result
    }
}
