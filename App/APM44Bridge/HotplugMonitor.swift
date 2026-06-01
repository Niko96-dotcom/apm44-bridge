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
        debounceWork?.cancel()
    }

    deinit {
        stop()
    }

    private func scheduleDebounced() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onFire()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
}
