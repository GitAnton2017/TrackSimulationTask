//
//  APIFeedLoader.swift
//  TrackSimulationTask
//
//  Created by Anton2016 on 20.09.2022.
//

import Foundation

protocol APIDataFeedRepresentable{
 var endPoint: URL { get }
 var dataFeed: Data { get async throws }
}

class APIDataFeedLoader: APIDataFeedRepresentable {
 var dataFeed: Data {
  get async throws {
   try Data(contentsOf: endPoint)
  }
 }
 
 let endPoint: URL
 
 init? (resourcePath: String) {
  guard let url = URL(string: resourcePath) else { return nil }
  self.endPoint = url
 }
}

class APIDataLocalFeedLoader: APIDataFeedRepresentable {
 var dataFeed: Data {
  get async throws {
   try Data(contentsOf: endPoint)
  }
 }
 
 let endPoint: URL
 
 init? () {
  guard let url = Bundle.main.url(forResource: "data", withExtension: "json") else { return nil }
  self.endPoint = url
 }
}
