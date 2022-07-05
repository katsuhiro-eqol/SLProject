//
//  ViewController.swift
//  SignLang
//
//  Created by Apple on 2022/06/27.
//

import UIKit
import AVFoundation
import Vision

class CameraViewController: UIViewController {

    var previewLayer = AVCaptureVideoPreviewLayer()
    private let drawOverlay = CAShapeLayer()
    private var imageSize: CGSize!
    
    private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInteractive)
    private var cameraFeedSession: AVCaptureSession?
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    private var bodyPoseRequest = VNDetectHumanBodyPoseRequest() //add
    
    private var nosePoint: CGPoint? //zero point
    private var leftShoulderPoint: CGPoint? //shoulder widthで規格化
    private var rightShoulderPoint: CGPoint?
    
    var stillData = [[Int]]()
    var videoData = [[Int]]()

    
    override func viewDidLoad() {
        super.viewDidLoad()
        imageSize = self.view.frame.size
        previewLayer.frame = view.layer.bounds
        drawOverlay.frame = view.layer.bounds
        drawOverlay.backgroundColor = #colorLiteral(red: 0.9999018312, green: 1, blue: 0.9998798966, alpha: 0.5).cgColor
        previewLayer.addSublayer(drawOverlay)
        view.layer.addSublayer(previewLayer)
        drawPerson()
        
        handPoseRequest.maximumHandCount = 2
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            if cameraFeedSession == nil {
                self.previewLayer.videoGravity = .resizeAspectFill
                try setupAVSession()
                self.previewLayer.session = cameraFeedSession
            }
            cameraFeedSession?.startRunning()
        } catch {
            AppError.display(error, inViewController: self)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        cameraFeedSession?.stopRunning()
        super.viewWillDisappear(animated)
    }
    
    func setupAVSession() throws {
        // Select a front facing camera, make an input.
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw AppError.captureSessionSetup(reason: "Could not find a front facing camera.")
        }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            throw AppError.captureSessionSetup(reason: "Could not create video device input.")
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.high
        
        // Add a video input.
        guard session.canAddInput(deviceInput) else {
            throw AppError.captureSessionSetup(reason: "Could not add video device input to the session")
        }
        session.addInput(deviceInput)
        
        let dataOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
            // Add a video data output.
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            throw AppError.captureSessionSetup(reason: "Could not add video data output to the session")
        }
        session.commitConfiguration()
        cameraFeedSession = session
}
   
    func drawPerson(){
        let image:UIImage = UIImage(named:"person")!
        let imageView = UIImageView(image: image)
        let screenWidth:CGFloat = self.view.frame.size.width
        let imgWidth:CGFloat = image.size.width
        let imgHeight:CGFloat = image.size.height
        let scale:CGFloat = screenWidth / imgWidth * 0.4
        let size:CGSize =
                    CGSize(width:imgWidth*scale, height:imgHeight*scale)
        imageView.frame.size = size
        imageView.center = CGPoint(x: self.view.center.x, y: self.view.center.y - screenWidth * 0.2)
        self.view.addSubview(imageView)
    }

    //noseをzero点とし、肩幅で各座標を規格化する関数。portrait/CGPointではxが縦方向。yが横方向。100枚して整数座標に変換。横方向500ピクセル、縦方向400ピクセルに割り付ける。noseより上に100ピクセル、下に300ピクセル、右に250ピクセル、左に250ピクセル。左上のピクセルを0とし横に1,2,3として、最上列の一番右が499。２段目の一番左が500で一番右が999。一番右下が、199999とする。
    
    private func pixelNumber(point: CGPoint?) -> Int {
        var pixelNumber: Int
        guard let left = leftShoulderPoint, let right = rightShoulderPoint, let nose = nosePoint else {return -1}
        let shoulderWidth = abs(left.y - right.y)
        guard let oriPoint = point else {return -2}
        
        if shoulderWidth == 0 {
            return -3
            } else {
                let ori = CGPoint(x: (oriPoint.x - nose.x)/shoulderWidth, y: (oriPoint.y - nose.y)/shoulderWidth)
                let xPixel = Int(ori.x * 100.0)
                let yPixel = Int(ori.y * 100.0)
                if xPixel < -100 || xPixel > 300 || yPixel < -250 || yPixel > 250 {
                    return -4
                } else {
                    pixelNumber = (xPixel + 100) * 500 + (yPixel + 250)
                }
            }
            return pixelNumber
        }
    
    private func nomarizeLocation(pre: CGPoint?) -> [Int]{
        var normalizedPoint: [Int]
        guard let left = leftShoulderPoint, let right = rightShoulderPoint, let nose = nosePoint else {return [-1, -1]}
        let shoulderWidth = left.y - right.y
        if shoulderWidth == 0 {
            return [-3, -3]
        } else {
            if pre == nil {
                return [-2, -2]
            } else {
                let point = CGPoint(x: (pre!.x - nose.x)/shoulderWidth, y: (pre!.y - nose.y)/shoulderWidth)
                normalizedPoint = [Int(point.x * 100.0), Int(point.y * 100.0)]
            }
        }
        return normalizedPoint
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        stillData = [[Int]]()

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([bodyPoseRequest, handPoseRequest])
            
            guard let observationBody = bodyPoseRequest.results?.first else {return}
            
            guard let nose =
                    try? observationBody.recognizedPoint(.nose) else {return}
            nosePoint = CGPoint(x: (nose.location.x) * imageSize.height, y: ( nose.location.y) * imageSize.width)
            guard let rightShoulder =
                    try? observationBody.recognizedPoint(.rightShoulder) else {return}
            rightShoulderPoint =  CGPoint(x: (rightShoulder.location.x) * imageSize.height, y: ( rightShoulder.location.y) * imageSize.width)
            guard let leftShoulder =
                    try? observationBody.recognizedPoint(.leftShoulder) else {return}
            leftShoulderPoint = CGPoint(x: (leftShoulder.location.x) * imageSize.height, y: ( leftShoulder.location.y) * imageSize.width)
            guard let rightEye =
                    try? observationBody.recognizedPoint(.rightEye) else {return}
            let rightEyePoint = CGPoint(x: (rightEye.location.x) * imageSize.height, y: ( rightEye.location.y) * imageSize.width)
            guard let leftEye =
                    try? observationBody.recognizedPoint(.leftEye) else {return}
            let leftEyePoint = CGPoint(x: (leftEye.location.x) * imageSize.height, y: ( leftEye.location.y) * imageSize.width)
            guard let rightElbow =
                    try? observationBody.recognizedPoint(.rightElbow) else {return}
            let rightElbowPoint = CGPoint(x: (rightElbow.location.x) * imageSize.height, y: ( rightElbow.location.y) * imageSize.width)
            guard let leftElbow =
                    try? observationBody.recognizedPoint(.leftElbow) else {return}
            let leftElbowPoint = CGPoint(x: (leftElbow.location.x) * imageSize.height, y: ( leftElbow.location.y) * imageSize.width)
            guard let rightWrist =
                    try? observationBody.recognizedPoint(.rightWrist) else {return}
            let rightWristPoint = CGPoint(x: (rightWrist.location.x) * imageSize.height, y: ( rightWrist.location.y) * imageSize.width)
            guard let leftWrist =
                    try? observationBody.recognizedPoint(.leftWrist) else {return}
            let leftWristPoint = CGPoint(x: (leftWrist.location.x) * imageSize.height, y: ( leftWrist.location.y) * imageSize.width)
            
            stillData.append(nomarizeLocation(pre: rightEyePoint))
            stillData.append(nomarizeLocation(pre: rightShoulderPoint))
            stillData.append(nomarizeLocation(pre: rightElbowPoint))
            stillData.append(nomarizeLocation(pre: rightWristPoint))
            
            stillData.append(nomarizeLocation(pre: leftEyePoint))
            stillData.append(nomarizeLocation(pre: leftShoulderPoint))
            stillData.append(nomarizeLocation(pre: leftElbowPoint))
            stillData.append(nomarizeLocation(pre: leftWristPoint))
            
            if handPoseRequest.results?.count == 1 || handPoseRequest.results?.count == 0{
                return
            } else {
                for i in 0...1 {
                    guard let observationHand0 = handPoseRequest.results?[i] else {return}
                    guard let indexFinger =
                            try? observationHand0.recognizedPoints(.indexFinger)[.indexTip] else {return}
                    let indexTip = CGPoint(x: (indexFinger.location.x) * imageSize.height, y: ( indexFinger.location.y) * imageSize.width)
                    stillData.append(nomarizeLocation(pre: indexTip))

                    guard let middleFinger =
                            try? observationHand0.recognizedPoints(.middleFinger)[.middleTip] else {return}
                    let middleTip = CGPoint(x: (middleFinger.location.x) * imageSize.height, y: ( middleFinger.location.y) * imageSize.width)
                    stillData.append(nomarizeLocation(pre: middleTip))
                    
                    guard let ringFinger =
                            try? observationHand0.recognizedPoints(.ringFinger)[.ringTip] else {return}
                    let ringTip = CGPoint(x: (ringFinger.location.x) * imageSize.height, y: ( ringFinger.location.y) * imageSize.width)
                    stillData.append(nomarizeLocation(pre: ringTip))
                    
                    guard let littleFinger =
                            try? observationHand0.recognizedPoints(.littleFinger)[.littleTip] else {return}
                    let littleTip = CGPoint(x: (littleFinger.location.x) * imageSize.height, y: ( littleFinger.location.y) * imageSize.width)
                    stillData.append(nomarizeLocation(pre: littleTip))
                    
                    guard let thumb =
                            try? observationHand0.recognizedPoints(.thumb)[.thumbTip] else {return}
                    let thumbTip = CGPoint(x: (thumb.location.x) * imageSize.height, y: ( thumb.location.y) * imageSize.width)
                    stillData.append(nomarizeLocation(pre: thumbTip))
                    
                     guard let wrist =
                             try? observationHand0.recognizedPoint(.wrist) else {return}
                     let wristPoint = CGPoint(x: (wrist.location.x) * imageSize.height, y: ( wrist.location.y) * imageSize.width)
                     stillData.append(nomarizeLocation(pre: wristPoint))
                }
            }
            
            print(stillData)
            
            /*
            defer {
                DispatchQueue.main.sync {
                
                }
            }
            */
        } catch {
            cameraFeedSession?.stopRunning()
            let error = AppError.visionError(error: error)
            DispatchQueue.main.async {
                error.displayInViewController(self)
            }
        }

    }
}
