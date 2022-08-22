//
//  FeedLoader.swift
//  EssentialFeed
//
//  Created by Marco Maddalena on 29.07.22.
//

import Foundation

public enum LoadFeedResult {
    case success([FeedImage])
    case failure(Error)
}

public protocol FeedLoader {
    func load(completion: @escaping (LoadFeedResult) -> Void)
}
