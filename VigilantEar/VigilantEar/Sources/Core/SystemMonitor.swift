import Foundation
import SwiftUI
import Combine

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()
    
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsageMB: Double = 0.0
    
    private var timer: Timer?
    
    private init() {}
    
    func start() {
        timer?.invalidate() // Prevent double-firing
        
        // Poll the CPU twice a second
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            // Push the heavy kernel math to a background thread
            Task.detached(priority: .background) {
                let metrics = SystemMonitor.fetchMetrics()
                // Safely hop back to the main thread to update the UI
                await self?.updateUI(cpu: metrics.cpu, mem: metrics.mem)
            }
        }
    }
    
    private func updateUI(cpu: Double, mem: Double) {
        self.cpuUsage = cpu
        self.memoryUsageMB = mem
    }
    
    // THE FIX: A much safer way to bridge C-structs into Swift memory
    nonisolated private static func fetchMetrics() -> (cpu: Double, mem: Double) {
        var totalCPU: Double = 0.0
        var memoryMB: Double = 0.0
        
        // --- 1. GET CPU USAGE ---
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kr = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if kr == KERN_SUCCESS, let threadList = threadList {
            for j in 0..<Int(threadCount) {
                // Instantiate the struct natively in Swift
                var thinfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                
                // Pass the struct pointer into the C function
                let infoResult = withUnsafeMutablePointer(to: &thinfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) { ptr in
                        thread_info(threadList[j], thread_flavor_t(THREAD_BASIC_INFO), ptr, &threadInfoCount)
                    }
                }
                
                // Access properties directly without `.pointee`!
                if infoResult == KERN_SUCCESS {
                    let isIdle = thinfo.flags & TH_FLAGS_IDLE != 0
                    if !isIdle {
                        totalCPU += (Double(thinfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                    }
                }
            }
            // Deallocate to prevent memory leaks
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }
        
        // --- 2. GET MEMORY USAGE ---
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            memoryMB = Double(info.resident_size) / (1024 * 1024)
        }
        
        return (totalCPU, memoryMB)
    }
}
