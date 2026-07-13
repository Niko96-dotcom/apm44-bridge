import CoreAudio
import Foundation

final class HotplugMonitor {
    private var listenerProc: AudioObjectPropertyListenerProc?
    private var selectedDeviceId = AudioDeviceID(kAudioObjectUnknown)
    private var selectedAddresses: [AudioObjectPropertyAddress] = []
    private var selectedUid: String?
    private var selectionObserver: NSObjectProtocol?
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.niko.apm44.hotplug", qos: .utility)
    private let onFire: () -> Void

    init(selectedUid: String? = nil, onFire: @escaping () -> Void) {
        self.selectedUid = selectedUid
        self.onFire = onFire
    }

    func start() {
        guard listenerProc == nil else { return }
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
        selectionObserver = NotificationCenter.default.addObserver(
            forName: .apm44OutputDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let uid = note.userInfo?["uid"] as? String
            self?.updateSelectedDevice(uid: uid?.isEmpty == false ? uid : nil)
        }
        updateSelectedDevice(uid: selectedUid)
    }

    func stop() {
        guard let proc = listenerProc else { return }
        removeSelectedListeners(proc: proc)
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
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
            self.selectionObserver = nil
        }
        // Serialize the cancel on `queue` so it can't race a scheduleDebounced
        // block still in flight from the Core Audio listener thread.
        queue.sync {
            debounceWork?.cancel()
            debounceWork = nil
        }
    }

    func updateSelectedDevice(uid: String?) {
        selectedUid = uid
        guard listenerProc != nil else { return }
        rebindSelectedDeviceListeners()
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
                DispatchQueue.main.async {
                    guard let self, self.listenerProc != nil else { return }
                    self.rebindSelectedDeviceListeners()
                    self.onFire()
                }
            }
            self.debounceWork = work
            self.queue.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    private func rebindSelectedDeviceListeners() {
        guard let proc = listenerProc else { return }
        removeSelectedListeners(proc: proc)
        guard let selectedUid,
              let deviceId = findDeviceId(uid: selectedUid) else { return }

        selectedDeviceId = deviceId
        let candidates = [
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamFormat,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyBufferFrameSize,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
        ]
        for candidate in candidates {
            var address = candidate
            if AudioObjectAddPropertyListener(
                deviceId,
                &address,
                proc,
                Unmanaged.passUnretained(self).toOpaque()
            ) == noErr {
                selectedAddresses.append(candidate)
            }
        }
    }

    private func removeSelectedListeners(proc: AudioObjectPropertyListenerProc) {
        guard selectedDeviceId != kAudioObjectUnknown else {
            selectedAddresses.removeAll()
            return
        }
        for storedAddress in selectedAddresses {
            var address = storedAddress
            AudioObjectRemovePropertyListener(
                selectedDeviceId,
                &address,
                proc,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        selectedAddresses.removeAll()
        selectedDeviceId = AudioDeviceID(kAudioObjectUnknown)
    }

    private func findDeviceId(uid wantedUid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &ids
        ) == noErr else { return nil }

        for id in ids where deviceUid(id) == wantedUid {
            return id
        }
        return nil
    }

    private func deviceUid(_ deviceId: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(
            deviceId,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr, let value else { return nil }
        return value as String
    }
}
