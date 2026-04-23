// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table implementation internals

#include "Vtop__pch.h"
#include "Vtop.h"
#include "Vtop___024root.h"

// FUNCTIONS
Vtop__Syms::~Vtop__Syms()
{

    // Tear down scope hierarchy
    __Vhier.remove(0, &__Vscope_tb_top);
    __Vhier.remove(&__Vscope_tb_top, &__Vscope_tb_top__decap);
    __Vhier.remove(&__Vscope_tb_top, &__Vscope_tb_top__encap);

}

Vtop__Syms::Vtop__Syms(VerilatedContext* contextp, const char* namep, Vtop* modelp)
    : VerilatedSyms{contextp}
    // Setup internal state of the Syms class
    , __Vm_modelp{modelp}
    // Setup module instances
    , TOP{this, namep}
{
        // Check resources
        Verilated::stackCheck(181);
    // Configure time unit / time precision
    _vm_contextp__->timeunit(-9);
    _vm_contextp__->timeprecision(-12);
    // Setup each module's pointers to their submodules
    // Setup each module's pointer back to symbol table (for public functions)
    TOP.__Vconfigure(true);
    // Setup scopes
    __Vscope_TOP.configure(this, name(), "TOP", "TOP", 0, VerilatedScope::SCOPE_OTHER);
    __Vscope_tb_top.configure(this, name(), "tb_top", "tb_top", -9, VerilatedScope::SCOPE_MODULE);
    __Vscope_tb_top__decap.configure(this, name(), "tb_top.decap", "decap", -9, VerilatedScope::SCOPE_MODULE);
    __Vscope_tb_top__encap.configure(this, name(), "tb_top.encap", "encap", -9, VerilatedScope::SCOPE_MODULE);

    // Set up scope hierarchy
    __Vhier.add(0, &__Vscope_tb_top);
    __Vhier.add(&__Vscope_tb_top, &__Vscope_tb_top__decap);
    __Vhier.add(&__Vscope_tb_top, &__Vscope_tb_top__encap);

    // Setup export functions
    for (int __Vfinal = 0; __Vfinal < 2; ++__Vfinal) {
        __Vscope_TOP.varInsert(__Vfinal,"cfg_local_ip", &(TOP.cfg_local_ip), false, VLVT_UINT32,VLVD_IN|VLVF_PUB_RW,1 ,31,0);
        __Vscope_TOP.varInsert(__Vfinal,"cfg_local_mac", &(TOP.cfg_local_mac), false, VLVT_UINT64,VLVD_IN|VLVF_PUB_RW,1 ,47,0);
        __Vscope_TOP.varInsert(__Vfinal,"cfg_mtu", &(TOP.cfg_mtu), false, VLVT_UINT16,VLVD_IN|VLVF_PUB_RW,1 ,15,0);
        __Vscope_TOP.varInsert(__Vfinal,"cfg_peer_ip", &(TOP.cfg_peer_ip), false, VLVT_UINT32,VLVD_IN|VLVF_PUB_RW,1 ,31,0);
        __Vscope_TOP.varInsert(__Vfinal,"cfg_peer_mac", &(TOP.cfg_peer_mac), false, VLVT_UINT64,VLVD_IN|VLVF_PUB_RW,1 ,47,0);
        __Vscope_TOP.varInsert(__Vfinal,"cfg_udp_port", &(TOP.cfg_udp_port), false, VLVT_UINT16,VLVD_IN|VLVF_PUB_RW,1 ,15,0);
        __Vscope_TOP.varInsert(__Vfinal,"clk", &(TOP.clk), false, VLVT_UINT8,VLVD_IN|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_m_tdata", &(TOP.dec_m_tdata), false, VLVT_WDATA,VLVD_OUT|VLVF_PUB_RW,1 ,511,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_m_tkeep", &(TOP.dec_m_tkeep), false, VLVT_UINT64,VLVD_OUT|VLVF_PUB_RW,1 ,63,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_m_tlast", &(TOP.dec_m_tlast), false, VLVT_UINT8,VLVD_OUT|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_m_tready", &(TOP.dec_m_tready), false, VLVT_UINT8,VLVD_IN|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_m_tuser", &(TOP.dec_m_tuser), false, VLVT_UINT16,VLVD_OUT|VLVF_PUB_RW,1 ,15,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_m_tvalid", &(TOP.dec_m_tvalid), false, VLVT_UINT8,VLVD_OUT|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_s_tdata", &(TOP.dec_s_tdata), false, VLVT_WDATA,VLVD_IN|VLVF_PUB_RW,1 ,511,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_s_tkeep", &(TOP.dec_s_tkeep), false, VLVT_UINT64,VLVD_IN|VLVF_PUB_RW,1 ,63,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_s_tlast", &(TOP.dec_s_tlast), false, VLVT_UINT8,VLVD_IN|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_s_tready", &(TOP.dec_s_tready), false, VLVT_UINT8,VLVD_OUT|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_s_tuser", &(TOP.dec_s_tuser), false, VLVT_UINT16,VLVD_IN|VLVF_PUB_RW,1 ,15,0);
        __Vscope_TOP.varInsert(__Vfinal,"dec_s_tvalid", &(TOP.dec_s_tvalid), false, VLVT_UINT8,VLVD_IN|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_m_tdata", &(TOP.enc_m_tdata), false, VLVT_WDATA,VLVD_OUT|VLVF_PUB_RW,1 ,511,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_m_tkeep", &(TOP.enc_m_tkeep), false, VLVT_UINT64,VLVD_OUT|VLVF_PUB_RW,1 ,63,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_m_tlast", &(TOP.enc_m_tlast), false, VLVT_UINT8,VLVD_OUT|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_m_tready", &(TOP.enc_m_tready), false, VLVT_UINT8,VLVD_IN|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_m_tuser", &(TOP.enc_m_tuser), false, VLVT_UINT16,VLVD_OUT|VLVF_PUB_RW,1 ,15,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_m_tvalid", &(TOP.enc_m_tvalid), false, VLVT_UINT8,VLVD_OUT|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_s_tdata", &(TOP.enc_s_tdata), false, VLVT_WDATA,VLVD_IN|VLVF_PUB_RW,1 ,511,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_s_tkeep", &(TOP.enc_s_tkeep), false, VLVT_UINT64,VLVD_IN|VLVF_PUB_RW,1 ,63,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_s_tlast", &(TOP.enc_s_tlast), false, VLVT_UINT8,VLVD_IN|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_s_tready", &(TOP.enc_s_tready), false, VLVT_UINT8,VLVD_OUT|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_s_tuser", &(TOP.enc_s_tuser), false, VLVT_UINT16,VLVD_IN|VLVF_PUB_RW,1 ,15,0);
        __Vscope_TOP.varInsert(__Vfinal,"enc_s_tvalid", &(TOP.enc_s_tvalid), false, VLVT_UINT8,VLVD_IN|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"rst_n", &(TOP.rst_n), false, VLVT_UINT8,VLVD_IN|VLVF_PUB_RW,0);
        __Vscope_TOP.varInsert(__Vfinal,"stat_dec_bad_cksum", &(TOP.stat_dec_bad_cksum), false, VLVT_UINT32,VLVD_OUT|VLVF_PUB_RW,1 ,31,0);
        __Vscope_TOP.varInsert(__Vfinal,"stat_dec_bad_port", &(TOP.stat_dec_bad_port), false, VLVT_UINT32,VLVD_OUT|VLVF_PUB_RW,1 ,31,0);
        __Vscope_TOP.varInsert(__Vfinal,"stat_dec_frames_out", &(TOP.stat_dec_frames_out), false, VLVT_UINT32,VLVD_OUT|VLVF_PUB_RW,1 ,31,0);
        __Vscope_TOP.varInsert(__Vfinal,"stat_dec_oversize", &(TOP.stat_dec_oversize), false, VLVT_UINT32,VLVD_OUT|VLVF_PUB_RW,1 ,31,0);
        __Vscope_TOP.varInsert(__Vfinal,"stat_enc_frames_out", &(TOP.stat_enc_frames_out), false, VLVT_UINT32,VLVD_OUT|VLVF_PUB_RW,1 ,31,0);
        __Vscope_TOP.varInsert(__Vfinal,"stat_enc_oversize", &(TOP.stat_enc_oversize), false, VLVT_UINT32,VLVD_OUT|VLVF_PUB_RW,1 ,31,0);
        __Vscope_TOP.varInsert(__Vfinal,"tb_inject_mode", &(TOP.tb_inject_mode), false, VLVT_UINT8,VLVD_IN|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"cfg_local_ip", &(TOP.tb_top__DOT__cfg_local_ip), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top.varInsert(__Vfinal,"cfg_local_mac", &(TOP.tb_top__DOT__cfg_local_mac), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,47,0);
        __Vscope_tb_top.varInsert(__Vfinal,"cfg_mtu", &(TOP.tb_top__DOT__cfg_mtu), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top.varInsert(__Vfinal,"cfg_peer_ip", &(TOP.tb_top__DOT__cfg_peer_ip), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top.varInsert(__Vfinal,"cfg_peer_mac", &(TOP.tb_top__DOT__cfg_peer_mac), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,47,0);
        __Vscope_tb_top.varInsert(__Vfinal,"cfg_udp_port", &(TOP.tb_top__DOT__cfg_udp_port), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top.varInsert(__Vfinal,"clk", &(TOP.tb_top__DOT__clk), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_in_tdata", &(TOP.tb_top__DOT__dec_in_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_in_tkeep", &(TOP.tb_top__DOT__dec_in_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_in_tlast", &(TOP.tb_top__DOT__dec_in_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_in_tready", &(TOP.tb_top__DOT__dec_in_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_in_tuser_size", &(TOP.tb_top__DOT__dec_in_tuser_size), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_in_tvalid", &(TOP.tb_top__DOT__dec_in_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_m_tdata", &(TOP.tb_top__DOT__dec_m_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_m_tkeep", &(TOP.tb_top__DOT__dec_m_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_m_tlast", &(TOP.tb_top__DOT__dec_m_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_m_tready", &(TOP.tb_top__DOT__dec_m_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_m_tuser", &(TOP.tb_top__DOT__dec_m_tuser), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_m_tvalid", &(TOP.tb_top__DOT__dec_m_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_s_tdata", &(TOP.tb_top__DOT__dec_s_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_s_tkeep", &(TOP.tb_top__DOT__dec_s_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_s_tlast", &(TOP.tb_top__DOT__dec_s_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_s_tready", &(TOP.tb_top__DOT__dec_s_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_s_tuser", &(TOP.tb_top__DOT__dec_s_tuser), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top.varInsert(__Vfinal,"dec_s_tvalid", &(TOP.tb_top__DOT__dec_s_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_m_tdata", &(TOP.tb_top__DOT__enc_m_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_m_tkeep", &(TOP.tb_top__DOT__enc_m_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_m_tlast", &(TOP.tb_top__DOT__enc_m_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_m_tready", &(TOP.tb_top__DOT__enc_m_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_m_tuser", &(TOP.tb_top__DOT__enc_m_tuser), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_m_tvalid", &(TOP.tb_top__DOT__enc_m_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_out_tdata", &(TOP.tb_top__DOT__enc_out_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_out_tkeep", &(TOP.tb_top__DOT__enc_out_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_out_tlast", &(TOP.tb_top__DOT__enc_out_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_out_tready", &(TOP.tb_top__DOT__enc_out_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_out_tuser_size", &(TOP.tb_top__DOT__enc_out_tuser_size), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_out_tvalid", &(TOP.tb_top__DOT__enc_out_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_s_tdata", &(TOP.tb_top__DOT__enc_s_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_s_tkeep", &(TOP.tb_top__DOT__enc_s_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_s_tlast", &(TOP.tb_top__DOT__enc_s_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_s_tready", &(TOP.tb_top__DOT__enc_s_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_s_tuser", &(TOP.tb_top__DOT__enc_s_tuser), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top.varInsert(__Vfinal,"enc_s_tvalid", &(TOP.tb_top__DOT__enc_s_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"rst_n", &(TOP.tb_top__DOT__rst_n), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top.varInsert(__Vfinal,"stat_dec_bad_cksum", &(TOP.tb_top__DOT__stat_dec_bad_cksum), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top.varInsert(__Vfinal,"stat_dec_bad_port", &(TOP.tb_top__DOT__stat_dec_bad_port), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top.varInsert(__Vfinal,"stat_dec_frames_out", &(TOP.tb_top__DOT__stat_dec_frames_out), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top.varInsert(__Vfinal,"stat_dec_oversize", &(TOP.tb_top__DOT__stat_dec_oversize), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top.varInsert(__Vfinal,"stat_enc_frames_out", &(TOP.tb_top__DOT__stat_enc_frames_out), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top.varInsert(__Vfinal,"stat_enc_oversize", &(TOP.tb_top__DOT__stat_enc_oversize), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top.varInsert(__Vfinal,"tb_inject_mode", &(TOP.tb_top__DOT__tb_inject_mode), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"b14_ip_hdr", &(TOP.tb_top__DOT__decap__DOT__b14_ip_hdr), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,159,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"b14_ver_ihl", &(TOP.tb_top__DOT__decap__DOT__b14_ver_ihl), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,1 ,7,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"b16_ip_len", &(TOP.tb_top__DOT__decap__DOT__b16_ip_len), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"b23_ip_proto", &(TOP.tb_top__DOT__decap__DOT__b23_ip_proto), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,1 ,7,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"b34_udp_dport_beat0", &(TOP.tb_top__DOT__decap__DOT__b34_udp_dport_beat0), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"can_accept", &(TOP.tb_top__DOT__decap__DOT__can_accept), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"carry_data", &(TOP.tb_top__DOT__decap__DOT__carry_data), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,175,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"carry_keep", &(TOP.tb_top__DOT__decap__DOT__carry_keep), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,21,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"cfg_local_ip", &(TOP.tb_top__DOT__decap__DOT__cfg_local_ip), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"cfg_mtu", &(TOP.tb_top__DOT__decap__DOT__cfg_mtu), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"cfg_udp_port", &(TOP.tb_top__DOT__decap__DOT__cfg_udp_port), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"cksum_ok", &(TOP.tb_top__DOT__decap__DOT__cksum_ok), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"clk", &(TOP.tb_top__DOT__decap__DOT__clk), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"fire_in", &(TOP.tb_top__DOT__decap__DOT__fire_in), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"ip_hdr_r", &(TOP.tb_top__DOT__decap__DOT__ip_hdr_r), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,159,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"m_axis_tdata", &(TOP.tb_top__DOT__decap__DOT__m_axis_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"m_axis_tkeep", &(TOP.tb_top__DOT__decap__DOT__m_axis_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"m_axis_tlast", &(TOP.tb_top__DOT__decap__DOT__m_axis_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"m_axis_tready", &(TOP.tb_top__DOT__decap__DOT__m_axis_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"m_axis_tuser_size", &(TOP.tb_top__DOT__decap__DOT__m_axis_tuser_size), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"m_axis_tvalid", &(TOP.tb_top__DOT__decap__DOT__m_axis_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"need_tail", &(TOP.tb_top__DOT__decap__DOT__need_tail), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"next_carry_data", &(TOP.tb_top__DOT__decap__DOT__next_carry_data), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,175,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"next_carry_keep", &(TOP.tb_top__DOT__decap__DOT__next_carry_keep), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,21,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"out_ready", &(TOP.tb_top__DOT__decap__DOT__out_ready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"out_tuser_size", &(TOP.tb_top__DOT__decap__DOT__out_tuser_size), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"rst_n", &(TOP.tb_top__DOT__decap__DOT__rst_n), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"s_axis_tdata", &(TOP.tb_top__DOT__decap__DOT__s_axis_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"s_axis_tkeep", &(TOP.tb_top__DOT__decap__DOT__s_axis_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"s_axis_tlast", &(TOP.tb_top__DOT__decap__DOT__s_axis_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"s_axis_tready", &(TOP.tb_top__DOT__decap__DOT__s_axis_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"s_axis_tuser_size", &(TOP.tb_top__DOT__decap__DOT__s_axis_tuser_size), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"s_axis_tvalid", &(TOP.tb_top__DOT__decap__DOT__s_axis_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"stat_drops_bad_cksum", &(TOP.tb_top__DOT__decap__DOT__stat_drops_bad_cksum), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"stat_drops_bad_port", &(TOP.tb_top__DOT__decap__DOT__stat_drops_bad_port), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"stat_drops_oversize", &(TOP.tb_top__DOT__decap__DOT__stat_drops_oversize), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"stat_frames_out", &(TOP.tb_top__DOT__decap__DOT__stat_frames_out), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"state", &(TOP.tb_top__DOT__decap__DOT__state), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,1 ,2,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"tuser_size_r", &(TOP.tb_top__DOT__decap__DOT__tuser_size_r), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"vck_fold", &(TOP.tb_top__DOT__decap__DOT__vck_fold), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,16,0);
        __Vscope_tb_top__decap.varInsert(__Vfinal,"vck_sum", &(TOP.tb_top__DOT__decap__DOT__vck_sum), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,19,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"can_accept", &(TOP.tb_top__DOT__encap__DOT__can_accept), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"carry_data", &(TOP.tb_top__DOT__encap__DOT__carry_data), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,223,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"carry_keep", &(TOP.tb_top__DOT__encap__DOT__carry_keep), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,27,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"cfg_local_ip", &(TOP.tb_top__DOT__encap__DOT__cfg_local_ip), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"cfg_local_mac", &(TOP.tb_top__DOT__encap__DOT__cfg_local_mac), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,47,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"cfg_mtu", &(TOP.tb_top__DOT__encap__DOT__cfg_mtu), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"cfg_peer_ip", &(TOP.tb_top__DOT__encap__DOT__cfg_peer_ip), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"cfg_peer_mac", &(TOP.tb_top__DOT__encap__DOT__cfg_peer_mac), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,47,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"cfg_udp_port", &(TOP.tb_top__DOT__encap__DOT__cfg_udp_port), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"ck_fold", &(TOP.tb_top__DOT__encap__DOT__ck_fold), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,16,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"ck_sum", &(TOP.tb_top__DOT__encap__DOT__ck_sum), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,19,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"clk", &(TOP.tb_top__DOT__encap__DOT__clk), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"fire_in", &(TOP.tb_top__DOT__encap__DOT__fire_in), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"hdr", &(TOP.tb_top__DOT__encap__DOT__hdr), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,335,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"ip_cksum", &(TOP.tb_top__DOT__encap__DOT__ip_cksum), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"ip_id_ctr", &(TOP.tb_top__DOT__encap__DOT__ip_id_ctr), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"ip_len_comb", &(TOP.tb_top__DOT__encap__DOT__ip_len_comb), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"m_axis_tdata", &(TOP.tb_top__DOT__encap__DOT__m_axis_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"m_axis_tkeep", &(TOP.tb_top__DOT__encap__DOT__m_axis_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"m_axis_tlast", &(TOP.tb_top__DOT__encap__DOT__m_axis_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"m_axis_tready", &(TOP.tb_top__DOT__encap__DOT__m_axis_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"m_axis_tuser_size", &(TOP.tb_top__DOT__encap__DOT__m_axis_tuser_size), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"m_axis_tvalid", &(TOP.tb_top__DOT__encap__DOT__m_axis_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"need_tail", &(TOP.tb_top__DOT__encap__DOT__need_tail), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"next_carry_data", &(TOP.tb_top__DOT__encap__DOT__next_carry_data), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,223,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"next_carry_keep", &(TOP.tb_top__DOT__encap__DOT__next_carry_keep), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,27,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"out_ready", &(TOP.tb_top__DOT__encap__DOT__out_ready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"rst_n", &(TOP.tb_top__DOT__encap__DOT__rst_n), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"s_axis_tdata", &(TOP.tb_top__DOT__encap__DOT__s_axis_tdata), false, VLVT_WDATA,VLVD_NODIR|VLVF_PUB_RW,1 ,511,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"s_axis_tkeep", &(TOP.tb_top__DOT__encap__DOT__s_axis_tkeep), false, VLVT_UINT64,VLVD_NODIR|VLVF_PUB_RW,1 ,63,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"s_axis_tlast", &(TOP.tb_top__DOT__encap__DOT__s_axis_tlast), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"s_axis_tready", &(TOP.tb_top__DOT__encap__DOT__s_axis_tready), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"s_axis_tuser_size", &(TOP.tb_top__DOT__encap__DOT__s_axis_tuser_size), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"s_axis_tvalid", &(TOP.tb_top__DOT__encap__DOT__s_axis_tvalid), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"stat_frames_out", &(TOP.tb_top__DOT__encap__DOT__stat_frames_out), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"stat_oversize_drops", &(TOP.tb_top__DOT__encap__DOT__stat_oversize_drops), false, VLVT_UINT32,VLVD_NODIR|VLVF_PUB_RW,1 ,31,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"state", &(TOP.tb_top__DOT__encap__DOT__state), false, VLVT_UINT8,VLVD_NODIR|VLVF_PUB_RW,1 ,1,0);
        __Vscope_tb_top__encap.varInsert(__Vfinal,"udp_len_comb", &(TOP.tb_top__DOT__encap__DOT__udp_len_comb), false, VLVT_UINT16,VLVD_NODIR|VLVF_PUB_RW,1 ,15,0);
    }
}
