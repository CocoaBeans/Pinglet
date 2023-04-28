/*
  Pinglet
  This project is based on SwiftyPing: https://github.com/samiyr/SwiftyPing
  Copyright (c) 2023 Kevin Ross
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
 */

import Foundation

/// Describes all possible errors thrown within `Pinglet`
public enum PingError: Error {
    // Response errors

    /// The response took longer to arrive than `configuration.timeoutInterval`.
    case responseTimeout

    // Response validation errors

    /// The response length was too short.
    case invalidLength(received: Int)
    /// The received checksum doesn't match the calculated one.
    case checksumMismatch(received: UInt16, calculated: UInt16)
    /// Response `type` was invalid.
    case invalidType(received: ICMPType.RawValue)
    /// Response `code` was invalid.
    case invalidCode(received: UInt8)
    /// Response `identifier` doesn't match what was sent.
    case identifierMismatch(received: UInt16, expected: UInt16)
    /// Response `sequenceNumber` doesn't match.
    case invalidSequenceIndex(received: UInt16, expected: UInt16)

    // Host resolve errors
    /// Unknown error occured within host lookup.
    case unknownHostError
    /// Address lookup failed.
    case addressLookupError
    /// Host was not found.
    case hostNotFound
    /// Address data could not be converted to `sockaddr`.
    case addressMemoryError

    // Request errors
    /// An error occurred while sending the request.
    case requestError
    /// The request send timed out. Note that this is not "the" timeout,
    /// that would be `responseTimeout`. This timeout means that
    /// the ping request wasn't even sent within the timeout interval.
    case requestTimeout

    // Internal errors
    /// Checksum is out-of-bounds for `UInt16` in `computeCheckSum`. This shouldn't occur, but if it does, this error ensures that the app won't crash.
    case checksumOutOfBounds
    /// Unexpected payload length.
    case unexpectedPayloadLength
    /// Unspecified package creation error.
    case packageCreationFailed
    /// For some reason, the socket is `nil`. This shouldn't ever happen, but just in case...
    case socketNil
    /// The ICMP header offset couldn't be calculated.
    case invalidHeaderOffset
    /// Failed to change socket options, in particular SIGPIPE.
    case socketOptionsSetError(err: Int32)

    case generic(Error)
}
