//
//  APIMock.swift
//  TrackSimulationTask
//
//  Created by Anton2016 on 20.09.2022.
//

import CoreLocation
import Foundation
import MapKit

infix operator <~~> : AdditionPrecedence
infix operator |<->| : AdditionPrecedence

struct TimePoint: Identifiable {
 let id = UUID()
 let time: Date
 let location: CLLocationCoordinate2D
 var speed: Double = 0.00
 let latitudinalMeters = 1000.00
 let longitudinalMeters = 1000.00
 
 init(time: Date, location2D: CLLocationCoordinate2D){
  self.time = time
  self.location = location2D
 }
 
 var placemark: MKPlacemark { .init(coordinate: location) }
 
 var mapRegion: MKCoordinateRegion {
  .init(center: location,
        latitudinalMeters: latitudinalMeters,
        longitudinalMeters: longitudinalMeters)
 }
 fileprivate var cl: CLLocation { .init(latitude: location.latitude, longitude: location.longitude) }
 
 static func <~~> (_ before: Self, _ now: Self) -> TimeInterval {
  now.time.timeIntervalSinceReferenceDate - before.time.timeIntervalSinceReferenceDate
 }
 
 static func |<->| (_ before: Self, _ now: Self) -> CLLocationDistance {
  now.cl.distance(from: before.cl)
 }
 
 
 //Parsing TimePoint constructor which failably instantiate Time point from JSON array [date, latitude, longitude]
 
 init?(a3: [Any]){
  guard a3.count == 3 else { return nil }
  guard let dateISO8601String = (a3[0] as? String)?.appending("Z") else { return nil }
  guard let dateTime = try? Date(dateISO8601String, strategy: .iso8601) else { return nil }
  guard let latitude = a3[2] as? CLLocationDegrees else { return nil }
  guard let longitude = a3[1] as? CLLocationDegrees else { return nil }
  self.init(time: dateTime, location2D: .init(latitude: latitude, longitude: longitude))
 }

}

@MainActor protocol APIRepresentable  {
 var dataFeedLoader: APIDataFeedRepresentable? { get }
 var timePoint: [TimePoint] { get set }
}


@MainActor final class APIMock: ObservableObject, APIRepresentable {
 
 let dataFeedLoader: APIDataFeedRepresentable? = //APIDataLocalFeedLoader()
  APIDataFeedLoader(resourcePath: "https://dev.skif.pro/coordinates.json")
 
 enum APIError: Error{
  case emptyBuffer
  case parseError
  case noDataFeed
  case unexpectedStreamState
  
 }
 
 enum StreamState{
  
  
  case initial
  case failed(message: String, error: Error)
  case ready
  case tracking
  case timeout
  case stopped
 }
 
 @Published var state: StreamState = .initial
 @Published var mapOpacity = 1.0

 @Published var timePoint: [TimePoint] = []
 
 //@Published var mapRegion: MKCoordinateRegion = .init()
 
 private var dataBuffer: Data?
 
 private lazy var parsedTimePoints: [TimePoint] = {
  guard let dataBuffer else { return [] }
  guard let points = try? JSONSerialization.jsonObject(with: dataBuffer) as? [[Any]] else { return [] }
  return points.compactMap{.init(a3: $0)}
 }()
 
 func fetchData() async {
  guard case .initial = state else {
   state = .failed(message: "Unexpeted Stream State", error: APIError.unexpectedStreamState)
   return
  }
  
  guard let dataFeedLoader else {
   state = .failed(message: "Tracking Data Feed Not Found", error: APIError.noDataFeed)
   return
   
  }
  
  do {
   let dataBuffer = try await dataFeedLoader.dataFeed
   
   if dataBuffer.isEmpty {
    state = .failed(message: "Data buffer is Epmty", error: APIError.emptyBuffer)
    return
   }
   
   self.dataBuffer = dataBuffer
   
   guard !parsedTimePoints.isEmpty else {
    state = .failed(message: "Data buffer is corrupted or has invalid data format", error: APIError.parseError)
    return
   }
   
   state = .ready
   timePoint = Array(parsedTimePoints[0..<1])
   
   
  } catch {
   state = .failed(message: "Data Feed Loader Failed to load tracking data", error: error)
   return
  }
  
 
  
 }
 
 private var timeOutContinuation: CheckedContinuation<Void, Never>?
 
 private var timePointsStream: AsyncStream<TimePoint> {
  
  var count = 1
  
  return AsyncStream<TimePoint> { [ unowned self ] in
   guard count < parsedTimePoints.count else {
    state = .stopped
    timeOutContinuation = nil
    return nil
   }
   
   var newPoint = parsedTimePoints[count]
   let prevPoint = parsedTimePoints[count - 1]
   
   let duration = prevPoint <~~> newPoint
   let distance = prevPoint |<->| newPoint
   
   newPoint.speed = (duration > 0 ? distance / duration : prevPoint.speed) * 3.6
   
   switch state {
     
    case .initial: fallthrough
    case .ready:   fallthrough
    case .failed:  fallthrough
     
    case .stopped: return nil
     
    case .timeout:
     await withCheckedContinuation{ timeOutContinuation = $0 }
     fallthrough
     
    case .tracking:
     try? await Task.sleep(nanoseconds: UInt64(duration * 5_000_000_0))
     count += 1
     return newPoint
   }
   
  }
 }
 
 private func update(_ timePoint: TimePoint) { self.timePoint = [timePoint] }
 
 func startUndatingLocations(){
  switch state {
   case .initial: fallthrough
   case .failed:  return
   case .timeout:
    state = .tracking
    mapOpacity = 1
    timeOutContinuation?.resume()
    timeOutContinuation = nil
   case .tracking:
    state = .timeout
    mapOpacity = 0.5
   case .stopped: fallthrough
   case .ready:
    state = .tracking
    
    Task.detached{ [ unowned self, stream = timePointsStream ] in
     for await timePoint in stream {
      await update(timePoint)
     }
    }
    
  }

  
  
 }

 func stopUndatingLocations(){
  state = .stopped
 }
}
