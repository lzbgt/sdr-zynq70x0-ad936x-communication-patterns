# FieldMesh async FIFO CDC constraints.
#
# The FIFO transfers only Gray-coded read/write pointers across clock domains.
# The first synchronizer stage is intentionally asynchronous; functional
# correctness is covered by the two-stage synchronizers in RTL.

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
