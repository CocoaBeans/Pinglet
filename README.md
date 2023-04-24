# Pinglet

A little ping package written in modern swift.

This project is based on SwiftyPing: https://github.com/samiyr/SwiftyPing

Added features:
- Background pings: all network activity can be offloaded to a background queue
- Includes support for pinging when the app is inactive on iOS
- Conforms to ObservableObject and publishers for Combine pipelines 

### Usage
```swift

// Ping indefinitely
let pinglet = try? Pinglet(host: "1.1.1.1", configuration: PingConfiguration(interval: 0.5, with: 5), queue: DispatchQueue.global())
pinglet?.responseObserver = { (response) in
    let duration = response.duration
    print(duration)
}
try? pinglet?.startPinging()

// Ping once
let once = try? Pinglet(host: "1.1.1.1", configuration: PingConfiguration(interval: 0.5, with: 5), queue: DispatchQueue.global())
once?.responseObserver = { (response) in
    let duration = response.duration
    print(duration)
}
once?.targetCount = 1
try? once?.startPinging()

// Combine
let pinglet = try? Pinglet(host: "1.1.1.1", configuration: PingConfiguration(interval: 0.5, with: 5), queue: DispatchQueue.global())
pinglet.$responses
       .sink { (pings: [PingResponse]) in
           print("ping count: \(pings.count)")
       }
       .store(in: &subscriptions)

```
### Installation
Swift Package Manager:

```swift
.Package(url: "https://github.com/CocoaBeans/Pinglet.git", branch: "main")
```

### Future development and contributions
I made this project based on what I need for PingPoint, so I probably won't be adding any features unless I really need them. I will maintain it (meaning bug fixes and support for new Swift versions) for some time at least. However, you can submit a pull request and I'll take a look. Please try to keep the overall coding style.

### Original Caveat Emptor
This is low-level code, basically C code translated to Swift. This means that there are unsafe casts from raw bytes to Swift structs, for which Swift's usual type safety checks no longer apply. These can fail ungracefully (throwing an exception), and may even be used as an exploit (I'm not a security researcher and thus don't have the expertise to say for sure), so use with caution, especially if pinging untrusted hosts.

Also, while I think that the API is now stable, I don't make any guarantees – some new version might break old stuff.

### License
Licensed under MIT.
