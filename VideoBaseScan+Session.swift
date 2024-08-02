//
//  VideoBaseScan+Session.swift
//  Vsite
//
//  Created by blitzz on 24/02/22.
//

import UIKit
import ARKit
import RealityKit
import Zip

extension VideoBaseScan: AVCaptureVideoDataOutputSampleBufferDelegate, ARSessionDelegate {
    
    
//    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
//        print("###### session did remove anchors delegate called ")
//
//        ShowToast.show(toatMessage: "Session Did Remove Ar anchors")
//    }
//
//    func sessionWasInterrupted(_ session: ARSession) {
//        print("###### sessionWasInterrupted ")
//
//        ShowToast.show(toatMessage: "SessionWasInterrupted")
//    }
//
//    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
//        print("###### sessionShouldAttemptRelocalization ")
//
//        ShowToast.show(toatMessage: "SessionShouldAttemptRelocalization")
//        return true
//    }
//
//    func sessionInterruptionEnded(_ session: ARSession) {
//        print("###### sessionInterruptionEnded ")
//        ShowToast.show(toatMessage: "sessionInterruptionEnded")
//    }
    
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        let msDate: Double = bootTime + frame.timestamp
        
        if prevFrTs >= 0 {
            let value = Double(1.0 / Double(framePerSecond)) / Double(1.5)
            if Double(reduseFpsInNTimes) * (msDate - prevFrTs) < value {
                reduseFpsInNTimes += 1
            }
        }
        prevFrTs = msDate
        
        if ireduceFps == 0 {
            let camMat = frame.camera.intrinsics
            processImage(frame.capturedImage, timestamp: msDate, cameraMatrix: camMat, arFrame: frame)
        }
        if ireduceFps == (reduseFpsInNTimes - 1) {
            ireduceFps = 0
        } else {
            ireduceFps += 1
        }
        
        //this same method get called during the video scan so at that time we need a arpose and txt file but during automatic floor plan only video need to upload so this arpose.txt not needed so that is why condition added
        if selectedMeasurementOption != .objectToPLY {
            let trans = frame.camera.transform
            let quat = simd_quaternion(trans)
            let logArPose = "\(msDate),\(trans.columns.3[0]),\(trans.columns.3[1]),\(trans.columns.3[2]),\(quat.vector[3]),\(quat.vector[0]),\(quat.vector[1]),\(quat.vector[2])\r\n"
            if let url = self.logArPose, isRecording {
                writeToFile(fileUrl: url, strWrite: logArPose)
            }
            
            
            if let ambientIntensity = frame.lightEstimate?.ambientIntensity, (processState != ProcessState.finished && processState != ProcessState.zippingAndUploading) {
                if ambientIntensity < 300 {
                    self.toggleTorch(on: true, darkLvel: Float(ambientIntensity / 300.0) )
                } else if ambientIntensity >= 1300 {
                    self.toggleTorch(on: false, darkLvel: 1.0)
                }
            }
        }
    }
    
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        //We are not showing insufficient feature message during automatic floor plan
        if self.isRecording && selectedMeasurementOption != .objectToPLY {
            switch camera.trackingState {
            case .limited(let reason):
                switch reason {
                case .insufficientFeatures: self.setDataCallback(operations: .cameraFeatures(state: CameraFeatures.insufficientFeatures))// then update UI
                default: break
                }
            case .normal: self.setDataCallback(operations: .cameraFeatures(state: CameraFeatures.normal))
            default: break
            }
        }
        
        print("###### camera did change tracking state")
    }

    func setDelayCallback(frame: ARFrame) {
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.delayTimer == nil, self.isRecording {
                self.delayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                    guard self?.delayTimer != nil else { return }
                    // Perfect view

                    if frame.camera.eulerAngles.x < TiltDevicePoints.BackABitStartPoint.rawValue &&
                        frame.camera.eulerAngles.x > TiltDevicePoints.BackABitEndPointAndForwardABitStartPoint.rawValue {
                        self?.setDataCallback(operations: .tilt(tiltAt: .none))
                    } else if frame.camera.eulerAngles.x > TiltDevicePoints.CeilingStartPoint.rawValue {
                        // Ceiling view
                        self?.setDataCallback(operations: .tilt(tiltAt: .ceiling))
                    } else if frame.camera.eulerAngles.x < TiltDevicePoints.CeilingStartPoint.rawValue &&
                                frame.camera.eulerAngles.x > TiltDevicePoints.BackABitStartPoint.rawValue {
                        // Forward A bit view
                        self?.setDataCallback(operations: .tilt(tiltAt: .forward))
                    } else if frame.camera.eulerAngles.x < TiltDevicePoints.BackABitEndPointAndForwardABitStartPoint.rawValue {
                        // Back A bit view
                        self?.setDataCallback(operations: .tilt(tiltAt: .backward))
                    }
                    
                    
                    if let ambientIntensity = frame.lightEstimate?.ambientIntensity, ambientIntensity < 180 { // more less .e.g 180 more darker it is.
                        //                        NSLog("======> too dark showing.....")
                        self?.setDataCallback(operations: .roomLight(isTooDark: true))
                    } else {
                        //                        NSLog("======> too dark not showing.....")
                        self?.setDataCallback(operations: .roomLight(isTooDark: false))
                    }
                    
                    self?.delayTimer?.invalidate()
                    self?.delayTimer = nil
                }
            }
        }
    }
    
    func processImage(_ pixelBuffer: CVPixelBuffer?, timestamp msDate: Double, cameraMatrix camMat: matrix_float3x3?, arFrame: ARFrame) {
        
        if isStarted {
            updateLocation(location: locationData)
            updateHeading(heading: headingData)
            
            let documentsDirectory = FileManager.documentsDirectory()
            let filePath = "\(documentsDirectory)/\(theDate)/Frames.m4v"
            
            let outputURL = URL(fileURLWithPath: filePath)
            do {
                assetWriter = try AVAssetWriter(url: outputURL, fileType: .m4v)
            } catch {
                SentryConfig.sharedInstance().logExecption(error: error, function: #function,fileName: #fileID)
                restartScanningWithError(code: .e1001)
            }
            
            if let pixelBuffer = pixelBuffer {
                assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: getVideoWriterSettings(bitrate: getBitrate(bitrate: Float(CVPixelBufferGetBytesPerRow(pixelBuffer)), quality: .high), width: Int(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)), height: Int(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))))
            }
            
            if let assetWriterInput = assetWriterInput, assetWriter?.canAdd(assetWriterInput) ?? false {
                assetWriter?.add(assetWriterInput)
                assetWriterInputPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)
            } else {
                restartScanningWithError(code: .e1002)
            }
            
            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: .zero)
            
            isStarted = false
            isRecording = true
            
        }
        if isRecording {
            if assetWriterInput?.isReadyForMoreMediaData ?? false {
                if let pixelBuffer = pixelBuffer {
                    assetWriterInputPixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frameNum), timescale: framePerSecond))
                    var logFrameStamp = ""
                    if let camMat = camMat {
                        logFrameStamp = "\(msDate),\(frameNum),\(camMat.columns.0[0]),\(camMat.columns.1[1]),\(camMat.columns.2[0]),\(camMat.columns.2[1])\r\n"
                    } else {
                        logFrameStamp = "\(msDate),\(frameNum)\r\n"
                    }
                    if let url = self.logFrames {
                        writeToFile(fileUrl: url, strWrite: logFrameStamp)
                    }
                    frameNum += 1
                } else {
                    print("pixelBuffer is nil")
                }
            } else {
                print("assetWriterInput.isReadyForMoreMediaData = NO!")
            }
            
            // no need to show guide line during automatic floor plan hence added condition
            if selectedMeasurementOption != .objectToPLY {
                setDelayCallback(frame: arFrame)
            }
        }
    }
    
    func getVideoWriterSettings(bitrate: Int, width: Int, height: Int) -> [String : AnyObject] {
        let videoWriterCompressionSettings = [
            AVVideoAverageBitRateKey : bitrate
        ]
        let videoWriterSettings: [String : AnyObject] = [
            AVVideoCodecKey : AVVideoCodecType.h264 as AnyObject,
            AVVideoCompressionPropertiesKey : videoWriterCompressionSettings as AnyObject,
            AVVideoWidthKey : width as AnyObject,
            AVVideoHeightKey : height as AnyObject
        ]
        return videoWriterSettings
    }
    
    func getBitrate(bitrate: Float, quality: VideoQuality) -> Int {
        if quality == .low {
            return Int(bitrate * 0.1)
        } else if quality == .medium {
            return Int(bitrate * 0.2)
        } else if quality == .high {
            return Int(bitrate * 0.3)
        } else {
            return Int(bitrate * 0.2)
        }
    }
    
    @objc func TimerFired(_ timer: Timer?) {
        runTimeTimerCount += 1
        let timeStr = String(format: "%.2d:%.2d", runTimeTimerCount / 60, runTimeTimerCount % 60)
        DispatchQueue.main.async(execute: { [weak self] in
            self?.setDataCallback(operations: .timer(elapsedTime: timeStr))
        })
    }
    
    func pauseElapsedTimer() {
        if processState == .scanning, let _runTimeTimer = runTimeTimer, _runTimeTimer.isValid {
            isRecording = false
            runTimeTimer?.invalidate()
            runTimeTimer = nil
            
            arSCNView.scene.rootNode.cleanup()
            arSCNView.session.pause()
            
            self.arSCNView.delegate = nil
            
            print("Recording session inturrupted")
        } else {
            print("Recording is not started yet or timer object is nil")
        }
    }
    
    func resumeElapsedTimer() {
        if processState == .scanning, runTimeTimer == nil {
            if selectedMeasurementOption == .objectToPLY {
                
                isRecording = true
                self.arSCNView.delegate = self
                showArCameraFeedInSceneview()
                
                runTimeTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(TimerFired(_:)), userInfo: nil, repeats: true)
            } else {
                if runTimeTimerCount < 30 {
                    AlertView.show(title: "Scan aborted", message: "The scan was aborted because the app was backgrounded. Please scan the entire/remaining floor area again.", preferredStyle: .alert, buttons: ["Dismiss"], sourceRect: nil) { [self] str in
                        
                        TwilioVideoCallClass.sharedInstance().dataTrackForAbortRestartScan(reason: "1")
                        
                        self.restartVideoScan()//(message:"The camera is turned off during the scan upload. once it is completed, click \"Start Scanning\" to rescan the entire/remaining floor area again.")

                       // ShowToast.show(toatMessage: Messages().kScanAbortedDesc,isDelayNeeded: true)
                        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.3) {
                            TwilioVideoCallClass.sharedInstance().dataTrackForAbortRestartScanButtonACK(buttonClick: "2")
                        }
                        
                    }
                } else {
                    AlertView.show(title: "Scan aborted", message: "The scan was aborted because the app was backgrounded. Do you want to upload the scanned area?", preferredStyle: .alert, buttons: ["Upload and start scan", "Discard scan"], sourceRect: nil) { str in
                        if str == "Upload and start scan" {
                            
                            self.tuplePreviousScanAvailable = (true, false) // add this value to true because when uploading done and button will be shown as a scananother floor so we need to show the start scan button that is why this value set to true (func createFloorscanForPLYProcessing(fileName: String)) Check the condition in this function after video uploaded successfully.
                            
                            if #available(iOS 13.4, *) { // for lidar device
                                if self.selectedMeasurementOption == .objectToPLY, self.btnStartStopScanningLidar.title(for: .normal) == Messages().kFinishScanning {
                                    self.finishLidarScan()
                                } else {
                                   // if self.isRecording == true {
                                    self.stopRecording(message: "The camera is turned off during the scan upload. once it is completed, click \"Start Scanning\" to rescan the entire/remaining floor area again.")
                                  //  }
                                }
                            } else { // for normal device
                                // Fallback on earlier versions
                                self.stopRecording()
                            }
                            
                        } else if str == "Discard scan" {
                          
                            TwilioVideoCallClass.sharedInstance().dataTrackForAbortRestartScan(reason: "1")
                            
                            self.restartVideoScan()

                           // ShowToast.show(toatMessage: Messages().kScanAbortedDesc,isDelayNeeded: true)
                            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.3) {
                                TwilioVideoCallClass.sharedInstance().dataTrackForAbortRestartScanButtonACK(buttonClick: "2")
                            }
                            
                        }
                    }
                }

            }
            print("Recording session restarted")
        } else {
            print("Recording was not running or timer object is not nil")
        }
    }
    
    func writeScannedAreaIntoFile() {
        assetWriterInput?.markAsFinished()
        assetWriter?.finishWriting(completionHandler: {
            self.assetWriterInput = nil
            self.assetWriter = nil
            self.assetWriterInputPixelBufferAdaptor = nil
        })
    }
    
    func toggleTorch(on: Bool, darkLvel:Float) {
        guard
            let device = AVCaptureDevice.default(for: AVMediaType.video),
            device.hasTorch
        else { return }
        
        do {
            try device.lockForConfiguration()
            if (on){
                try device.setTorchModeOn(level: darkLvel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be used")
        }
    }
}


//        if (previousPosition != nil && self.lastOrientation == .landscapeRight && self.isRecording) {
////            //Move too fast
//            guard let distance = previousPosition?.distanceFrom(position: frame.camera.transform.getPosition()) else { return }
//
//            if distance >= 0.01 {
//                self.setDataCallback(operations: .movingTooFast(isFast: true))
//            } else if distance < 0.005 {
//                self.setDataCallback(operations: .movingTooFast(isFast: false))
//            }
//        }
//        previousPosition = frame.camera.transform.getPosition()
        
//        guard let query = self.arView?.makeRaycastQuery(from: self.arView?.center ?? CGPoint.zero,
//                                                  allowing: .estimatedPlane,
//                                                  alignment: .any)
//        else { return }
//
//        guard let raycastResult = self.arView?.session.raycast(query).first
//        else { return }
//
//        // Creates a text ModelEntity
//        func tooCloseModel() -> ModelEntity {
//                let lineHeight: CGFloat = 0.05
//                let font = MeshResource.Font.systemFont(ofSize: lineHeight)
//                let textMesh = MeshResource.generateText("Too Close", extrusionDepth: Float(lineHeight * 0.1), font: font)
//                let textMaterial = SimpleMaterial(color: AppColor.theme.yellow_color, isMetallic: false)
//                let model = ModelEntity(mesh: textMesh, materials: [textMaterial])
//                // Center the text
//                model.position.x -= model.visualBounds(relativeTo: nil).extents.x / 2
//                return model
//        }
//
//        if let currentPositionOfCamera = self.arView?.cameraTransform.translation, currentPositionOfCamera != .zero {
//
//            let distanceFromCamera = distance(raycastResult.worldTransform.getPosition(), currentPositionOfCamera)
//            // distance is defined in simd as the distance between 2 points
//
//                print("Distance from raycast:",distanceFromCamera)
//                if (distanceFromCamera < 0.5) {
//                    print("Too Close")
//
//                    let raycastDistance = normalize(raycastResult.worldTransform.getPosition() - (self.arView?.cameraTransform.translation)!)
//                    // This pulls the text back toward the camera from the plane
//                    let textPositionInWorldCoordinates = raycastResult.worldTransform.getPosition() //- (raycastDistance * 0.1)
//
//                    let textEntity = tooCloseModel()
//                    // This scales the text so it is of a consistent size
//                    textEntity.scale = .one * raycastDistance
//
//                    var textPositionWithCameraOrientation = self.arView?.cameraTransform
//                    textPositionWithCameraOrientation?.translation = textPositionInWorldCoordinates
//                    // self.textAnchor is defined somewhere in the class as an optional
//                    if let matrix = textPositionWithCameraOrientation?.matrix {
//                        self.textAnchor = AnchorEntity(world: matrix)
//                        textAnchor?.addChild(textEntity)
//                        self.arView?.scene.addAnchor(textAnchor!)
//                    }
//                } else {
//                    guard let textAnchor = self.textAnchor else { return }
//                    self.arView?.scene.removeAnchor(textAnchor)
//                }
//        }
