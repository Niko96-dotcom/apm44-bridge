import CoreAudio
import Foundation

final class HotplugMonitor {
    private var listenerProc: AudioObjectPropertyListenerProc?
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.niko.apm44.hotplug", qos: .utility)
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
    }

    func start() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let proc: AudioObjectPropertyListenerProc = { _, _, _, clientData in
            guard let clientData else { return noErr }
            let monitor = Unmanaged<HotplugMonitor>.fromOpaque(clientData).takeUnretainedValue()
            monitor.scheduleDebounced()
            return noErr
        }
        listenerProc = proc
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            proc,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if status != noErr {
            NSLog("HotplugMonitor: failed to register listener (%d)", status)
        }
    }

    func stop() {
        guard let proc = listenerProc else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            proc,
            Unmanaged.passUnretained(self).toOpaque()
        )
        listenerProc = nil
        // Serialize the cancel on `queue` so it can't race a scheduleDebounced
        // block still in flight from the Core Audio listener thread.
        queue.sync {
            debounceWork?.cancel()
            debounceWork = nil
        }
    }

    deinit {
        stop()
    }

    private func scheduleDebounced() {
        // The Core Audio property listener fires on an arbitrary thread; route
        // every read/write of `debounceWork` through the serial `queue` so the
        // field is only ever touched from one place.
        queue.async { [weak self] in
            guard let self else { return }
            self.debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onFire()
            }
            self.debounceWork = work
            self.queue.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }
}
