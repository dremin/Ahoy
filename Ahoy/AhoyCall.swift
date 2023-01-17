//
//  CallMetadata.swift
//  Ahoy
//
//  Created by Sam Johnson on 10/10/22.
//

import Foundation
import TwilioVoice

struct AhoyCall {
    var call: Call
    var isUserDisconnected = false
    var isOutbound = false
    var outboundAddress = ""
    var status: CallStatus = .connecting
}

enum CallStatus {
    case connecting
    case ringing
    case connected
    case disconnecting
}
