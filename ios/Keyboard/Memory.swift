#if DEBUG
import Darwin

enum Memory {
    /// "current/peak MB" of this process's phys_footprint, the number the system's jetsam limit counts.
    static var label: String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return "? MB" }
        let peak = info.ledger_phys_footprint_peak > 0 ? UInt64(info.ledger_phys_footprint_peak) : info.phys_footprint
        return "\(info.phys_footprint / 1_048_576)/\(peak / 1_048_576) MB"
    }
}
#endif
