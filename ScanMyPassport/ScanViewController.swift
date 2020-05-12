//
//  ViewController.swift
//  ScanMyPassport
//
//  Created by Kyra McKenna on 16/04/2020.
//  Copyright © 2020 Daon. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ScanViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var capturedImageView: UIImageView!
    
    @IBOutlet weak var sheenView: UIView!
    @IBOutlet weak var scanButton: UIButton!
    
    var bImageCaptured = true
    
    
    private let captureSession = AVCaptureSession()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private let videoDataOutput = AVCaptureVideoDataOutput()

    private var isTapped = false
    
    private var maskLayer = CAShapeLayer()
    private var drawings: [CAShapeLayer] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setCameraInput()
        self.showCameraFeed()
        self.setCameraOutput()
    }
    
    override func viewDidAppear(_ animated: Bool) {

        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        self.captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        
        self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        self.captureSession.stopRunning()
    }
    
    func doPerspectiveCorrection(_ observation: VNRectangleObservation, from buffer: CVImageBuffer) {
        var ciImage = CIImage(cvImageBuffer: buffer)

        let topLeft = observation.topLeft.scaled(to: ciImage.extent.size)
        let topRight = observation.topRight.scaled(to: ciImage.extent.size)
        let bottomLeft = observation.bottomLeft.scaled(to: ciImage.extent.size)
        let bottomRight = observation.bottomRight.scaled(to: ciImage.extent.size)

        // pass those to the filter to extract/rectify the image
        ciImage = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight),
        ])

        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let output = UIImage(cgImage: cgImage!)
        
        bImageCaptured = true
        self.removeMask()
        
        
        //UIImageWriteToSavedPhotosAlbum(output, nil, nil, nil)
        
        // fade in the scanned image
        UIView.transition(with: self.view, duration:0.5, options:.curveEaseOut, animations:{
            
            self.capturedImageView.isHidden = false
            self.capturedImageView.image = output
            self.capturedImageView.alpha = 1.0
        
            self.videoView.alpha = 0.3
            
            self.captureSession.stopRunning()
            
            self.scanButton.alpha = 0.5
            self.scanButton.isEnabled = false
            self.removeMask()
            
            self.sheenView.alpha = 0.4
            self.sheenView.isHidden = false
            
        }, completion:{ finished in})
    }
    
    
    @IBAction func startAgain(_ sender: Any) {
        
        self.removeMask()
        
        UIView.transition(with: self.view, duration:0.5, options:.curveEaseOut, animations:{
            
            self.bImageCaptured = false
            self.captureSession.startRunning()
            
            self.capturedImageView.image = nil
            self.capturedImageView.alpha = 0.0
            self.capturedImageView.isHidden = true

            self.videoView.alpha = 1.0
            
            self.scanButton.alpha = 1.0
            self.scanButton.isEnabled = true
            
            self.sheenView.alpha = 0
            self.sheenView.isHidden = true
            
        }, completion:{ finished in})
        
        self.isTapped = false
    }
    
    @IBAction func captureImage(_ sender: Any) {
        
        self.scanButton.alpha = 0.5
        self.scanButton.isEnabled = false
        
        self.capturedImageView.isHidden = true
        self.isTapped = true
    }
    
    @objc func doScan(sender: UIButton!){
        self.isTapped = true
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.view.frame
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection) {
        
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            debugPrint("unable to get image from sample buffer")
            return
        }
        
        self.detectFace(in: frame)
    }
    
    private func handleFaceDetectionResults(_ observedFaces: [VNFaceObservation], image: CVPixelBuffer) {
        self.clearDrawings()

        let facesBoundingBoxes: [CAShapeLayer] = observedFaces.map({ (observedFace: VNFaceObservation) -> CAShapeLayer in
            let faceBoundingBoxOnScreen = self.previewLayer.layerRectConverted(fromMetadataOutputRect: observedFace.boundingBox)
            let faceBoundingBoxPath = CGPath(rect: faceBoundingBoxOnScreen, transform: nil)
            let faceBoundingBoxShape = CAShapeLayer()
            faceBoundingBoxShape.path = faceBoundingBoxPath
            faceBoundingBoxShape.fillColor = UIColor.clear.cgColor
            faceBoundingBoxShape.strokeColor = UIColor.green.cgColor
            return faceBoundingBoxShape

        })
        facesBoundingBoxes.forEach({ faceBoundingBox in self.view.layer.addSublayer(faceBoundingBox) })
        self.drawings = facesBoundingBoxes
    }

    private func clearDrawings() {
        self.drawings.forEach({ drawing in drawing.removeFromSuperlayer() })
    }

    private func detectFace(in image: CVPixelBuffer) {
        let faceDetectionRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request: VNRequest, error: Error?) in
            DispatchQueue.main.async {
                // If a face is found then draw box around the card
                if let results = request.results as? [VNFaceObservation] {
                    if(results.count > 0){
                        self.detectRectangle(in: image)
                    }
                } else {
                    self.removeMask()
                }
            }
        })
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .leftMirrored, options: [:])
        try? imageRequestHandler.perform([faceDetectionRequest])
    }
    

    private func setCameraInput() {
        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .back).devices.first else {
                fatalError("No back camera device found.")
        }
        let cameraInput = try! AVCaptureDeviceInput(device: device)
        self.captureSession.addInput(cameraInput)
    }
    
    private func showCameraFeed() {
        self.previewLayer.videoGravity = .resizeAspectFill
        self.videoView.layer.addSublayer(self.previewLayer)
        self.previewLayer.frame = self.view.frame
    }
    
    private func setCameraOutput() {
        self.videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        self.captureSession.addOutput(self.videoDataOutput)
        
        guard let connection = self.videoDataOutput.connection(with: AVMediaType.video),
            connection.isVideoOrientationSupported else { return }
        
        connection.videoOrientation = .portrait
    }
    
    private func detectRectangle(in image: CVPixelBuffer) {
        
        let request = VNDetectRectanglesRequest(completionHandler: { (request: VNRequest, error: Error?) in
            DispatchQueue.main.async {
                
                // If a face is found in the card then draw the bounding box of the card
                guard let results = request.results as? [VNRectangleObservation] else { return }
                self.removeMask()
                
                guard let rect = results.first else{
                    return
                }
                
                self.drawBoundingBox(rect: rect)
                
                if self.isTapped{
                    self.isTapped = false
                    self.doPerspectiveCorrection(rect, from: image)
                }
            }
        })
        
        request.minimumAspectRatio = VNAspectRatio(1.3)
        request.maximumAspectRatio = VNAspectRatio(1.6)
        request.minimumSize = Float(0.5)
        request.maximumObservations = 1

        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        try? imageRequestHandler.perform([request])
    }
    
    func drawBoundingBox(rect : VNRectangleObservation) {
    
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.previewLayer.frame.height)
        let scale = CGAffineTransform.identity.scaledBy(x: self.previewLayer.frame.width, y: self.previewLayer.frame.height)

        let bounds = rect.boundingBox.applying(scale).applying(transform)
        createLayer(in: bounds)
    }

    private func createLayer(in rect: CGRect) {

        if(bImageCaptured){
            return
        }
        
        maskLayer = CAShapeLayer()
        maskLayer.frame = rect
        maskLayer.cornerRadius = 10
        maskLayer.opacity = 0.75
        maskLayer.borderColor = UIColor.red.cgColor
        maskLayer.borderWidth = 5.0
        
        previewLayer.insertSublayer(maskLayer, at: 1)

    }
    
    func removeMask() {
        DispatchQueue.main.async {
            self.maskLayer.removeFromSuperlayer()
        }
    }
}

extension CGPoint {
   func scaled(to size: CGSize) -> CGPoint {
       return CGPoint(x: self.x * size.width,
                      y: self.y * size.height)
   }
}

