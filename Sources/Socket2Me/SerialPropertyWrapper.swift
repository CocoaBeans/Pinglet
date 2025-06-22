//
// Created by Kevin Ross on 5/17/24.
//

import Foundation

@propertyWrapper
public class SerialAccess<Value: Sendable> {
    
    private var defaultValue: Value
    private let queue: DispatchQueue

    public init(defaultValue: Value,
                queue: DispatchQueue = DispatchQueue(label: "com.serialaccess.queue", qos: .`default`)) {
        self.defaultValue = defaultValue
        self.queue = queue
    }

    public var wrappedValue: Value {
        get {
            queue.sync { defaultValue }
        }
        set {
            queue.async(flags: [.barrier, .assignCurrentContext]) { [self] in
                defaultValue = newValue
            }
        }
    }
}
