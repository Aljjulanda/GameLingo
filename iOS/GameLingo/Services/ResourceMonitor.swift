import Foundation
import Darwin

struct ResourceMonitor {
    private var lastTime = 0.0, lastCPU = 0.0
    mutating func sample() -> (cpu: Double, residentBytes: UInt64) {
        var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
        let cpu = Double(usage.ru_utime.tv_sec+usage.ru_stime.tv_sec)+Double(usage.ru_utime.tv_usec+usage.ru_stime.tv_usec)/1_000_000
        let now = ProcessInfo.processInfo.systemUptime
        let percent = lastTime > 0 ? max(0,(cpu-lastCPU)/max(0.001,now-lastTime)*100) : 0
        lastCPU = cpu; lastTime = now
        return (percent,Self.residentBytes())
    }
    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size/MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count) }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }
}
