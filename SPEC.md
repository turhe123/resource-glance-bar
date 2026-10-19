# ResourceGlanceBar — specification

**Tagline:** CPU load, memory pressure and disk space as tiny live meters in the menu bar with a detailed dropdown.

**Category:** System Monitoring

**Inspired by (paid):** iStat Menus ($11.99 one-time)

**Frameworks:** SwiftUI, AppKit, Charts, Foundation, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

The paid app. iStat Menus by Bjango is the best known menu bar system monitor and a perennial pick in roundups of essential Mac utilities, listed around 11.99 dollars one-time in recent guides. People pay for its tidy CPU, memory and disk readouts, which are more glanceable than Activity Monitor. Our clean-room free version deliberately skips sensors and fans, which other ideas in this catalog cover, and focuses on three resources.

Feature set. Up to three menu bar items, each independently enabled: CPU shows a tiny bar graph of the last 20 seconds or a percentage, Memory shows used percentage with a color that goes green, yellow and red following memory pressure, and Disk shows free space on the startup volume. Clicking an item opens a popover. CPU view: total user and system load, per-core bars, load average, and a list of the five busiest processes by CPU with a small history chart. Memory view: used, wired, compressed, cached and free amounts, swap used, and the five processes using the most memory. Disk view: capacity, used and free, plus read and write throughput as a chart. A Quit Process button next to each listed process asks for confirmation then sends a terminate request.

UI spec. Several MenuBarExtra scenes, one per resource, created conditionally from settings toggles. Each popover is window style and 300 points wide. Settings fields: which items to show, update interval of 1, 2 or 5 seconds, graph or number display, warning thresholds for CPU and memory and disk, color theme, and launch at login. States: while the first sample is pending, show dashes. If a process list cannot be read, show a short unavailable note instead of an empty list.

Technical approach. CPU load comes from host_processor_info which returns per-core tick counters, and deltas between samples produce the percentages. Memory uses host_statistics64 with HOST_VM_INFO64 and the page size from vm_kernel_page_size, and the memory pressure level from the sysctl named kern.memorystatus_vm_pressure_level via sysctlbyname. Swap usage comes from sysctl vm.swapusage. Disk capacity uses URLResourceValues volumeAvailableCapacityForImportantUsage and volumeTotalCapacity. Disk throughput is estimated from IOKit IOBlockStorageDriver statistics. Process lists use the proc_listpids and proc_pidinfo functions from libproc, which ship with the system, with CPU time deltas computed per pid. Charts are rendered with Swift Charts from ring buffers. Everything runs on a single background timer and publishes to the main actor. No special permissions are needed for these calls for the user's own processes. Settings use AppStorage and SMAppService handles launch at login.

Edge cases. Timer coalescing while the Mac sleeps can create a large time delta, so discard samples whose interval is far longer than expected. Processes owned by other users may not be readable, so skip them silently. Never offer to quit critical system processes: disable the button for processes owned by root. Keep CPU use of the app itself under one percent by slowing updates to five seconds when no popover is open. Target is around 600 lines.
