set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here .. ..]]
set bit_file [file join $root vivado artifacts AES_GCM_RX.bit]
set ps_init [file join $root vivado artifacts ps7_init.tcl]
set fsbl [file join $here zynq_fsbl.elf]
set uboot [file join $here u-boot.elf]
set system_dtb [file join $here system.dtb]
set image_ub [file join $here image.ub]

foreach required [list $bit_file $ps_init $fsbl $uboot $system_dtb $image_ub] {
    if {![file exists $required]} {error "Missing JTAG boot file: $required"}
}

if {[info exists ::env(AES_GCM_RX_CABLE_SERIAL)] &&
    [string trim $::env(AES_GCM_RX_CABLE_SERIAL)] ne ""} {
    set cable_serial [string trim $::env(AES_GCM_RX_CABLE_SERIAL)]
} elseif {[info exists ::env(AES_GCM_JTAG_CABLE_SERIAL)] &&
          [string trim $::env(AES_GCM_JTAG_CABLE_SERIAL)] ne ""} {
    set cable_serial [string trim $::env(AES_GCM_JTAG_CABLE_SERIAL)]
} else {
    set cable_serial "210351BE7D5BA"
}
puts "JTAG_CABLE_SERIAL=$cable_serial"

connect
targets -set -nocase -filter [format {name =~ "*APU*" && jtag_cable_serial == "%s"} $cable_serial]
rst -system -stop
after 1000
targets -set -nocase -filter [format {name =~ "*xc7z020*" && jtag_cable_serial == "%s"} $cable_serial]
fpga -file $bit_file
source $ps_init
targets -set -nocase -filter [format {name =~ "*Cortex-A9*#0" && jtag_cable_serial == "%s"} $cable_serial]
ps7_init
ps7_post_config
dow $fsbl
con
after 3000
stop
rst -processor -clear-registers
after 100
dow $uboot
dow -data $system_dtb 0x00100000
dow -data $image_ub 0x10000000
puts "JTAG_RAM_BOOT_READY=1"
con
after 400
stop
after 1000
con
disconnect
exit
