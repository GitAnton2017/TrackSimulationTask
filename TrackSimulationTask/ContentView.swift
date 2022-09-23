
import SwiftUI
import MapKit

struct ContentView: View {
 
 @StateObject var api = APIMock()
 @State var showErrorMessage = false
 @State var mapRegion = MKCoordinateRegion()
 @State var showLoadProgress = true
 
 
 @Sendable func fetchData() async {
  await api.fetchData()
  
  
  if case .failed(_, _) = api.state {
   showErrorMessage = true
   return
  }
  
  mapRegion = api.timePoint[0].mapRegion
  showLoadProgress = false
 }
 
 func refetchData(){
  showErrorMessage = false
  Task {
   api.state = .initial
   await api.fetchData()
   if case .failed(_, _) = api.state {
    showErrorMessage = true
   }
  }
 }
 
 func dismissAction(){
  showErrorMessage = false
 }
 

    var body: some View {
     
        ZStack {
         Map(coordinateRegion: $mapRegion, annotationItems: api.timePoint) {
          MapAnnotation(coordinate: $0.location){
           
           if case .timeout = api.state {
            VStack{
             Text("\(Int(api.timePoint[0].speed.rounded()))")
              .frame(width: 200)
              .fontWeight(.bold)
              .font(.largeTitle)
              .overlay {
               Circle()
                .stroke(.red, lineWidth: 16)
                .frame(width: 120, height: 120)
              }
             Text("km/h").frame(width: 200)
            }
           } else {
            Circle()
             .fill(.red)
             .frame(width: 30, height: 30)

           }
          }
          
         }.opacity(api.mapOpacity)
   
         if showLoadProgress{
          ProgressView("Loading...")
           .scaleEffect(.init(width: 1.25, height: 1.25))
         }
        }.task(fetchData)
         .onReceive(api.$timePoint.dropFirst()) { mapRegion = $0[0].mapRegion }
         .onTapGesture { api.startUndatingLocations() }
         .alert("Tracking Data API Error!",
                isPresented: $showErrorMessage,
                presenting: api.state,
                actions: { _ in
                 Button("Dismiss", action: dismissAction)
                 Button("Retry", action: refetchData)
                }, message: { apiState in
                 if case let.failed(message, _) = apiState {
                  Text(message)
                 }
                })
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
