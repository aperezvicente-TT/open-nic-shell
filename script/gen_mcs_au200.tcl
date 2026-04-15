set build_dir  "/home/alex/mpi-shfs/fpga/open-nic-shell/build/au200_2cmac_2pf/open_nic_shell"
set top        "open_nic_shell"
set impl_run   "impl_4"

set bit_file "${build_dir}/${top}.runs/${impl_run}/${top}.bit"
set mcs_file "[file rootname $bit_file].mcs"

if {![file exists $bit_file]} {
    puts "ERROR: Bitstream not found at $bit_file"
    exit 1
}

puts "Generating MCS from: $bit_file"
puts "Output MCS:          $mcs_file"

write_cfgmem \
    -format    mcs      \
    -size      128      \
    -interface SPIx4    \
    -loadbit   "up 0x01002000 $bit_file" \
    -file      "$mcs_file" \
    -force

puts "Done: $mcs_file"
exit
