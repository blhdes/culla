//
//  CullaScreenshots.swift
//  CullaScreenshots
//
//  Created by Ale Gómez Urrea on 28/3/26.
//

import XCTest

@MainActor
class CullaScreenshotsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScreenshots"]
        setupSnapshot(app)
        app.launch()
    }

    func testTakeScreenshots() {
        let app = XCUIApplication()

        // Wait for the library to finish loading
        sleep(5)
        
        snapshot("01_Home")
    }
}
