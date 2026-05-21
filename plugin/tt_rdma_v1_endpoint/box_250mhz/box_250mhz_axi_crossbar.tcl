# SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
# SPDX-License-Identifier: Apache-2.0
#
# No AXI crossbar IP required for tt_link_udp_bridge.
# The box AXI-Lite master is wired directly to tt_link_regs (single slave)
# via the assign statements in box_250mhz_address_map_inst.vh.
