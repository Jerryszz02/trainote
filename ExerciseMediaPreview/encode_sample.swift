import AVFoundation
import CoreGraphics
import ImageIO

// macOS system encoder; no ffmpeg or downloaded executable is needed.
guard CommandLine.arguments.count == 3 else {
  fatalError("Usage: swift encode_sample.swift <frames-directory> <new-output.mp4>")
}
let frames = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard !FileManager.default.fileExists(atPath: output.path) else {
  fatalError("Output exists; choose a new output path.")
}
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let width = 960, height = 600
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264,
  AVVideoWidthKey: width, AVVideoHeightKey: height,
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
  sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
  ])
writer.add(input)
guard writer.startWriting() else { throw writer.error! }
writer.startSession(atSourceTime: .zero)
for frame in 0..<72 {
  let url = frames.appendingPathComponent(String(format: "%03d.png", frame))
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let pool = adaptor.pixelBufferPool else { fatalError("Missing frame or buffer pool") }
  var optionalBuffer: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
  guard let buffer = optionalBuffer else { fatalError("Cannot allocate buffer") }
  CVPixelBufferLockBaseAddress(buffer, [])
  let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo:
      CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  CVPixelBufferUnlockBaseAddress(buffer, [])
  while !input.isReadyForMoreMediaData && writer.status == .writing {
    Thread.sleep(forTimeInterval: 0.005)
  }
  guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24))
  else { fatalError(writer.error?.localizedDescription ?? "Cannot append frame") }
}
input.markAsFinished()
writer.endSession(atSourceTime: CMTime(value: 3, timescale: 1))
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError(writer.error!.localizedDescription) }
print("Encoded 72 frames, 960×600, 24 fps, 3 seconds, no audio")
