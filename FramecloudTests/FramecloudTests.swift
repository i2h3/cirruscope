//
//  FramecloudTests.swift
//  FramecloudTests
//
//  Created by Iva Horn on 22.07.25.
//

import Testing
@testable import Framecloud

struct FramecloudTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func userAgentContainsWebKitIdentification() async throws {
        let userAgent = FramecloudApp.userAgent
        
        // Verify that the user agent contains WebKit identification
        #expect(userAgent.contains("AppleWebKit"))
        #expect(userAgent.contains("Safari"))
        #expect(userAgent.contains("Mozilla"))
        
        // Verify that it still contains the app name
        #expect(userAgent.contains("Framecloud"))
        
        // Verify the format looks like a proper Safari user agent
        #expect(userAgent.hasPrefix("Mozilla/5.0"))
    }

}
