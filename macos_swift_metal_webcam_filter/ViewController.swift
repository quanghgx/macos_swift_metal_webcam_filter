//
//  ViewController.swift
//  macos_swift_metal_webcam_filter
//
//  Created by Hoàng Xuân Quang on 7/26/17.
//  Copyright © 2017 Hoang Xuan Quang. All rights reserved.
//

import Cocoa
import AVFoundation
import Metal
import MetalKit

class ViewController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    var device:MTLDevice!
    var library: MTLLibrary!
    var commandQueue: MTLCommandQueue!
    var renderPipelineState: MTLRenderPipelineState!
    let semaphore = DispatchSemaphore(value: 1)
    open var texture: MTLTexture?

    var cache : CVMetalTextureCache?

    var webcam:AVCaptureDevice? = nil
    let videoOutput:AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
    let videoSession:AVCaptureSession = AVCaptureSession()
    let videoQueue: DispatchQueue = DispatchQueue(label: "video_queue")

    var metalView: MTKView {
        return view as! MTKView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        /* Metal initialization*/
        device = MTLCreateSystemDefaultDevice()
        library = device.newDefaultLibrary()
        commandQueue = device.makeCommandQueue()

        init_render_pipeline_state()

        metalView.device = device
        metalView.clearColor = MTLClearColorMake(0.3, 0.5,0.7, 1.0)
        metalView.delegate = self

        initCache()

        /* Camera setup*/

        // Set the device
        let devices = AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo)!
        webcam = devices[0] as? AVCaptureDevice

        // Configuration
        videoSession.beginConfiguration()
        do {
            let webcamInput: AVCaptureDeviceInput = try AVCaptureDeviceInput(device: webcam)
            if videoSession.canAddInput(webcamInput){
                videoSession.addInput(webcamInput)
                print("---> Adding webcam input")
            }
        } catch let err as NSError {
            print("---> Error using the webcam: \(err)")
        }

        // Webcam session
        videoSession.sessionPreset = AVCaptureSessionPresetHigh

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as AnyHashable : (kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as AnyHashable: true
        ]
        videoSession.addOutput(videoOutput)

        // Register the sample buffer callback
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        videoSession.commitConfiguration()
        videoSession.startRunning()
    }

    private func initCache() {
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device!, nil, &cache) == kCVReturnSuccess else {
            fatalError("Could not create texture cache")
        }
    }

    private func init_render_pipeline_state(){
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.sampleCount = 1
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "mapTexture")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "displayTexture")

        do {
            try renderPipelineState = device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("create render pipeline error \(error)")
        }
    }

    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            fatalError("Could not retreive pixelbuffer")
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var imageTexture: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache!, pixelBuffer, nil, MTLPixelFormat.bgra8Unorm, width, height, 0, &imageTexture)
        texture = CVMetalTextureGetTexture(imageTexture!)
    }
}

extension ViewController: MTKViewDelegate{

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("MTKView drawable size will change to \(size)")
    }

    public func draw(in view: MTKView) {

        _ = semaphore.wait(timeout: DispatchTime.distantFuture)
        autoreleasepool {
            guard let texture = texture else {
                _ = semaphore.signal()
                return
            }

            let commandBuffer = commandQueue.makeCommandBuffer()
            let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: metalView.currentRenderPassDescriptor!)
            commandEncoder.setRenderPipelineState(renderPipelineState)
            commandEncoder.setFragmentTexture(texture, at: 0)
            commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            commandEncoder.endEncoding()

            commandBuffer.addScheduledHandler { [weak self] (buffer) in
                guard let unwrappedSelf = self else { return }
                unwrappedSelf.semaphore.signal()
            }
            
            commandBuffer.present(metalView.currentDrawable!)
            commandBuffer.commit()            
        }
    }
}
