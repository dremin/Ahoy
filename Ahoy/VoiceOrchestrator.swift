//
//  VoiceOrchestrator.swift
//  Ahoy
//
//  Created by Sam Johnson on 9/19/22.
//

import Foundation
import os
import CallKit
import PushKit
import TwilioVoice

class VoiceOrchestrator: NSObject {
    var logger = Logger()
    
    // CallKit properties
    var callKitProvider: CXProvider?
    var callKitCallController = CXCallController()
    var callKitCompletionCallback: ((Bool) -> Void)? = nil
    
    // TwilioVoice properties
    var audioDevice = DefaultAudioDevice()
    var activeCallInvites: [String: CallInvite]! = [:]
    var activeCalls: [String: Call]! = [:]
    var userDisconnectedCalls: [String] = []
    var isSpeakerOutput = false
    
    // Callback functions
    var callAdded: ((Call) -> Void)? = nil
    var callRemoved: ((Call) -> Void)? = nil
    var callUpdated: ((Call) -> Void)? = nil
    
    override init() {
        super.init()
        
        let callKitConfig = CXProviderConfiguration()
        callKitConfig.maximumCallGroups = 1
        callKitConfig.maximumCallsPerCallGroup = 1
        callKitConfig.supportedHandleTypes = [ .phoneNumber, .generic ]
        
        callKitProvider = CXProvider(configuration: callKitConfig)
        
        if let provider = callKitProvider {
            provider.setDelegate(self, queue: nil)
        }
    }
    
    deinit {
        if let provider = callKitProvider {
            provider.invalidate()
        }
    }
    
    // MARK: Helper functions
    
    func createCallUpdate(withHandle callHandle: CXHandle) -> CXCallUpdate {
        let callUpdate = CXCallUpdate()
        
        callUpdate.remoteHandle = callHandle
        callUpdate.supportsDTMF = true
        callUpdate.supportsHolding = true
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = false
        
        return callUpdate
    }
    
    func formatNumber(remote name: String?) -> String {
        let formatted = (name ?? "Unknown").replacingOccurrences(of: "client:", with: "")
        
        return formatted
    }
    
    func createHandle(remote name: String?, format: Bool) -> CXHandle {
        // Format the from address as needed
        let formatted = format ? formatNumber(remote: name) : name ?? ""
        
        // The CXHandle represents the identity of the remote party.
        // Type should be .phoneNumber for phone numbers, others should be .generic.
        var type = CXHandle.HandleType.generic
        
        if formatted.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil {
            type = .phoneNumber
        }
        
        let callHandle = CXHandle(type: type, value: formatted)
        
        return callHandle
    }
    
    func endCall(uuid: UUID) {
        // User-initiated disconnect
        userDisconnectedCalls.append(uuid.uuidString)
        
        // Tell CallKit that this call is ending. This will then call provider:performEndCallAction:
        // where we will actually end the call.
        
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        
        callKitCallController.request(transaction) { error in
            if let error = error {
                self.logger.error("EndCallAction transaction request failed: \(error.localizedDescription).")
            } else {
                self.logger.debug("EndCallAction transaction request successful")
            }
        }
    }
    
    func setHold(uuid: UUID, hold: Bool) {
        // Tell CallKit that this call is changing hold state. This will then call provider:performSetHeldCallAction:
        // where we will actually hold/unhold the call.
        
        let action = CXSetHeldCallAction(call: uuid, onHold: hold)
        let transaction = CXTransaction(action: action)
        
        callKitCallController.request(transaction) { error in
            if let error = error {
                self.logger.error("SetHeldCallAction transaction request failed: \(error.localizedDescription).")
            } else {
                self.logger.debug("SetHeldCallAction transaction request successful")
            }
        }
    }
    
    func setMute(uuid: UUID, mute: Bool) {
        // Tell CallKit that this call is changing mute state. This will then call provider:performSetMutedCallAction:
        // where we will actually mute/unmute the call.
        
        let action = CXSetMutedCallAction(call: uuid, muted: mute)
        let transaction = CXTransaction(action: action)
        
        callKitCallController.request(transaction) { error in
            if let error = error {
                self.logger.error("SetMutedCallAction transaction request failed: \(error.localizedDescription).")
            } else {
                self.logger.debug("SetMutedCallAction transaction request successful")
            }
        }
    }
    
    func placeCall(to: String) {
        // Tell CallKit to place a call. This will then call provider:performStartCallAction: where we will actually do it.
        
        guard let provider = callKitProvider else {
            logger.error("CallKit provider not available")
            return
        }
        
        let sanitized = to.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        
        let callHandle = createHandle(remote: sanitized, format: false)
        let uuid = UUID()
        let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
        let transaction = CXTransaction(action: startCallAction)
        
        callKitCallController.request(transaction) { error in
            if let error = error {
                self.logger.error("StartCallAction transaction request failed: \(error.localizedDescription)")
                return
            }
            
            let callUpdate = self.createCallUpdate(withHandle: callHandle)
            provider.reportCall(with: uuid, updated: callUpdate)
        }
    }
    
    func toggleAudioRoute(toSpeaker: Bool) {
        // The mode set by the Voice SDK is "VoiceChat" so the default audio route is the built-in receiver. Use port override to switch the route.
        audioDevice.block = {
            DefaultAudioDevice.DefaultAVAudioSessionConfigurationBlock()
            
            do {
                if toSpeaker {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                    self.isSpeakerOutput = true
                } else {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                    self.isSpeakerOutput = false
                }
            } catch {
                self.logger.error("overrideOutputAudioPort failed: \(error.localizedDescription)")
            }
        }
        
        audioDevice.block()
    }
}

// MARK: CXProviderDelegate

extension VoiceOrchestrator: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        logger.debug("providerDidReset:")
        
        audioDevice.isEnabled = false
    }

    func providerDidBegin(_ provider: CXProvider) {
        logger.debug("providerDidBegin:")
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        logger.debug("provider:didActivateAudioSession:")
        
        audioDevice.isEnabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        logger.debug("provider:didDeactivateAudioSession:")
        
        audioDevice.isEnabled = false
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        logger.debug("provider:timedOutPerformingAction:")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        logger.debug("provider:performStartCallAction:")
        
        // Tell CallKit that the call attempt is being made
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        
        // Set up the call
        let connectOptions = ConnectOptions(accessToken: accessToken) { builder in
            builder.params = [ "to": action.handle.value ]
            builder.uuid = action.callUUID
        }
        let call = TwilioVoiceSDK.connect(options: connectOptions, delegate: self)
        
        // Update state
        activeCalls[call.uuid!.uuidString] = call
        callAdded?(call)
        
        callKitCompletionCallback = { success in
            if success {
                self.logger.debug("Created call SID \(call.sid)")
                provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
            } else {
                self.logger.error("Unable to create call")
            }
            
            self.callKitCompletionCallback = nil
        }
        
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        logger.debug("provider:performAnswerCallAction:")
        // User has selected to answer the call
        
        // Match UUID to the previously received CallInvite
        guard let callInvite = activeCallInvites[action.callUUID.uuidString] else {
            logger.error("No CallInvite matches the UUID")
            action.fail()
            return
        }
        
        // Accept the CallInvite
        let acceptOptions = AcceptOptions(callInvite: callInvite) { builder in
            builder.uuid = callInvite.uuid
        }
        
        let call = callInvite.accept(options: acceptOptions, delegate: self)
        
        // Update our state
        activeCalls[call.uuid!.uuidString] = call
        activeCallInvites.removeValue(forKey: callInvite.uuid.uuidString)
        callAdded?(call)
        
        logger.debug("Accepted call SID \(call.sid)")
        
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        logger.debug("provider:performEndCallAction:")
        
        if let invite = activeCallInvites[action.callUUID.uuidString] {
            // Call was not yet answered; reject the invite
            invite.reject()
            activeCallInvites.removeValue(forKey: action.callUUID.uuidString)
        } else if let call = activeCalls[action.callUUID.uuidString] {
            // Disconnect the call
            call.disconnect()
        } else {
            logger.error("Unknown UUID to perform EndCallAction with")
            // Even though we failed, don't return an error--let the system know there's no call
        }
        
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        logger.debug("provider:performSetHeldAction:")
        
        guard let call = activeCalls[action.callUUID.uuidString] else {
            logger.error("Unknown UUID to perform SetHeldCallAction with")
            action.fail()
            return
        }
        
        call.isOnHold = action.isOnHold
        callUpdated?(call)
        
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        logger.debug("provider:performSetMutedAction:")
        
        guard let call = activeCalls[action.callUUID.uuidString] else {
            logger.error("Unknown UUID to perform SetMutedCallAction with")
            action.fail()
            return
        }
        
        call.isMuted = action.isMuted
        callUpdated?(call)
        
        action.fulfill()
    }
}

// MARK: TVONotificationDelegate

extension VoiceOrchestrator: NotificationDelegate {
    func callInviteReceived(callInvite: CallInvite) {
        logger.debug("callInviteReceived")
        // Once the SDK processes the push payload and determined it contains a CallInvite, this is called.
        
        /**
         * The TTL of a registration is 1 year. The TTL for registration for this device/identity
         * pair is reset to 1 year whenever a new registration occurs or a push notification is
         * sent to this device/identity pair.
         */
        UserDefaults.standard.set(Date(), forKey: kCachedBindingDate)
        
        // Cache the invite so that we have it when the user performs an action on it
        activeCallInvites[callInvite.uuid.uuidString] = callInvite
        
        guard let provider = callKitProvider else {
            logger.debug("CallKit provider not available")
            return
        }
        
        // The CXHandle represents the identity of the remote party.
        let callHandle = createHandle(remote: callInvite.from, format: true)
        
        // The CXCallUpdate defines the properties of the call for CallKit to use
        let callUpdate = createCallUpdate(withHandle: callHandle)
        
        // Notify CallKit of the call to display a notification to the user, record it in the call log, etc.
        provider.reportNewIncomingCall(with: callInvite.uuid, update: callUpdate) { error in
            if let error = error {
                self.logger.error("Failed to report incoming call to CallKit successfully: \(error.localizedDescription).")
            } else {
                self.logger.debug("Incoming call successfully reported to CallKit.")
            }
        }
    }
    
    func cancelledCallInviteReceived(cancelledCallInvite: CancelledCallInvite, error: Error) {
        logger.debug("cancelledCallInviteReceived, error: \(error.localizedDescription)")
        // Once the SDK processes the push payload and determined it contains a cancelled CallInvite, this is called.
        
        // Find the CallInvite that matches this notification payload
        guard let callInvite = (activeCallInvites.values.first { invite in invite.callSid == cancelledCallInvite.callSid }) else {
            logger.error("No pending call invite")
            return
        }
        
        // Perform standard end call action
        endCall(uuid: callInvite.uuid)
        
        // Remove the call from cache
        self.activeCallInvites.removeValue(forKey: callInvite.uuid.uuidString)
    }
}

// MARK: TVOCallDelegate
extension VoiceOrchestrator: CallDelegate {
    func callDidConnect(call: Call) {
        logger.debug("callDidConnect")
        
        if let callback = callKitCompletionCallback {
            callback(true)
        }
    }
    
    func callDidFailToConnect(call: Call, error: Error) {
        logger.debug("callDidFailToConnect: \(error.localizedDescription)")
        
        if let callback = callKitCompletionCallback {
            callback(false)
        }
        
        // Tell CallKit about the failure
        if let provider = callKitProvider {
            provider.reportCall(with: call.uuid!, endedAt: Date(), reason: CXCallEndedReason.failed)
        }
        
        // Update state
        activeCalls.removeValue(forKey: call.uuid!.uuidString)
        callRemoved?(call)
    }
    
    func callDidDisconnect(call: Call, error: Error?) {
        logger.debug("callDidDisconnect")
        
        if let index = userDisconnectedCalls.firstIndex(of: call.uuid!.uuidString) {
            // If the disconnect was user-initiated, CallKit is already aware
            // Remove the user-disconnected state for this call now that we don't need it any more
            userDisconnectedCalls.remove(at: index)
        } else {
            // Tell CallKit about the disconnect
            var reason = CXCallEndedReason.remoteEnded
            
            if error != nil {
                reason = .failed
            }
            
            if let provider = callKitProvider {
                provider.reportCall(with: call.uuid!, endedAt: Date(), reason: reason)
            }
        }
        
        // Update state
        activeCalls.removeValue(forKey: call.uuid!.uuidString)
        callRemoved?(call)
    }
}
