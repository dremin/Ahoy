//
//  PushDelegate.swift
//  Ahoy
//
//  Created by Sam Johnson on 9/28/22.
//

import Foundation
import os
import PushKit
import UIKit
import TwilioVoice

// % twilio token:voice --identity=bob --voice-app-sid=APxx --push-credential-sid=CRxx --ttl 86400

let accessToken = ""

let kRegistrationTTLInDays = 365

let kCachedDeviceToken = "CachedDeviceToken"
let kCachedBindingDate = "CachedBindingDate"

class PushDelegate: NSObject, PKPushRegistryDelegate {
    var logger = Logger()
    var voiceOrchestrator: VoiceOrchestrator
    
    init(_ voiceOrchestrator: VoiceOrchestrator) {
        self.voiceOrchestrator = voiceOrchestrator
        
        super.init()
        
        let voipRegistry = PKPushRegistry.init(queue: DispatchQueue.main)
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [ .voIP ]
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        logger.debug("pushRegistry:didUpdatePushCredentials:forType:")
        // Register push credentials with TwilioVoiceSDK.register if the device token is different from the cached one.
        
        guard
            (registrationRequired() || UserDefaults.standard.data(forKey: kCachedDeviceToken) != credentials.token)
        else {
            return
        }

        let cachedDeviceToken = credentials.token
        /*
         * Perform registration if a new device token is detected.
         */
        TwilioVoiceSDK.register(accessToken: accessToken, deviceToken: cachedDeviceToken) { error in
            if let error = error {
                self.logger.debug("An error occurred while registering: \(error.localizedDescription)")
            } else {
                self.logger.debug("Successfully registered for VoIP push notifications.")
                
                // Save the device token after successfully registered.
                UserDefaults.standard.set(cachedDeviceToken, forKey: kCachedDeviceToken)
                
                /**
                 * The TTL of a registration is 1 year. The TTL for registration for this device/identity
                 * pair is reset to 1 year whenever a new registration occurs or a push notification is
                 * sent to this device/identity pair.
                 */
                UserDefaults.standard.set(Date(), forKey: kCachedBindingDate)
            }
        }
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        logger.debug("pushRegistry:didInvalidatePushTokenForType:")
        // Unregister the device token with TwilioVoiceSDK.unregister.
        
        guard let deviceToken = UserDefaults.standard.data(forKey: kCachedDeviceToken) else { return }
        
        TwilioVoiceSDK.unregister(accessToken: accessToken, deviceToken: deviceToken) { error in
            if let error = error {
                self.logger.debug("An error occurred while unregistering: \(error.localizedDescription)")
            } else {
                self.logger.debug("Successfully unregistered from VoIP push notifications.")
            }
        }
        
        UserDefaults.standard.removeObject(forKey: kCachedDeviceToken)
        
        // Remove the cached binding as credentials are invalidated
        UserDefaults.standard.removeObject(forKey: kCachedBindingDate)
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        logger.debug("pushRegistry:didReceiveIncomingPushWithPayload:forType:completion:")

        // Give the payload to TwilioVoiceSDK.handleNotification
        TwilioVoiceSDK.handleNotification(payload.dictionaryPayload, delegate: voiceOrchestrator, delegateQueue: nil)
        
        /**
         * The Voice SDK processes the call notification and returns the call invite synchronously. Report the incoming call to
         * CallKit and fulfill the completion before exiting this callback method.
         * This happens on iOS >= 13.0.
         */
        completion()
    }
    
    /**
     * The TTL of a registration is 1 year. The TTL for registration for this device/identity pair is reset to
     * 1 year whenever a new registration occurs or a push notification is sent to this device/identity pair.
     * This method checks if binding exists in UserDefaults, and if half of TTL has been passed then the method
     * will return true, else false.
     */
    func registrationRequired() -> Bool {
        guard
            let lastBindingCreated = UserDefaults.standard.object(forKey: kCachedBindingDate)
        else { return true }
        
        let date = Date()
        var components = DateComponents()
        components.setValue(kRegistrationTTLInDays/2, for: .day)
        let expirationDate = Calendar.current.date(byAdding: components, to: lastBindingCreated as! Date)!

        if expirationDate.compare(date) == ComparisonResult.orderedDescending {
            return false
        }
        return true;
    }
}
