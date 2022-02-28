//
//  ViewController.swift
//  ShareScreenTestApp
//
//  Created by Slav Sarafski on 21.02.22.
//

import UIKit
import ReplayKit
import Network

class ViewController: UIViewController {

    var broadcastController : RPBroadcastController?
    
    
    var port: NWEndpoint.Port?
    var listener: NWListener?
    
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var recpicker: RPSystemBroadcastPickerView!
    
    var isScoketStarted = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.port = NWEndpoint.Port(rawValue: 8080)!
        listener = try! NWListener(using: .tcp, on: self.port!)
        
        recpicker.backgroundColor = .white
        for v in recpicker.subviews {
            print(type(of: v))
            if let b = v as? UIButton {
                //b.setTitle("Record", for: .normal)
//                b.setImage(UIImage(named: "invo"), for: .normal)
//                b.centerXAnchor.constraint(equalTo: recpicker.centerXAnchor).isActive = true
//                b.centerYAnchor.constraint(equalTo: recpicker.centerYAnchor).isActive = true
//                b.widthAnchor.constraint(equalTo: recpicker.widthAnchor).isActive = true
//                b.heightAnchor.constraint(equalTo: recpicker.heightAnchor).isActive = true
            }
        }
    }

    @IBAction func startShare() {
//        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 100, height: 80))
//        picker.translatesAutoresizingMaskIntoConstraints = false
//        self.view.addSubview(picker)
//
//        print(picker.subviews.count)
//        for v in picker.subviews {
//            print(type(of: v))
//            if let b = v as? UIButton {
//                b.setTitle("Kur", for: .normal)
//                b.setImage(UIImage(systemName: "house"), for: .normal)
//            }
//        }
//
//        picker.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
//        picker.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
//        picker.widthAnchor.constraint(equalTo: self.view.widthAnchor).isActive = true
//        picker.heightAnchor.constraint(equalTo: self.view.heightAnchor).isActive = true
        
//        RPBroadcastActivityViewController.load(withPreferredExtension: "com.videoengager.sharescreentestapp.ShareScreenExtention") {
//        RPBroadcastActivityViewController.load {
//            activity, error in
////            print("Error \(error)")
//            if error == nil {
//                activity?.delegate = self
//                activity?.modalPresentationStyle = .fullScreen
//                self.present(activity!, animated: true, completion: nil)
//            }
//        }
        
        startSocketAction()
        let picker = RPSystemBroadcastPickerView()
        for v in recpicker.subviews {
            print(type(of: v))
            if let b = v as? UIButton {
                b.sendActions(for: .allEvents)
            }
        }
    }

    private var connectionsByID: [Int: ServerConnection] = [:]

    @IBAction func startSocketAction() {
        do {
            try startSocket()
        }
        catch {
            print(error)
        }
    }
    
    func startSocket() throws {
        print("Server starting...")
        if isScoketStarted { return }
        isScoketStarted = true
        listener?.stateUpdateHandler = self.stateDidChange(to:)
        listener?.newConnectionHandler = self.didAccept(nwConnection:)
        listener?.start(queue: .main)
    }

    func stateDidChange(to newState: NWListener.State) {
        switch newState {
        case .ready:
          print("Server ready.")
        case .failed(let error):
            print("Server failure, error: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        default:
            break
        }
    }

    private func didAccept(nwConnection: NWConnection) {
        let connection = ServerConnection(nwConnection: nwConnection)
        self.connectionsByID[connection.id] = connection
        connection.didStopCallback = { _ in
            self.connectionDidStop(connection)
        }
        connection.didReceiveCallback = { image in
            self.imageView.image = UIImage(ciImage: image)
        }
        connection.start()
        connection.send(data: "Welcome you are connection: \(connection.id)".data(using: .utf8)!)
        print("server did open connection \(connection.id)")
    }

    private func connectionDidStop(_ connection: ServerConnection) {
        self.connectionsByID.removeValue(forKey: connection.id)
        print("server did close connection \(connection.id)")
    }
    
    private func stop() {
        self.listener?.stateUpdateHandler = nil
        self.listener?.newConnectionHandler = nil
        self.listener?.cancel()
        for connection in self.connectionsByID.values {
            connection.didStopCallback = nil
            connection.stop()
        }
        self.connectionsByID.removeAll()
    }
}

extension ViewController: RPBroadcastActivityViewControllerDelegate, RPBroadcastControllerDelegate {
    func broadcastActivityViewController(_ broadcastActivityViewController: RPBroadcastActivityViewController,
                                         didFinishWith broadcastController: RPBroadcastController?,
                                         error: Error?) {
        
        DispatchQueue.main.async {
            print("Error2 : \(error)")
            self.broadcastController = broadcastController
            self.broadcastController?.delegate = self
            broadcastActivityViewController.dismiss(animated: true) {
                self.broadcastController?.startBroadcast(handler: { error in
                    print("started broadcast (error)")
                })
            }
        }
    }
    
    func broadcastController(_ broadcastController: RPBroadcastController, didFinishWithError error: Error?) {
            
    }

    func broadcastController(_ broadcastController: RPBroadcastController, didUpdateServiceInfo serviceInfo: [String : NSCoding & NSObjectProtocol]) {
        
    }
}

class ServerConnection {
    //The TCP maximum package size is 64K 65536
    let MTU = 65536

    private static var nextID: Int = 0
    let  connection: NWConnection
    let id: Int

    init(nwConnection: NWConnection) {
        connection = nwConnection
        id = ServerConnection.nextID
        ServerConnection.nextID += 1
    }

    var didStopCallback: ((Error?) -> Void)? = nil
    var didReceiveCallback: ((CIImage) -> Void)?

    func start() {
        print("connection \(id) will start")
        connection.stateUpdateHandler = self.stateDidChange(to:)
        setupReceive()
        connection.start(queue: .main)
    }

    private func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .waiting(let error):
            connectionDidFail(error: error)
        case .ready:
            print("connection \(id) ready")
        case .failed(let error):
            connectionDidFail(error: error)
        default:
            break
        }
    }

    var isStart = false
    var chunks: [Data] = []
    var count = 0
    private func setupReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: MTU) { (data, _, isComplete, error) in
            if let data = data, !data.isEmpty {
                let message = String(data: data, encoding: .utf8)
                print("connection \(self.id) did receive, data: \(data as NSData) string: \(message ?? "-")")
                //self.send(data: data)
                
                if let msg = String(data: data, encoding: .utf8) {
                    print("MESSAGE '\(msg)'")
                    if msg == "start",
                       self.isStart == false {
                        print("START CHUNK")
                        self.isStart = true
                        self.chunks = []
                    }
                    else if let cr = msg.range(of: "count:")
                    {
                        print("COUNT-")
                        let countMsg = msg[cr.upperBound...]
                        if let count = Int(countMsg) {
                            print("COUNT-\(count)")
                            self.count = count
                        }
                    }
                    else if msg == "end",
                       self.isStart == true {
                        self.isStart = false
                        print("END-\(self.chunks.count) - \(self.count)")
                        if self.chunks.count == self.count {
                            let data = self.chunks.reduce(Data(), +)
                            print("END-combine")
                            if let image = CIImage(data: data) {
                                print("END-Image")
                                self.didReceiveCallback?(image)
                            }
                        }
                    }
                }
                else {
                    self.chunks.append(data)
                }
                
//                if let image = CIImage(data: data) {
//                    print("imamge image")
//                    self.didReceiveCallback?(image)
//                }
            }
            if isComplete {
                self.connectionDidEnd()
            } else if let error = error {
                self.connectionDidFail(error: error)
            } else {
                self.setupReceive()
            }
        }
    }


    func send(data: Data) {
        self.connection.send(content: data, completion: .contentProcessed( { error in
            if let error = error {
                self.connectionDidFail(error: error)
                return
            }
            print("connection \(self.id) did send, data: \(data as NSData)")
        }))
    }

    func stop() {
        print("connection \(id) will stop")
    }



    private func connectionDidFail(error: Error) {
        print("connection \(id) did fail, error: \(error)")
        stop(error: error)
    }

    private func connectionDidEnd() {
        print("connection \(id) did end")
        stop(error: nil)
    }

    private func stop(error: Error?) {
        connection.stateUpdateHandler = nil
        connection.cancel()
        if let didStopCallback = didStopCallback {
            self.didStopCallback = nil
            didStopCallback(error)
        }
    }
}
