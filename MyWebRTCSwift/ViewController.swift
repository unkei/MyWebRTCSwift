//
//  ViewController.swift
//  MyWebRTCSwift
//
//  Created by Keiichi Unno on 6/22/15.
//  Copyright (c) 2015 Keiichi Unno. All rights reserved.
//

import AVFoundation
import UIKit
import Socket_IO_Client_Swift

let TAG = "ViewController"
let VIDEO_TRACK_ID = TAG + "VIDEO"
let AUDIO_TRACK_ID = TAG + "AUDIO"
let LOCAL_MEDIA_STREAM_ID = TAG + "STREAM"

class ViewController: UIViewController, RTCSessionDescriptionDelegate, RTCPeerConnectionDelegate {

    var mediaStream: RTCMediaStream!
    var localVideoTrack: RTCVideoTrack!
    var localAudioTrack: RTCAudioTrack!
    var remoteVideoTrack: RTCVideoTrack!
    var remoteAudioTrack: RTCAudioTrack!
    var renderer: RTCEAGLVideoView!
    var renderer_sub: RTCEAGLVideoView!

    func Log(value:String) {
        println(TAG + " " + value)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        initWebRTC();
        sigConnect("unwebrtc.herokuapp.com");
//        sigConnect("10.54.36.19:8000");

        var device: AVCaptureDevice! = nil
        for captureDevice in AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) {
            if (captureDevice.position == AVCaptureDevicePosition.Front) {
                device = captureDevice as! AVCaptureDevice
            }
        }
        if (device != nil) {
            var capturer = RTCVideoCapturer(deviceName: device.localizedName)

            var videoConstraints = RTCMediaConstraints()
            var audioConstraints = RTCMediaConstraints()
            var videoSource = peerConnectionFactory.videoSourceWithCapturer(capturer, constraints: videoConstraints)
            localVideoTrack = peerConnectionFactory.videoTrackWithID(VIDEO_TRACK_ID, source: videoSource)
//            AudioSource audioSource = peerConnectionFactory.createAudioSource(audioConstraints)
            localAudioTrack = peerConnectionFactory.audioTrackWithID(AUDIO_TRACK_ID)

            renderer = RTCEAGLVideoView(frame: self.view.frame)
            renderer_sub = RTCEAGLVideoView(frame: CGRectMake(20, 50, 90, 120))
            self.view.addSubview(renderer)
            self.view.addSubview(renderer_sub)

            mediaStream = peerConnectionFactory.mediaStreamWithLabel(LOCAL_MEDIA_STREAM_ID)
            mediaStream.addVideoTrack(localVideoTrack)
            mediaStream.addAudioTrack(localAudioTrack)

            localVideoTrack.addRenderer(renderer_sub)
        }
    }

    override func viewDidDisappear(animated: Bool) {
        // FIXME: temporarily placed here but should be somwhere called only when app terminates
        RTCPeerConnectionFactory.deinitializeSSL()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // webrtc
    var peerConnectionFactory: RTCPeerConnectionFactory! = nil
    var peerConnection: RTCPeerConnection! = nil
    var pcConstraints: RTCMediaConstraints! = nil
    var videoConstraints: RTCMediaConstraints! = nil
    var audioConstraints: RTCMediaConstraints! = nil
    var mediaConstraints: RTCMediaConstraints! = nil

    var socket: SocketIOClient! = nil
    var wsServerUrl: String! = nil
    var peerStarted: Bool = false

    func initWebRTC() {
        RTCPeerConnectionFactory.initializeSSL()
        peerConnectionFactory = RTCPeerConnectionFactory()

        pcConstraints = RTCMediaConstraints()
        videoConstraints = RTCMediaConstraints()
        audioConstraints = RTCMediaConstraints()
        mediaConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                RTCPair(key: "OfferToReceiveAudio", value: "true"),
                RTCPair(key: "OfferToReceiveVideo", value: "true")
            ],
            optionalConstraints: nil)
    }

    func connect() {
        if (!peerStarted) {
            sendOffer()
            peerStarted = true
        }
    }

    func hangUp() {
        sendDisconnect()
        stop()
    }

    func stop() {
        peerConnection.close()
        peerConnection = nil
        peerStarted = false
    }

    func prepareNewConnection() -> RTCPeerConnection {
        var icsServers: [RTCICEServer] = []
        var rtcConfig: RTCConfiguration = RTCConfiguration()
        rtcConfig.tcpCandidatePolicy = RTCTcpCandidatePolicy.Disabled
        rtcConfig.bundlePolicy = RTCBundlePolicy.MaxBundle
        rtcConfig.rtcpMuxPolicy = RTCRtcpMuxPolicy.Require

        peerConnection = peerConnectionFactory.peerConnectionWithICEServers(icsServers, constraints: pcConstraints, delegate: self)
        peerConnection.addStream(mediaStream);
        return peerConnection;
    }

    // RTCPeerConnectionDelegate - begin [
    func peerConnection(peerConnection: RTCPeerConnection!, signalingStateChanged stateChanged: RTCSignalingState) {
    }

    func peerConnection(peerConnection: RTCPeerConnection!, iceConnectionChanged newState: RTCICEConnectionState) {
    }

    func peerConnection(peerConnection: RTCPeerConnection!, iceGatheringChanged newState: RTCICEGatheringState) {
    }

    func peerConnection(peerConnection: RTCPeerConnection!, gotICECandidate candidate: RTCICECandidate!) {
        if (candidate != nil) {
            Log("iceCandidate: " + candidate.description)
            var json:[String: AnyObject] = [
                "type" : "candidate",
                "sdpMLineIndex" : candidate.sdpMLineIndex,
                "sdpMid" : candidate.sdpMid,
                "candidate" : candidate.sdp
            ]
            sigSend(json)
        } else {
            Log("End of candidates. -------------------")
        }
    }

    func peerConnection(peerConnection: RTCPeerConnection!, addedStream stream: RTCMediaStream!) {
        if (peerConnection == nil) {
            return
        }
        if (stream.audioTracks.count > 1 || stream.videoTracks.count > 1) {
            Log("Weird-looking stream: " + stream.description)
            return
        }
        if (stream.videoTracks.count == 1) {
            remoteVideoTrack = stream.videoTracks[0] as! RTCVideoTrack
            remoteVideoTrack.setEnabled(true)
            remoteVideoTrack.addRenderer(renderer);
        }
    }

    func peerConnection(peerConnection: RTCPeerConnection!, removedStream stream: RTCMediaStream!) {
        remoteVideoTrack = nil
//        stream.videoTracks[0].dispose();
    }

    func peerConnection(peerConnection: RTCPeerConnection!, didOpenDataChannel dataChannel: RTCDataChannel!) {
    }

    func peerConnectionOnRenegotiationNeeded(peerConnection: RTCPeerConnection!) {
    }
    // RTCPeerConnectionDelegate - end ]

    func onOffer(sdp:RTCSessionDescription) {
        setOffer(sdp)
        sendAnswer()
        peerStarted = true;
    }

    func onAnswer(sdp:RTCSessionDescription) {
        setAnswer(sdp)
    }

    func onCandidate(candidate:RTCICECandidate) {
        peerConnection.addICECandidate(candidate)
    }

    func sendSDP(sdp:RTCSessionDescription) {
        var json:[String: AnyObject] = [
            "type" : sdp.type,
            "sdp"  : sdp.description
        ]
        sigSend(json);
    }

    func sendOffer() {
        peerConnection = prepareNewConnection();
        peerConnection.createOfferWithDelegate(self, constraints: mediaConstraints)
    }

    func setOffer(sdp:RTCSessionDescription) {
        if (peerConnection != nil) {
            Log("peer connection already exists")
        }
        peerConnection = prepareNewConnection();
        peerConnection.setRemoteDescriptionWithDelegate(self, sessionDescription: sdp)
    }

    func sendAnswer() {
        Log("sending Answer. Creating remote session description...")
        if (peerConnection == nil) {
            Log("peerConnection NOT exist!")
            return
        }
        peerConnection.createAnswerWithDelegate(self, constraints: mediaConstraints)
    }

    func setAnswer(sdp:RTCSessionDescription) {
        if (peerConnection == nil) {
            Log("peerConnection NOT exist!")
            return
        }
        peerConnection.setRemoteDescriptionWithDelegate(self, sessionDescription: sdp)
    }

    func sendDisconnect() {
        var json:[String: AnyObject] = [
            "type" : "user disconnected"
        ]
        sigSend(json);
    }

    func peerConnection(peerConnection: RTCPeerConnection!, didCreateSessionDescription sdp: RTCSessionDescription!, error: NSError!) {
        if (error == nil) {
            peerConnection.setLocalDescriptionWithDelegate(self, sessionDescription: sdp)
            Log("Sending: SDP")
            Log(sdp.description)
            sendSDP(sdp)
        } else {
            Log("sdp creation error: " + error.description)
        }
    }

    func peerConnection(peerConnection: RTCPeerConnection!, didSetSessionDescriptionWithError error: NSError!) {
    }

    // websocket related operations
    func sigConnect(wsUrl:String) {
        wsServerUrl = wsUrl;

        var opts:[String: AnyObject] = [
            "log"  : true
        ]
        Log("connecting to " + wsServerUrl)
        socket = SocketIOClient(socketURL: wsServerUrl, opts: opts)
        socket.on("connect") { data in
            self.Log("WebSocket connection opened to: " + self.wsServerUrl);
        }
        socket.on("disconnect") { data in
            self.Log("WebSocket connection closed.")
        }
        socket.on("message") { (data, emitter) in
            if (data!.count == 0) {
                return
            }

            var json = data![0] as! NSDictionary
            self.Log("WSS->C: " + json.description);

            var type = json["type"] as! String

            if (type == "offer") {
                self.Log("Received offer, set offer, sending answer....");
                var sdp = RTCSessionDescription(type: type, sdp: json["sdp"] as! String)
                self.onOffer(sdp);
            } else if (type == "answer" && self.peerStarted) {
                self.Log("Received answer, setting answer SDP");
                var sdp = RTCSessionDescription(type: type, sdp: json["sdp"] as! String)
                self.onAnswer(sdp);
            } else if (type == "candidate" && self.peerStarted) {
                self.Log("Received ICE candidate...");
                var candidate = RTCICECandidate(
                    mid: json["sdpMid"] as! String,
                    index: json["sdpMLineIndex"] as! Int,
                    sdp: json["candidate"] as! String)
                self.onCandidate(candidate);
            } else if (type == "user disconnected" && self.peerStarted) {
                self.Log("disconnected");
                self.stop();
            } else {
                self.Log("Unexpected WebSocket message: " + data![0].description);
            }
        }
        socket.connect();
    }

    func sigSend(msg:NSDictionary) {
        socket.emit("message", msg)
    }
}
