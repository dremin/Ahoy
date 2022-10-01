//
//  ViewController.swift
//  Ahoy
//
//  Created by Sam Johnson on 9/19/22.
//

import UIKit
import os
import TwilioVoice

class ViewController: UIViewController {
    @IBOutlet weak var placeCallStack: UIStackView!
    @IBOutlet weak var placeCallInput: UITextField!
    
    @IBOutlet weak var activeCallStack: UIStackView!
    @IBOutlet weak var activeCallTitle: UILabel!
    @IBOutlet weak var muteButton: UIButton!
    @IBOutlet weak var holdButton: UIButton!
    @IBOutlet weak var speakerButton: UIButton!
    @IBOutlet weak var endCallButton: UIButton!
    
    var logger = Logger()
    
    // Rudimentary UI currently supports only one call at a time
    var activeCall: Call?
    var voiceOrchestrator: VoiceOrchestrator?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        placeCallInput.delegate = self
        
        // Get VoiceOrchestrator and set callback functions
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        voiceOrchestrator = appDelegate.voiceOrchestrator
        voiceOrchestrator?.callAdded = callAdded
        voiceOrchestrator?.callRemoved = callRemoved
        voiceOrchestrator?.callUpdated = callUpdated
    }
    
    @IBAction func placeCallButtonClicked(_ sender: UIButton) {
        placeCall()
    }
    
    @IBAction func muteButtonClicked(_ sender: UIButton) {
        guard let activeCall = activeCall else {
            logger.error("Unable to mute: No active call")
            return
        }
        
        voiceOrchestrator?.setMute(uuid: activeCall.uuid!, mute: !activeCall.isMuted)
    }
    
    @IBAction func holdButtonClicked(_ sender: UIButton) {
        guard let activeCall = activeCall else {
            logger.error("Unable to hold: No active call")
            return
        }
        
        voiceOrchestrator?.setHold(uuid: activeCall.uuid!, hold: !activeCall.isOnHold)
    }
    
    @IBAction func speakerButtonClicked(_ sender: UIButton) {
        guard let voiceOrchestrator = voiceOrchestrator else {
            logger.error("Unable to set output: No voiceOrchestrator")
            return
        }
        
        let newOutputIsSpeaker = !voiceOrchestrator.isSpeakerOutput
        
        voiceOrchestrator.toggleAudioRoute(toSpeaker: newOutputIsSpeaker)
        
        if newOutputIsSpeaker {
            speakerButton.setTitle("Headset", for: .normal)
            speakerButton.setImage(UIImage(systemName: "iphone"), for: .normal)
        } else {
            speakerButton.setTitle("Speaker", for: .normal)
            speakerButton.setImage(UIImage(systemName: "speaker.wave.3.fill"), for: .normal)
        }
    }

    @IBAction func endCallButtonClicked(_ sender: UIButton) {
        guard let activeCall = activeCall else {
            logger.error("Unable to end call: No active call")
            return
        }
        
        voiceOrchestrator?.endCall(uuid: activeCall.uuid!)
    }
    
    func placeCall() {
        placeCallInput.resignFirstResponder()
        
        checkRecordPermission { [weak self] permissionGranted in
            if permissionGranted {
                self?.doPlaceCall()
            } else {
                self?.showMicrophoneAccessRequest()
            }
        }
    }
    
    func doPlaceCall() {
        guard let to = placeCallInput.text else {
            logger.error("Unable to place call: No target")
            return
        }
        
        voiceOrchestrator?.placeCall(to: to)
    }
    
    func updateUI(call: Call) {
        activeCall = call
        
        activeCallTitle.text = voiceOrchestrator?.formatNumber(remote: call.from ?? call.to)
        
        if call.isOnHold {
            holdButton.setTitle("Unhold", for: .normal)
            holdButton.setImage(UIImage(systemName: "speaker.fill"), for: .normal)
        } else {
            holdButton.setTitle("Hold", for: .normal)
            holdButton.setImage(UIImage(systemName: "speaker.slash.fill"), for: .normal)
        }
        
        if call.isMuted {
            muteButton.setTitle("Unmute", for: .normal)
            muteButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        } else {
            muteButton.setTitle("Mute", for: .normal)
            muteButton.setImage(UIImage(systemName: "mic.slash.fill"), for: .normal)
        }
    }
    
    // MARK: VoiceOrchestrator callbacks
    
    func callAdded(call: Call) {
        DispatchQueue.main.async { [weak self] in
            self?.activeCallStack.isHidden = false
            self?.placeCallStack.isHidden = true
            self?.updateUI(call: call)
        }
    }
    
    func callRemoved(call: Call) {
        guard let voiceOrchestrator = voiceOrchestrator else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            // Check if there is another active call
            guard let otherCall = voiceOrchestrator.activeCalls.first?.value else {
                // No active calls, hide call UI
                self?.activeCallStack.isHidden = true
                self?.placeCallStack.isHidden = false
                return
            }
            
            // Update UI for the other active call
            self?.updateUI(call: otherCall)
        }
    }
    
    func callUpdated(call: Call) {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI(call: call)
        }
    }
    
    // MARK: Microphone access
    
    func checkRecordPermission(completion: @escaping (_ permissionGranted: Bool) -> Void) {
        let permissionStatus = AVAudioSession.sharedInstance().recordPermission
        
        switch permissionStatus {
        case .granted:
            // Record permission already granted.
            completion(true)
        case .denied:
            // Record permission denied.
            completion(false)
        case .undetermined:
            // Requesting record permission.
            // Optional: pop up app dialog to let the users know if they want to request.
            AVAudioSession.sharedInstance().requestRecordPermission { granted in completion(granted) }
        default:
            completion(false)
        }
    }
    
    func showMicrophoneAccessRequest() {
        let alertController = UIAlertController(title: "Microphone Permission Required",
                                                message: "Phone calls require permission to use your microphone. This can be enabled in Settings.",
                                                preferredStyle: .alert)
        
        let continueWithoutMic = UIAlertAction(title: "Continue without microphone", style: .default) { [weak self] _ in
            self?.doPlaceCall()
        }
        
        let goToSettings = UIAlertAction(title: "Open Settings", style: .default) { _ in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                      options: [UIApplication.OpenExternalURLOptionsKey.universalLinksOnly: false],
                                      completionHandler: nil)
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in
        }
        
        [continueWithoutMic, goToSettings, cancel].forEach { alertController.addAction($0) }
        
        present(alertController, animated: true, completion: nil)
    }
}

// MARK: - UITextFieldDelegate

extension ViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        placeCall()
        return true
    }
}
