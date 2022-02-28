//
//  SampleHandler.swift
//  ShareScreenExtention
//
//  Created by Slav Sarafski on 21.02.22.
//

import ReplayKit

class SampleHandler: RPBroadcastSampleHandler {

    private enum Constants {
        static let appGroupIdentifier = "group.com.videoengager.sharescreentestapp"
    }

    private var socketFilePath: String {
        let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier)
         
        return sharedContainer?.appendingPathComponent("rtc_SSFD").path ?? ""
    }
    
    private var clientConnection: SocketConnection?
    private var uploader: SampleUploader?
    
    private var frameCount: Int = 0
    
    override init() {
      super.init()
//        if let connection = SocketConnection(filePath: socketFilePath) {
//          clientConnection = connection
//          setupConnection()
//
//          uploader = SampleUploader(connection: connection)
//        }
    }
    
    var client: Client?
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
//        frameCount = 0
//
//        DarwinNotificationCenter.shared.postNotification(.broadcastStarted)
//        openConnection()
        
        client = Client(host: "localhost", port: 8080)
        client?.start()
    }
    
    override func broadcastPaused() {
        // User has requested to pause the broadcast. Samples will stop being delivered.
    }
    
    override func broadcastResumed() {
        // User has requested to resume the broadcast. Samples delivery will resume.
    }
    
    override func broadcastFinished() {
        // User has requested to finish the broadcast.
    }
    
    var chunkId = 0
    var chunkCount = 0
    var chunkIndex = 0
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case RPSampleBufferType.video:
            
            frameCount += 1
            if frameCount % 3 == 0,
               let data = sampleBuffer.imageData() {
                print(data.count)
                self.createChunks(forData: data) { chunks in
//                    client?.connection.send(data: "start".data(using: .utf8)!)
//                    client?.connection.send(data: "count".data(using: .utf8)!)
                    chunkCount = chunks.count
                    chunkId += 1
                    if chunkId > 99 { chunkId = 1}
                    chunkIndex = 0
                    for chunk in chunks {
                        chunkIndex += 1
                        let info = String(format: "%02d%02d%02d", chunkId, chunkIndex, chunkCount).data(using: .utf8)! // 010106 -> 010206 -> 010306
                        client?.connection.send(data: info)
                        //client?.connection.send(data: chunk)
                    }
//                    client?.connection.send(data: "end".data(using: .utf8)!)
                }
            }
            
//            frameCount += 1
//            if frameCount % 3 == 0 {
//                uploader?.send(sample: sampleBuffer)
//            }
        default:
            break
        }
    }
    
    func createChunks(forData imageData: Data, completion: ([Data])->Void) {

        var chunks: [Data] = []
        
        imageData.withUnsafeBytes { (u8Ptr: UnsafePointer<UInt8>) in
            let mutRawPointer = UnsafeMutableRawPointer(mutating: u8Ptr)
            let uploadChunkSize = 65536
            let totalSize = imageData.count
            var offset = 0

            while offset < totalSize {

                let chunkSize = offset + uploadChunkSize > totalSize ? totalSize - offset : uploadChunkSize
                let chunk = Data(bytesNoCopy: mutRawPointer+offset, count: chunkSize, deallocator: Data.Deallocator.none)
                offset += chunkSize
                chunks.append(chunk)
            }
            completion(chunks)
        }
    }
}

extension CMSampleBuffer {
    func data() -> Data? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }

        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        guard let src_buff = CVPixelBufferGetBaseAddress(imageBuffer) else { return nil }
        let data = Data(bytes: src_buff, count: bytesPerRow * height)

        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return data
    }
    
    private static var imageContext = CIContext(options: nil)
    func imageData() -> Data? {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }
        
        let image = CIImage(cvPixelBuffer: imageBuffer)
        
        guard let colorSpace = image.colorSpace else {
            return nil
        }
      
        let options: [CIImageRepresentationOption: Float] = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0]

        return CMSampleBuffer.imageContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: options)
    }
}

private extension SampleHandler {
  
    func setupConnection() {
        clientConnection?.didClose = { [weak self] error in
            print("client connection did close \(String(describing: error))")
          
            if let error = error {
                self?.finishBroadcastWithError(error)
            } else {
                // the displayed failure message is more user friendly when using NSError instead of Error
                let JMScreenSharingStopped = 10001
                let customError = NSError(domain: RPRecordingErrorDomain, code: JMScreenSharingStopped, userInfo: [NSLocalizedDescriptionKey: "Screen sharing stopped"])
                self?.finishBroadcastWithError(customError)
            }
        }
    }
    
    func openConnection() {
        let queue = DispatchQueue(label: "broadcast.connectTimer")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard self?.clientConnection?.open() == true else {
                return
            }
            
            timer.cancel()
        }
        
        timer.resume()
    }
}

