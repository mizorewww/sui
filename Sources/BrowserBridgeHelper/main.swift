import Darwin
import Foundation

let port: UInt16 = 47_831
let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
guard socketFileDescriptor >= 0 else { exit(1) }

var address = sockaddr_in()
address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
address.sin_family = sa_family_t(AF_INET)
address.sin_port = port.bigEndian
address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(socketFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
}
guard connected == 0 else { close(socketFileDescriptor); exit(2) }

func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
    data.withUnsafeBytes { rawBuffer in
        guard var pointer = rawBuffer.baseAddress else { return true }
        var remaining = rawBuffer.count
        while remaining > 0 {
            let count = Darwin.write(descriptor, pointer, remaining)
            if count <= 0 { return false }
            pointer = pointer.advanced(by: count)
            remaining -= count
        }
        return true
    }
}

func readExactly(_ count: Int, from handle: FileHandle) -> Data? {
    var result = Data()
    while result.count < count {
        guard let part = try? handle.read(upToCount: count - result.count), !part.isEmpty else { return nil }
        result.append(part)
    }
    return result
}

DispatchQueue.global(qos: .userInitiated).async {
    let input = FileHandle.standardInput
    while let header = readExactly(4, from: input) {
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        guard length > 0, length < 1_048_576, let payload = readExactly(Int(length), from: input) else { break }
        var line = payload
        line.append(0x0A)
        if !writeAll(line, to: socketFileDescriptor) { break }
    }
    shutdown(socketFileDescriptor, SHUT_RDWR)
}

var buffer = Data()
var chunk = [UInt8](repeating: 0, count: 65_536)
while true {
    let received = recv(socketFileDescriptor, &chunk, chunk.count, 0)
    guard received > 0 else { break }
    buffer.append(chunk, count: received)
    while let newline = buffer.firstIndex(of: 0x0A) {
        let payload = Data(buffer.prefix(upTo: newline))
        buffer.removeSubrange(...newline)
        var length = UInt32(payload.count).littleEndian
        let header = Data(bytes: &length, count: 4)
        guard writeAll(header, to: STDOUT_FILENO), writeAll(payload, to: STDOUT_FILENO) else { exit(3) }
    }
}
close(socketFileDescriptor)
