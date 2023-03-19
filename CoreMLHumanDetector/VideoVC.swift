//
//  VideoVC.swift
//  CoreMLHumanDetector
//
//  Created by Bill Vivino on 3/18/23.
//

import Foundation
import UIKit
import AVFoundation
import Vision

class VideoVC: UIViewController {
    var player: AVPlayer?
    var model: Model?
    private var displayLink: CADisplayLink?
    private var playerItemOutput: AVPlayerItemVideoOutput?
    private var videoFileBufferOrientation = CGImagePropertyOrientation.up
    private var videoFileFrameDuration = CMTime.invalid
    private let videoFileReadingQueue = DispatchQueue(label: "VideoFileReading", qos: .userInteractive)
    private var videoRenderView: VideoRenderView!
    private let session = AVCaptureSession()
    
    var bufferSize: CGSize = UIScreen.main.bounds.size
    var rootLayer: CALayer! = nil
    private var detectionOverlay: CALayer! = nil
    
    // Vision parts
    private var requests = [VNRequest]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupAVCapture()
        
        if let asset = player?.currentItem?.asset {
            startReadingAsset(asset)
        } 
    }
    
    func setupAVCapture() {
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        session.beginConfiguration()
        session.sessionPreset = .vga640x480 // Model image size is smaller.
        do {
            try  videoDevice!.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            videoDevice!.unlockForConfiguration()
        } catch {
            print(error)
        }
        session.commitConfiguration()
        // setup Vision parts
        rootLayer = view.layer
        
        setupLayers()
        updateLayerGeometry()
        setupVision()
        
        // start the capture
//        startCaptureSession()
    }
    
    func updateLayerGeometry() {
        let bounds = rootLayer.bounds
        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
    }
    
    //MARK: - start reading assets
    func startReadingAsset(_ asset: AVAsset) {
        videoRenderView = VideoRenderView(frame: view.bounds)
        setupVideoOutputView(videoRenderView)
        
        // Setup display link
        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        displayLink.preferredFramesPerSecond = 0 // Use display's rate
        displayLink.isPaused = true
        displayLink.add(to: RunLoop.current, forMode: .default)
        
        guard let track = asset.tracks(withMediaType: .video).first else {
            print("No video tracks found in AVAsset.")
            return
        }

        guard let playerItem = player?.currentItem else {return}
        
        let settings = [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
        playerItem.add(output)
        player?.actionAtItemEnd = .pause
        player?.play()
        self.displayLink = displayLink
        self.playerItemOutput = output
        self.videoRenderView.player = player!

        let affineTransform = track.preferredTransform.inverted()
        let angleInDegrees = atan2(affineTransform.b, affineTransform.a) * CGFloat(180) / CGFloat.pi
        var orientation: UInt32 = 1
        switch angleInDegrees {
        case 0:
            orientation = 1 // Recording button is on the right
        case 180, -180:
            orientation = 3 // abs(180) degree rotation recording button is on the right
        case 90:
            orientation = 8 // 90 degree CW rotation recording button is on the top
        case -90:
            orientation = 6 // 90 degree CCW rotation recording button is on the bottom
        default:
            orientation = 1
        }
        videoFileBufferOrientation = CGImagePropertyOrientation(rawValue: orientation)!
        videoFileFrameDuration = track.minFrameDuration
        displayLink.isPaused = false
    }
    
    func setupLayers() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }
    
    //MARK: Video output stuff
    
    func setupVideoOutputView(_ videoOutputView: UIView) {
        videoOutputView.translatesAutoresizingMaskIntoConstraints = false
//        videoOutputView.backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        videoOutputView.layer.addSublayer(detectionOverlay)
        view.addSubview(videoOutputView)
        let _ = view.bottomAnchor

        videoOutputView.bounds = UIScreen.main.bounds
        NSLayoutConstraint.activate([
            videoOutputView.leftAnchor.constraint(equalTo: view.leftAnchor),
            videoOutputView.rightAnchor.constraint(equalTo: view.rightAnchor),
            videoOutputView.topAnchor.constraint(equalTo: view.topAnchor),
            videoOutputView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc
    private func handleDisplayLink(_ displayLink: CADisplayLink) {
        guard let output = playerItemOutput else {
            return
        }
        
        videoFileReadingQueue.async {
            let nextTimeStamp = displayLink.timestamp + displayLink.duration
            let itemTime = output.itemTime(forHostTime: nextTimeStamp)
            guard output.hasNewPixelBuffer(forItemTime: itemTime) else {
                return
            }
            guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
                return
            }
            // Create sample buffer from pixel buffer
            var sampleBuffer: CMSampleBuffer?
            var formatDescription: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
            let duration = self.videoFileFrameDuration
            var timingInfo = CMSampleTimingInfo(duration: duration, presentationTimeStamp: itemTime, decodeTimeStamp: itemTime)
            CMSampleBufferCreateForImageBuffer(allocator: nil,
                                               imageBuffer: pixelBuffer,
                                               dataReady: true,
                                               makeDataReadyCallback: nil,
                                               refcon: nil,
                                               formatDescription: formatDescription!,
                                               sampleTiming: &timingInfo,
                                               sampleBufferOut: &sampleBuffer)
            if let sampleBuffer = sampleBuffer {
              self.recievebuffer(sampleBuffer, orientation: self.videoFileBufferOrientation)
            }
        }
    }
    
    func recievebuffer(_ buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        let visionHandler = VNImageRequestHandler(cmSampleBuffer: buffer, orientation: orientation, options: [:])

        DispatchQueue.main.async {
            // Get the frame of rendered view
            let normalizedFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        
        do {
            try visionHandler.perform(self.requests)
            if let request = self.requests.first,
               let results = request.results {
                self.drawVisionRequestResults(results)
            }
        }
        catch {
            //
        }
    }
    
    @discardableResult
    func setupVision() -> NSError? {
        // Setup Vision parts
        let error: NSError! = nil
        var modelResourceString = ""
        
        if let model = model,
           model == .modelOne {
            modelResourceString = "YOLOv3FP16"
        } else if let model = model,
                  model == .modelTwo {
            modelResourceString = "YOLOv3TinyFP16"
        }
        
        guard let modelURL = Bundle.main.url(forResource: modelResourceString, withExtension: "mlmodelc") else {
            print("Model file is missing")
            return NSError(domain: "VideoVC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }
        
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        self.drawVisionRequestResults(results)
                    }
                })
            })
            self.requests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
        
        return error
    }
    
    func drawVisionRequestResults(_ results: [Any]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil // remove all the old recognized objects
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)
            
//            let textLayer = self.createTextSubLayerInBounds(objectBounds,
//                                                            identifier: topLabelObservation.identifier,
//                                                            confidence: topLabelObservation.confidence)
//            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CAShapeLayer {
        let shapeLayer = CAShapeLayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        let path = UIBezierPath(rect: bounds)
        shapeLayer.path = path.cgPath
        shapeLayer.lineWidth = 5.0
        
        print(shapeLayer.position)
        let viewBounds = VNImageRectForNormalizedRect(CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 1, height: 1)), Int(bufferSize.width), Int(bufferSize.height))
        print(viewBounds.midX, viewBounds.midY)
        if shapeLayer.position.x > viewBounds.midX - 100 &&
            shapeLayer.position.x < viewBounds.midX + 100 &&
            shapeLayer.position.y > viewBounds.midY - 100 &&
            shapeLayer.position.y < viewBounds.midY + 100 {
            shapeLayer.strokeColor = UIColor.green.cgColor
        } else {
            shapeLayer.strokeColor = UIColor.red.cgColor
        }
        shapeLayer.fillColor = UIColor.clear.cgColor
        
        return shapeLayer
    }
}

class VideoRenderView: UIView {
    private var renderLayer: AVPlayerLayer!
    
    var player: AVPlayer? {
        get {
            return renderLayer.player
        }
        set {
            renderLayer.player = newValue
        }
    }
    
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        renderLayer = layer as? AVPlayerLayer
        renderLayer.videoGravity = .resizeAspect
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
