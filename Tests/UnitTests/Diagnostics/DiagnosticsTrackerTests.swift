//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  DiagnosticsTrackerTests.swift
//
//  Created by Cesar de la Vega on 11/4/24.

import Foundation
import Nimble

@testable import RevenueCat

@available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
class DiagnosticsTrackerTests: TestCase {

    fileprivate var fileHandler: FileHandler!
    fileprivate var handler: DiagnosticsFileHandler!
    fileprivate var tracker: DiagnosticsTracker!
    fileprivate var diagnosticsDispatcher: MockOperationDispatcher!
    fileprivate var dateProvider: MockDateProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()

        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        self.fileHandler = try Self.createWithTemporaryFile()
        self.handler = .init(self.fileHandler)
        self.diagnosticsDispatcher = MockOperationDispatcher()
        self.dateProvider = .init(stubbedNow: Self.eventTimestamp1, subsequentNows: Self.eventTimestamp2)
        self.tracker = .init(diagnosticsFileHandler: self.handler,
                             diagnosticsDispatcher: self.diagnosticsDispatcher,
                             dateProvider: self.dateProvider)
    }

    override func tearDown() async throws {
        self.handler = nil

        try await super.tearDown()
    }

    // MARK: - trackEvent

    func testTrackEvent() async {
        let event = DiagnosticsEvent(eventType: .httpRequestPerformed,
                                     properties: [.verificationResultKey: AnyEncodable("FAILED")],
                                     timestamp: Self.eventTimestamp1)

        self.tracker.track(event)

        let entries = await self.handler.getEntries()
        expect(entries) == [
            .init(eventType: .httpRequestPerformed,
                  properties: [.verificationResultKey: AnyEncodable("FAILED")],
                  timestamp: Self.eventTimestamp1)
        ]
    }

    func testTrackMultipleEvents() async {
        let event1 = DiagnosticsEvent(eventType: .httpRequestPerformed,
                                      properties: [.verificationResultKey: AnyEncodable("FAILED")],
                                      timestamp: Self.eventTimestamp1)
        let event2 = DiagnosticsEvent(eventType: .customerInfoVerificationResult,
                                      properties: [.verificationResultKey: AnyEncodable("FAILED")],
                                      timestamp: Self.eventTimestamp2)

        self.tracker.track(event1)
        self.tracker.track(event2)

        let entries = await self.handler.getEntries()
        expect(entries) == [
            .init(eventType: .httpRequestPerformed,
                  properties: [.verificationResultKey: AnyEncodable("FAILED")],
                  timestamp: Self.eventTimestamp1),
            .init(eventType: .customerInfoVerificationResult,
                  properties: [.verificationResultKey: AnyEncodable("FAILED")],
                  timestamp: Self.eventTimestamp2)
        ]
    }

    // MARK: - customer info verification

    func testDoesNotTrackWhenVerificationIsNotRequested() async {
        let customerInfo: CustomerInfo = .emptyInfo.copy(with: .notRequested)

        self.tracker.trackCustomerInfoVerificationResultIfNeeded(customerInfo)

        let entries = await self.handler.getEntries()
        expect(entries.count) == 0
    }

    func testTracksCustomerInfoVerificationFailed() async {
        let customerInfo: CustomerInfo = .emptyInfo.copy(with: .failed)

        self.tracker.trackCustomerInfoVerificationResultIfNeeded(customerInfo)

        let entries = await self.handler.getEntries()
        expect(entries) == [
            .init(eventType: .customerInfoVerificationResult,
                  properties: [.verificationResultKey: AnyEncodable("FAILED")],
                  timestamp: Self.eventTimestamp1)
        ]
    }

    // MARK: - http request performed

    func testTracksHttpRequestPerformedWithExpectedParameters() async {
        self.tracker.trackHttpRequestPerformed(endpointName: "mock_endpoint",
                                               responseTime: 50,
                                               wasSuccessful: true,
                                               responseCode: 200,
                                               backendErrorCode: 7121,
                                               resultOrigin: .cache,
                                               verificationResult: .verified)
        let entries = await self.handler.getEntries()
        expect(entries) == [
            .init(eventType: .httpRequestPerformed,
                  properties: [
                    .endpointNameKey: AnyEncodable("mock_endpoint"),
                    .responseTimeMillisKey: AnyEncodable(50000),
                    .successfulKey: AnyEncodable(true),
                    .responseCodeKey: AnyEncodable(200),
                    .backendErrorCodeKey: AnyEncodable(7121),
                    .eTagHitKey: AnyEncodable(true),
                    .verificationResultKey: AnyEncodable("VERIFIED")],
                  timestamp: Self.eventTimestamp1)
        ]
    }

    // MARK: - product request

    func testTracksProductRequestWithExpectedParameters() async {
        self.tracker.trackProductsRequest(wasSuccessful: false,
                                          storeKitVersion: .storeKit2,
                                          errorMessage: "test error message",
                                          errorCode: 1234,
                                          storeKitErrorDescription: "store_kit_error_type",
                                          requestedProductIds: ["test_product_id_1", "test_product_id_2"],
                                          notFoundProductIds: ["test_product_id_2"],
                                          responseTime: 50)
        let emptyErrorMessage: String? = nil
        let emptyErrorCode: Int? = nil
        let emptySkErrorDescription: String? = nil
        self.tracker.trackProductsRequest(wasSuccessful: true,
                                          storeKitVersion: .storeKit1,
                                          errorMessage: emptyErrorMessage,
                                          errorCode: emptyErrorCode,
                                          storeKitErrorDescription: emptySkErrorDescription,
                                          requestedProductIds: ["test_product_id_3", "test_product_id_4"],
                                          notFoundProductIds: [],
                                          responseTime: 20)

        let entries = await self.handler.getEntries()
        expect(entries) == [
            .init(eventType: .appleProductsRequest,
                  properties: [
                    .responseTimeMillisKey: AnyEncodable(50000),
                    .storeKitVersion: AnyEncodable("store_kit_2"),
                    .successfulKey: AnyEncodable(false),
                    .errorMessageKey: AnyEncodable("test error message"),
                    .skErrorDescriptionKey: AnyEncodable("store_kit_error_type"),
                    .requestedProductIdsKey: AnyEncodable(["test_product_id_1", "test_product_id_2"]),
                    .notFoundProductIdsKey: AnyEncodable(["test_product_id_2"]),
                    .errorCodeKey: AnyEncodable(1234)],
                  timestamp: Self.eventTimestamp1),
            .init(eventType: .appleProductsRequest,
                  properties: [
                    .responseTimeMillisKey: AnyEncodable(20000),
                    .storeKitVersion: AnyEncodable("store_kit_1"),
                    .successfulKey: AnyEncodable(true),
                    .errorMessageKey: AnyEncodable(emptyErrorMessage),
                    .skErrorDescriptionKey: AnyEncodable(emptySkErrorDescription),
                    .requestedProductIdsKey: AnyEncodable(["test_product_id_3", "test_product_id_4"]),
                    .notFoundProductIdsKey: AnyEncodable([]),
                    .errorCodeKey: AnyEncodable(emptyErrorCode)],
                  timestamp: Self.eventTimestamp2)
        ]
    }

    // MARK: - Purchase Request

    func testTracksPurchaseRequestWithExpectedParameters() async {
        self.tracker.trackPurchaseRequest(wasSuccessful: true,
                                          storeKitVersion: .storeKit2,
                                          errorMessage: nil,
                                          errorCode: nil,
                                          storeKitErrorDescription: nil,
                                          productId: "com.revenuecat.product1",
                                          promotionalOfferId: nil,
                                          winBackOfferApplied: false,
                                          purchaseResult: .verified,
                                          responseTime: 75)

        let emptyErrorMessage: String? = nil
        let emptyErrorCode: Int? = nil
        let emptyPromotionalOfferId: String? = nil
        let emptySkErrorDescription: String? = nil
        let entries = await self.handler.getEntries()
        expect(entries) == [
            .init(eventType: .applePurchaseAttempt,
                  properties: [
                    .responseTimeMillisKey: AnyEncodable(75000),
                    .storeKitVersion: AnyEncodable("store_kit_2"),
                    .successfulKey: AnyEncodable(true),
                    .errorMessageKey: AnyEncodable(emptyErrorMessage),
                    .skErrorDescriptionKey: AnyEncodable(emptySkErrorDescription),
                    .productIdKey: AnyEncodable("com.revenuecat.product1"),
                    .promotionalOfferIdKey: AnyEncodable(emptyPromotionalOfferId),
                    .winBackOfferAppliedKey: AnyEncodable(false),
                    .purchaseResultKey: AnyEncodable("verified"),
                    .errorCodeKey: AnyEncodable(emptyErrorCode)],
                  timestamp: Self.eventTimestamp1)
        ]
    }

    func testTracksPurchaseRequestWithPromotionalOffer() async {
        self.tracker.trackPurchaseRequest(wasSuccessful: false,
                                          storeKitVersion: .storeKit1,
                                          errorMessage: "purchase failed",
                                          errorCode: 5678,
                                          storeKitErrorDescription: "payment_cancelled",
                                          productId: "com.revenuecat.premium",
                                          promotionalOfferId: "summer_discount_2023",
                                          winBackOfferApplied: true,
                                          purchaseResult: .userCancelled,
                                          responseTime: 120)

        let entries = await self.handler.getEntries()
        expect(entries) == [
            .init(eventType: .applePurchaseAttempt,
                  properties: [
                    .responseTimeMillisKey: AnyEncodable(120000),
                    .storeKitVersion: AnyEncodable("store_kit_1"),
                    .successfulKey: AnyEncodable(false),
                    .errorMessageKey: AnyEncodable("purchase failed"),
                    .skErrorDescriptionKey: AnyEncodable("payment_cancelled"),
                    .productIdKey: AnyEncodable("com.revenuecat.premium"),
                    .promotionalOfferIdKey: AnyEncodable("summer_discount_2023"),
                    .winBackOfferAppliedKey: AnyEncodable(true),
                    .purchaseResultKey: AnyEncodable("user_cancelled"),
                    .errorCodeKey: AnyEncodable(5678)],
                  timestamp: Self.eventTimestamp1)
        ]
    }

    // MARK: - empty diagnostics file when too big

    func testTrackingEventClearsDiagnosticsFileIfTooBig() async throws {
        for _ in 0...8000 {
            await self.handler.appendEvent(diagnosticsEvent: .init(eventType: .httpRequestPerformed,
                                                                   properties: [:],
                                                                   timestamp: Date()))
        }

        let entries = await self.handler.getEntries()
        expect(entries.count) == 8001

        let event = DiagnosticsEvent(eventType: .httpRequestPerformed,
                                     properties: [.verificationResultKey: AnyEncodable("FAILED")],
                                     timestamp: Self.eventTimestamp2)

        self.tracker.track(event)

        let entries2 = await self.handler.getEntries()
        expect(entries2.count) == 2
        expect(entries2) == [
            .init(eventType: .maxEventsStoredLimitReached,
                  properties: [:],
                  timestamp: Self.eventTimestamp1),
            .init(eventType: .httpRequestPerformed,
                  properties: [.verificationResultKey: AnyEncodable("FAILED")],
                  timestamp: Self.eventTimestamp2)
        ]
    }

}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
private extension DiagnosticsTrackerTests {

    static let eventTimestamp1: Date = .init(timeIntervalSince1970: 1694029328)
    static let eventTimestamp2: Date = .init(timeIntervalSince1970: 1694022321)

    static func temporaryFileURL() -> URL {
        return FileManager.default
            .temporaryDirectory
            .appendingPathComponent("file_handler_tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("jsonl")
    }

    static func createWithTemporaryFile() throws -> FileHandler {
        return try FileHandler(Self.temporaryFileURL())
    }
}
