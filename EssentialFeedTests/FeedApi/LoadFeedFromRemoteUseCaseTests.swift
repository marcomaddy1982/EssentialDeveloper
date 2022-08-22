//
//  FeedLoaderTests.swift
//  EssentialFeedTests
//
//  Created by Marco Maddalena on 29.07.22.
//

import XCTest
import EssentialFeed

class LoadFeedFromRemoteUseCaseTests: XCTestCase {

    func test_init_doesNotRequestDataFromURL() {
        let client = HTTPClientMock()
        let url = URL(string: "https://a-generic-url")!
        _ = RemoteFeedLoader(url: url, client: client)
        
        XCTAssertTrue(client.requestedURLs.isEmpty)
    }
    
    func test_load_requestDataFromURL() {
        let url = URL(string: "https://a-generic-url")!
        let (client, sut) = makeSUT(url: url)
        
        sut.load() { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url])
    }
    
    func test_load_deliversErrorsClientError() {
        let (client, sut) = makeSUT()
        
        expect(sut: sut, toCompleteWith: failure(.connectivity)) {
            let clientError = NSError(domain: "Test",
                                      code: 0)
            client.complete(with: clientError)
        }
    }
    
    func test_load_deliversErrorsNon200HTTPResponse() {
        let (client, sut) = makeSUT()
        
        let codes =  [199, 201, 300, 400, 500]
        codes.enumerated().forEach { index, code in
            expect(sut: sut, toCompleteWith: failure(.invalidData)) {
                let json = makeItemsJSON([])
                client.complete(with: code, data: json ,index: index)
            }
        }
    }
    
    func test_load_deliversErrorsOn200HTTPResponseWithInvalidJSON() {
        let (client, sut) = makeSUT()
        
        expect(sut: sut, toCompleteWith: failure(.invalidData)) {
            let invalidJSON = Data("Invalid Json".utf8)
            client.complete(with: 200, data: invalidJSON)
        }
    }
    
    func test_load_deliversNoItemsOn200HTTPResponseWithEmptyJSONList() {
        let (client, sut) = makeSUT()
        
        expect(sut: sut, toCompleteWith: .success([])) {
            let emptyListJson = makeItemsJSON([])
            client.complete(with: 200, data: emptyListJson)
        }
    }
    
    func test_load_deliversItemsOn200HTTPResponseWithJSONItems() {
        let (client, sut) = makeSUT()
        
        let item1 = makeItem(id: UUID(),
                             imageURL: URL(string: "http://a-url.com")!)
        
        let item2 = makeItem(id: UUID(),
                             description: "a description",
                             location: "a location",
                             imageURL: URL(string: "http://another-url.com")!)
        
        let items = [item1.model, item2.model]
        
        expect(sut: sut, toCompleteWith: .success(items), when: {
            let json = makeItemsJSON([item1.json, item2.json])
            client.complete(with: 200, data: json)
        })
    }
    
    func test_loadTwice_requestDataFromURL() {
        let url = URL(string: "https://a-generic-url")!
        let (client, sut) = makeSUT(url: url)
        
        sut.load() { _ in }
        sut.load() { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url, url])
    }
    
    func test_load_doesNotDeliverResultAfterSUTInstanceHasBeenDeallocated() {
            let url = URL(string: "http://any-url.com")!
            let client = HTTPClientMock()
            var sut: RemoteFeedLoader? = RemoteFeedLoader(url: url, client: client)

            var capturedResults = [RemoteFeedLoader.Result]()
            sut?.load { capturedResults.append($0) }

            sut = nil
        
            client.complete(with: 200, data: makeItemsJSON([]))

            XCTAssertTrue(capturedResults.isEmpty)
        }
    
    // MARK: - Helpers
    
    private func makeSUT(url: URL = URL(string: "https://a-generic-url")!,
                         file: StaticString = #filePath,
                         line: UInt = #line) -> (HTTPClientMock, RemoteFeedLoader) {
        let client = HTTPClientMock()
        let sut = RemoteFeedLoader(url: url,
                                   client: client)
        
        trackForMemoryLeaks(sut, file: file, line: line)
        trackForMemoryLeaks(client, file: file, line: line)
        
        return (client, sut)
    }
    
    private func failure(_ error: RemoteFeedLoader.Error) -> RemoteFeedLoader.Result {
        return .failure(error)
    }
    
    private func makeItem(id: UUID, description: String? = nil, location: String? = nil, imageURL: URL) -> (model: FeedImage, json: [String: Any]) {
            let item = FeedImage(id: id, description: description, location: location, url: imageURL)

            let json = [
                "id": id.uuidString,
                "description": description,
                "location": location,
                "image": imageURL.absoluteString
            ].compactMapValues { $0 }

            return (item, json)
        }

        private func makeItemsJSON(_ items: [[String: Any]]) -> Data {
            let json = ["items": items]
            return try! JSONSerialization.data(withJSONObject: json)
        }
    
    private func expect(sut: RemoteFeedLoader,
                        toCompleteWith expectedResult: RemoteFeedLoader.Result,
                        when action: () -> Void,
                        file: StaticString = #filePath,
                        line: UInt = #line) {
        
        
        let exp = expectation(description: "Wait for load completion")
        
        sut.load { receivedResult in
            switch (receivedResult, expectedResult) {
            case let (.success(receivedItems), .success(expectedItems)):
                XCTAssertEqual(receivedItems, expectedItems, file: file, line: line)
                
            case let (.failure(receivedError as RemoteFeedLoader.Error), .failure(expectedError as RemoteFeedLoader.Error)):
                XCTAssertEqual(receivedError, expectedError, file: file, line: line)
                
            default:
                XCTFail("Expected result \(expectedResult) got \(receivedResult) instead", file: file, line: line)
            }
            
            exp.fulfill()
        }
        
        action()
        
        wait(for: [exp], timeout: 1.0)
    }
    
    private class HTTPClientMock: HTTPClient {
        private var messages = [(url: URL, completion: (HTTPClientResult) -> Void)]()

        var requestedURLs: [URL] {
            return messages.map { $0.url }
        }
        
        func get(from url: URL,
                 completion: @escaping (HTTPClientResult) -> Void) {
            messages.append((url, completion))
        }
        
        func complete(with error: Error, index: Int = 0) {
            messages[index].completion(.failure(error))
        }
        
        func complete(with statusCode: Int, data: Data, index: Int = 0) {
            let response = HTTPURLResponse(url: messages[index].url,
                                           statusCode: statusCode,
                                           httpVersion: nil,
                                           headerFields: nil)!
            messages[index].completion(.success(data, response))
        }
    }
}
