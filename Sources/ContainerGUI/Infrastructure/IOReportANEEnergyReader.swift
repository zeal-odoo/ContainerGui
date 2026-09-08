import CoreFoundation
import Darwin
import Foundation

/// Passive, host-wide estimated energy. IOReport is private API; missing support fails closed.
final class IOReportANEEnergyReader: ANEEnergyReading, @unchecked Sendable {
    private let lock = NSLock()
    private var session: Session?

    func read() throws -> [ANEEnergyChannel] {
        try lock.withLock {
            if session == nil { session = try Session() }
            guard let session else { throw ANEPowerFailure.unsupported }
            return try session.read()
        }
    }

    private final class Library {
        let handle: UnsafeMutableRawPointer

        init() throws {
            guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL) else {
                throw ANEPowerFailure.unsupported
            }
            self.handle = handle
        }

        func symbol<T>(_ name: String, as type: T.Type) throws -> T {
            guard let address = dlsym(handle, name) else { throw ANEPowerFailure.unsupported }
            return unsafeBitCast(address, to: type)
        }

        deinit { dlclose(handle) }
    }

    private final class Session {
        private typealias CopyChannels = @convention(c) (UInt64, UInt64) -> Unmanaged<CFDictionary>?
        private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
        private typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFDictionary>?>, UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
        private typealias CreateSamples = @convention(c) (CFTypeRef, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
        private typealias IntegerValue = @convention(c) (CFDictionary, Int32) -> Int64
        private typealias ChannelFormat = @convention(c) (CFDictionary) -> Int32

        private let library: Library
        private let group: ChannelString
        private let name: ChannelString
        private let unit: ChannelString
        private let createSamples: CreateSamples
        private let integerValue: IntegerValue
        private let format: ChannelFormat
        private var subscription: CFTypeRef?
        private var actualChannels: CFDictionary?

        init() throws {
            let library = try Library()
            self.library = library
            let copyChannels = try library.symbol("IOReportCopyAllChannels", as: CopyChannels.self)
            let subscribe = try library.symbol("IOReportCreateSubscription", as: CreateSubscription.self)
            group = try library.symbol("IOReportChannelGetGroup", as: ChannelString.self)
            name = try library.symbol("IOReportChannelGetChannelName", as: ChannelString.self)
            unit = try library.symbol("IOReportChannelGetUnitLabel", as: ChannelString.self)
            createSamples = try library.symbol("IOReportCreateSamples", as: CreateSamples.self)
            integerValue = try library.symbol("IOReportSimpleGetIntegerValue", as: IntegerValue.self)
            format = try library.symbol("IOReportChannelGetFormat", as: ChannelFormat.self)
            guard let all = copyChannels(0, 0)?.takeRetainedValue() else { throw ANEPowerFailure.unsupported }
            let selected = try dictionaries(in: all).filter { channel in
                string(group, channel) == "Energy Model" && string(name, channel).map(ANEEnergyChannel.isANEName) == true
            }
            let metadata = try selected.map { channel in
                guard let channelName = string(name, channel), let channelUnit = string(unit, channel) else {
                    throw ANEPowerFailure.unsupported
                }
                return ANEEnergyChannel(name: channelName, unit: channelUnit, value: 0)
            }
            try ANEEnergyChannel.validate(metadata)
            guard let channels = (all as NSDictionary).mutableCopy() as? NSMutableDictionary else {
                throw ANEPowerFailure.readFailed
            }
            channels["IOReportChannels"] = selected
            var actual: Unmanaged<CFDictionary>?
            let created = subscribe(nil, channels as CFMutableDictionary, &actual, 0, nil)
            // Both the subscription and the out-parameter are create-owned, including failure paths.
            actualChannels = actual?.takeRetainedValue()
            subscription = created?.takeRetainedValue()
            guard subscription != nil, actualChannels != nil else { throw ANEPowerFailure.readFailed }
        }

        func read() throws -> [ANEEnergyChannel] {
            guard let subscription, let actualChannels,
                  let samples = createSamples(subscription, actualChannels, nil)?.takeRetainedValue() else {
                throw ANEPowerFailure.readFailed
            }
            let result = try dictionaries(in: samples).map { channel in
                guard string(group, channel) == "Energy Model",
                      let channelName = string(name, channel), ANEEnergyChannel.isANEName(channelName) else {
                    throw ANEPowerFailure.invalidSample
                }
                guard let channelUnit = string(unit, channel) else { throw ANEPowerFailure.unsupported }
                // Only the scalar integer format is energy data we understand. The IOReport
                // invalid-value sentinel is Int64.min and is rejected by channel validation.
                // ABI constants: apple-oss-distributions/xnu, iokit/IOKit/IOReportTypes.h.
                guard format(channel) == 1 else { throw ANEPowerFailure.unsupported }
                return ANEEnergyChannel(name: channelName, unit: channelUnit, value: integerValue(channel, 0))
            }
            try ANEEnergyChannel.validate(result)
            return result.sorted { $0.name < $1.name }
        }

        private func dictionaries(in dictionary: CFDictionary) throws -> [CFDictionary] {
            guard let channels = (dictionary as NSDictionary)["IOReportChannels"] as? [NSDictionary] else {
                throw ANEPowerFailure.readFailed
            }
            return channels.map { $0 as CFDictionary }
        }

        private func string(_ accessor: ChannelString, _ channel: CFDictionary) -> String? {
            accessor(channel)?.takeUnretainedValue() as String?
        }

        deinit {
            // Release CF objects while their library's code is still loaded.
            subscription = nil
            actualChannels = nil
            withExtendedLifetime(library) {}
        }
    }
}
