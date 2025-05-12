//
// Created by Kevin Ross on 5/17/24.
//

import Foundation

@propertyWrapper
public struct SerialAccess<Value> {

    public var queue: DispatchQueue
    public var defaultValue: Value

    init(queue: DispatchQueue = DispatchQueue(label: "SerialAccess", qos: .default), defaultValue: Value) {
        self.queue = queue
        self.defaultValue = defaultValue
    }

    public var wrappedValue: Value {
        get {
            queue.sync { defaultValue }
        }
        set {
            queue.sync { defaultValue = newValue }
        }
    }
}
