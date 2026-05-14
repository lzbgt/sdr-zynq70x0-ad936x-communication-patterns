# FieldMesh async FIFO CDC constraints.
#
# The FIFO transfers Gray-coded read/write pointers across clock domains and
# stores payload words in distributed RAM. The first pointer synchronizer stage
# and the RAM write-clock/read-clock boundary are intentionally asynchronous;
# functional correctness is covered by the two-stage synchronizers and empty/full
# protocol in RTL.

set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*rd_gray_reg*}] \
  -to [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*rd_gray_s1_reg*}]
set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*rd_bin_reg*}] \
  -to [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*rd_gray_s1_reg*}]

set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*wr_gray_reg*}] \
  -to [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*wr_gray_m1_reg*}]
set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*wr_bin_reg*}] \
  -to [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*wr_gray_m1_reg*}]

set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*mem_reg*}] \
  -to [get_cells -quiet -hier -filter {NAME =~ *fieldmesh_iq_tx_cdc*m_word_reg_reg*}]

# RF DAC source selection crosses from the sidecar AXI-lite clock into the
# AD9361 DAC clock domain through two flip-flops in fieldmesh_iq_dac_driver.
set_false_path \
  -to [get_pins -quiet -hier -filter {NAME =~ *fieldmesh_iq_dac_driver*select_fieldmesh_meta_reg/D}]

# DAC-domain diagnostic counters cross back into the sidecar AXI-lite clock
# through two-stage diagnostic synchronizers. They are status-only snapshots,
# not control decisions.
set_false_path \
  -to [get_pins -quiet -hier -filter {NAME =~ *fieldmesh_ctrl*rf_dac_sample_count_meta_reg*/D}]
set_false_path \
  -to [get_pins -quiet -hier -filter {NAME =~ *fieldmesh_ctrl*rf_dac_packet_count_meta_reg*/D}]
set_false_path \
  -to [get_pins -quiet -hier -filter {NAME =~ *fieldmesh_ctrl*rf_dac_underflow_count_meta_reg*/D}]
set_false_path \
  -to [get_pins -quiet -hier -filter {NAME =~ *fieldmesh_ctrl*rf_dac_active_meta_reg/D}]
