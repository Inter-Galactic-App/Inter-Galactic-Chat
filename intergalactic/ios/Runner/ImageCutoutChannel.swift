import CoreVideo
import Flutter
import UIKit
import Vision

final class ImageCutoutChannel {
  private static let channelName = "chat.intergalactic.app/image_cutout"
  private static let appleVisionBackend = "appleVisionSubjectLift"

  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "generateMask":
        handleGenerateMask(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func handleGenerateMask(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    let arguments = call.arguments as? [String: Any]
    let backend = arguments?["backend"] as? String
    guard backend == appleVisionBackend else {
      result(
        FlutterError(
          code: "unsupported_platform",
          message: "The requested image-cutout backend is not available on iOS.",
          details: nil
        )
      )
      return
    }

    guard let imageBytes = data(from: arguments?["imageBytes"]) else {
      result(
        FlutterError(
          code: "image_decode_failed",
          message: "The selected image could not be decoded.",
          details: nil
        )
      )
      return
    }

    let settings = arguments?["settings"] as? [String: Any] ?? [:]
    let maxProcessingDimension = positiveInt(
      from: settings["maxProcessingDimension"],
      fallback: 640
    )

    NSLog(
      "intergalactic_ios_image_cutout event=generate_mask_received backend=apple_vision byte_count=%d max_dimension=%d",
      imageBytes.count,
      maxProcessingDimension
    )

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let mask = try generateAppleVisionMask(
          imageBytes: imageBytes,
          maxProcessingDimension: maxProcessingDimension
        )
        NSLog(
          "intergalactic_ios_image_cutout event=generate_mask_succeeded backend=apple_vision width=%d height=%d alpha_count=%d",
          mask.width,
          mask.height,
          mask.alpha.count
        )
        DispatchQueue.main.async {
          result([
            "width": mask.width,
            "height": mask.height,
            "alpha": FlutterStandardTypedData(bytes: mask.alpha),
          ])
        }
      } catch let error as ImageCutoutBridgeError {
        NSLog(
          "intergalactic_ios_image_cutout event=generate_mask_failed backend=apple_vision code=%@",
          error.code
        )
        DispatchQueue.main.async {
          result(error.flutterError)
        }
      } catch {
        NSLog(
          "intergalactic_ios_image_cutout event=generate_mask_failed backend=apple_vision code=processing_failed"
        )
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "processing_failed",
              message: "Background removal could not process this image.",
              details: nil
            )
          )
        }
      }
    }
  }

  private static func generateAppleVisionMask(
    imageBytes: Data,
    maxProcessingDimension: Int
  ) throws -> CutoutMaskPayload {
    guard #available(iOS 17.0, *) else {
      throw ImageCutoutBridgeError(
        code: "unsupported_os_version",
        message: "Apple Vision subject lifting requires iOS 17 or newer."
      )
    }

    return try generateAppleVisionMaskIOS17(
      imageBytes: imageBytes,
      maxProcessingDimension: maxProcessingDimension
    )
  }

  @available(iOS 17.0, *)
  private static func generateAppleVisionMaskIOS17(
    imageBytes: Data,
    maxProcessingDimension: Int
  ) throws -> CutoutMaskPayload {
    let cgImage = try normalizedCGImage(
      from: imageBytes,
      maxProcessingDimension: maxProcessingDimension
    )
    let requestHandler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: .up,
      options: [:]
    )
    let request = VNGenerateForegroundInstanceMaskRequest()

    do {
      try requestHandler.perform([request])
    } catch {
      throw ImageCutoutBridgeError(
        code: "processing_failed",
        message: "Apple Vision could not process this image."
      )
    }

    guard let observation = request.results?.first else {
      throw ImageCutoutBridgeError(
        code: "no_subject_found",
        message: "No distinct foreground subject was found."
      )
    }

    guard observation.allInstances.count > 0 else {
      throw ImageCutoutBridgeError(
        code: "no_subject_found",
        message: "No distinct foreground subject was found."
      )
    }

    let maskBuffer: CVPixelBuffer
    do {
      maskBuffer = try observation.generateScaledMaskForImage(
        forInstances: observation.allInstances,
        from: requestHandler
      )
    } catch {
      throw ImageCutoutBridgeError(
        code: "processing_failed",
        message: "Apple Vision could not generate a foreground mask."
      )
    }

    return try alphaPayload(from: maskBuffer)
  }

  private static func normalizedCGImage(
    from imageBytes: Data,
    maxProcessingDimension: Int
  ) throws -> CGImage {
    guard let image = UIImage(data: imageBytes),
      image.size.width > 0,
      image.size.height > 0 else {
      throw ImageCutoutBridgeError(
        code: "image_decode_failed",
        message: "The selected image could not be decoded."
      )
    }

    let targetSize = scaledSize(
      from: image.size,
      maxProcessingDimension: maxProcessingDimension
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    let normalized = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }

    guard let cgImage = normalized.cgImage else {
      throw ImageCutoutBridgeError(
        code: "image_decode_failed",
        message: "The selected image could not be decoded."
      )
    }
    return cgImage
  }

  private static func scaledSize(
    from size: CGSize,
    maxProcessingDimension: Int
  ) -> CGSize {
    let maxDimension = max(1, maxProcessingDimension)
    let longestSide = max(size.width, size.height)
    guard longestSide > CGFloat(maxDimension) else {
      return CGSize(
        width: max(1, Int(size.width.rounded())),
        height: max(1, Int(size.height.rounded()))
      )
    }

    let scale = CGFloat(maxDimension) / longestSide
    return CGSize(
      width: max(1, Int((size.width * scale).rounded())),
      height: max(1, Int((size.height * scale).rounded()))
    )
  }

  private static func alphaPayload(
    from pixelBuffer: CVPixelBuffer
  ) throws -> CutoutMaskPayload {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    guard width > 0, height > 0 else {
      throw ImageCutoutBridgeError(
        code: "processing_failed",
        message: "Apple Vision returned an invalid foreground mask."
      )
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      throw ImageCutoutBridgeError(
        code: "processing_failed",
        message: "Apple Vision returned an unreadable foreground mask."
      )
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    var alpha = Data(count: width * height)

    try alpha.withUnsafeMutableBytes { rawDestination in
      guard let destination = rawDestination.bindMemory(to: UInt8.self).baseAddress else {
        throw ImageCutoutBridgeError(
          code: "processing_failed",
          message: "Apple Vision returned an unreadable foreground mask."
        )
      }

      switch pixelFormat {
      case kCVPixelFormatType_OneComponent8:
        copyOneComponent8(
          from: baseAddress,
          bytesPerRow: bytesPerRow,
          width: width,
          height: height,
          to: destination
        )
      case kCVPixelFormatType_OneComponent32Float:
        copyOneComponent32Float(
          from: baseAddress,
          bytesPerRow: bytesPerRow,
          width: width,
          height: height,
          to: destination
        )
      case kCVPixelFormatType_32BGRA:
        copyPackedAlpha(
          from: baseAddress,
          bytesPerRow: bytesPerRow,
          width: width,
          height: height,
          alphaOffset: 3,
          to: destination
        )
      case kCVPixelFormatType_32RGBA:
        copyPackedAlpha(
          from: baseAddress,
          bytesPerRow: bytesPerRow,
          width: width,
          height: height,
          alphaOffset: 3,
          to: destination
        )
      default:
        throw ImageCutoutBridgeError(
          code: "processing_failed",
          message: "Apple Vision returned an unsupported foreground-mask format."
        )
      }
    }

    guard alpha.contains(where: { $0 > 18 }) else {
      throw ImageCutoutBridgeError(
        code: "no_subject_found",
        message: "No distinct foreground subject was found."
      )
    }

    NSLog(
      "intergalactic_ios_image_cutout event=mask_format pixel_format=%u width=%d height=%d",
      pixelFormat,
      width,
      height
    )
    return CutoutMaskPayload(width: width, height: height, alpha: alpha)
  }

  private static func copyOneComponent8(
    from baseAddress: UnsafeMutableRawPointer,
    bytesPerRow: Int,
    width: Int,
    height: Int,
    to destination: UnsafeMutablePointer<UInt8>
  ) {
    for y in 0..<height {
      let source = baseAddress
        .advanced(by: y * bytesPerRow)
        .assumingMemoryBound(to: UInt8.self)
      destination.advanced(by: y * width).update(from: source, count: width)
    }
  }

  private static func copyOneComponent32Float(
    from baseAddress: UnsafeMutableRawPointer,
    bytesPerRow: Int,
    width: Int,
    height: Int,
    to destination: UnsafeMutablePointer<UInt8>
  ) {
    for y in 0..<height {
      let source = baseAddress
        .advanced(by: y * bytesPerRow)
        .assumingMemoryBound(to: Float32.self)
      for x in 0..<width {
        destination[y * width + x] = UInt8(
          max(0, min(255, Int((source[x] * 255).rounded())))
        )
      }
    }
  }

  private static func copyPackedAlpha(
    from baseAddress: UnsafeMutableRawPointer,
    bytesPerRow: Int,
    width: Int,
    height: Int,
    alphaOffset: Int,
    to destination: UnsafeMutablePointer<UInt8>
  ) {
    for y in 0..<height {
      let source = baseAddress
        .advanced(by: y * bytesPerRow)
        .assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        destination[y * width + x] = source[x * 4 + alphaOffset]
      }
    }
  }

  private static func data(from value: Any?) -> Data? {
    if let typedData = value as? FlutterStandardTypedData {
      return typedData.data
    }
    if let data = value as? Data {
      return data
    }
    if let bytes = value as? [UInt8] {
      return Data(bytes)
    }
    return nil
  }

  private static func positiveInt(from value: Any?, fallback: Int) -> Int {
    if let value = value as? Int, value > 0 {
      return value
    }
    if let value = value as? NSNumber, value.intValue > 0 {
      return value.intValue
    }
    return fallback
  }
}

private struct CutoutMaskPayload {
  let width: Int
  let height: Int
  let alpha: Data
}

private struct ImageCutoutBridgeError: Error {
  let code: String
  let message: String

  var flutterError: FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
