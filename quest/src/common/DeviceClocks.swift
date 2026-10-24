import Foundation

// P403 step 1 (Remington, Oct 22: draw-in slowed late in the session, 'it was doing so well before'; he suspects the
// headset heating up): the GPU and CPU clocks and the hottest thermal zone, read from sysfs once per perf window on the
// headset (Linux too, where the paths exist), so a throttled headset shows as such in the perf line and its captures.
// Empty where nothing is readable. Reads about a dozen tiny files; called every 5 s, not every frame.
enum DeviceClocks {
    private static func read(_ path: String) -> String? {
        guard let d = FileManager.default.contents(atPath: path), let s = String(data: d, encoding: .utf8) else { return nil }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func num(_ path: String) -> Double? { read(path).flatMap { Double($0.split(separator: " ").first ?? "") } }

    static func line() -> String {
        var parts: [String] = []
        // Adreno: kgsl clocks in Hz (Quest 3: 680 MHz at the top).
        if let g = num("/sys/class/kgsl/kgsl-3d0/gpuclk") ?? num("/sys/class/kgsl/kgsl-3d0/devfreq/cur_freq") {
            var s = "gpu \(Int(g / 1e6)) MHz"
            if let mx = num("/sys/class/kgsl/kgsl-3d0/max_gpuclk") ?? num("/sys/class/kgsl/kgsl-3d0/devfreq/max_freq"), mx > 0 { s += " of \(Int(mx / 1e6))" }
            if let busy = read("/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage") { s += ", busy \(busy)" }
            parts.append(s)
        }
        // CPU: scaling_cur_freq in kHz per core; the range across the cores that answer.
        var cpu: [Double] = []
        for i in 0..<12 { if let f = num("/sys/devices/system/cpu/cpu\(i)/cpufreq/scaling_cur_freq") { cpu.append(f / 1e3) } }
        if let lo = cpu.min(), let hi = cpu.max() { parts.append("cpu \(Int(lo))-\(Int(hi)) MHz") }
        // Thermal: the hottest zone and its name (millidegrees on Android, some zones answer in degrees).
        var hot: (Double, String)? = nil
        for i in 0..<40 {
            guard let t = num("/sys/class/thermal/thermal_zone\(i)/temp") else { if i > 8 { break } else { continue } }
            let c = t > 1000 ? t / 1000 : t
            if c > 0 && c < 150 && (hot == nil || c > hot!.0) { hot = (c, read("/sys/class/thermal/thermal_zone\(i)/type") ?? "zone\(i)") }
        }
        if let h = hot { parts.append(String(format: "hottest %@ %.0f C", h.1, h.0)) }
        return parts.joined(separator: ", ")
    }
}
