// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtop.h for the primary calling header

#include "Vtop__pch.h"
#include "Vtop___024root.h"

void Vtop___024root___ico_sequent__TOP__0(Vtop___024root* vlSelf);

void Vtop___024root___eval_ico(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_ico\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VicoTriggered.word(0U))) {
        Vtop___024root___ico_sequent__TOP__0(vlSelf);
    }
}

VL_INLINE_OPT void Vtop___024root___ico_sequent__TOP__0(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___ico_sequent__TOP__0\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Init
    VlWide<3>/*95:0*/ __Vtemp_3;
    // Body
    vlSelfRef.tb_top__DOT__enc_m_tready = vlSelfRef.enc_m_tready;
    vlSelfRef.tb_top__DOT__dec_s_tvalid = vlSelfRef.dec_s_tvalid;
    vlSelfRef.tb_top__DOT__dec_s_tdata[0U] = vlSelfRef.dec_s_tdata[0U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[1U] = vlSelfRef.dec_s_tdata[1U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[2U] = vlSelfRef.dec_s_tdata[2U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[3U] = vlSelfRef.dec_s_tdata[3U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[4U] = vlSelfRef.dec_s_tdata[4U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[5U] = vlSelfRef.dec_s_tdata[5U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[6U] = vlSelfRef.dec_s_tdata[6U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[7U] = vlSelfRef.dec_s_tdata[7U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[8U] = vlSelfRef.dec_s_tdata[8U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[9U] = vlSelfRef.dec_s_tdata[9U];
    vlSelfRef.tb_top__DOT__dec_s_tdata[0xaU] = vlSelfRef.dec_s_tdata[0xaU];
    vlSelfRef.tb_top__DOT__dec_s_tdata[0xbU] = vlSelfRef.dec_s_tdata[0xbU];
    vlSelfRef.tb_top__DOT__dec_s_tdata[0xcU] = vlSelfRef.dec_s_tdata[0xcU];
    vlSelfRef.tb_top__DOT__dec_s_tdata[0xdU] = vlSelfRef.dec_s_tdata[0xdU];
    vlSelfRef.tb_top__DOT__dec_s_tdata[0xeU] = vlSelfRef.dec_s_tdata[0xeU];
    vlSelfRef.tb_top__DOT__dec_s_tdata[0xfU] = vlSelfRef.dec_s_tdata[0xfU];
    vlSelfRef.tb_top__DOT__dec_s_tkeep = vlSelfRef.dec_s_tkeep;
    vlSelfRef.tb_top__DOT__dec_s_tlast = vlSelfRef.dec_s_tlast;
    vlSelfRef.tb_top__DOT__dec_s_tuser = vlSelfRef.dec_s_tuser;
    vlSelfRef.tb_top__DOT__tb_inject_mode = vlSelfRef.tb_inject_mode;
    vlSelfRef.enc_m_tvalid = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid;
    vlSelfRef.enc_m_tdata[0U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U];
    vlSelfRef.enc_m_tdata[1U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U];
    vlSelfRef.enc_m_tdata[2U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U];
    vlSelfRef.enc_m_tdata[3U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U];
    vlSelfRef.enc_m_tdata[4U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U];
    vlSelfRef.enc_m_tdata[5U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U];
    vlSelfRef.enc_m_tdata[6U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U];
    vlSelfRef.enc_m_tdata[7U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U];
    vlSelfRef.enc_m_tdata[8U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U];
    vlSelfRef.enc_m_tdata[9U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U];
    vlSelfRef.enc_m_tdata[0xaU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.enc_m_tdata[0xbU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.enc_m_tdata[0xcU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.enc_m_tdata[0xdU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.enc_m_tdata[0xeU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.enc_m_tdata[0xfU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.enc_m_tkeep = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep;
    vlSelfRef.enc_m_tlast = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast;
    vlSelfRef.enc_m_tuser = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size;
    vlSelfRef.dec_m_tvalid = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid;
    vlSelfRef.tb_top__DOT__enc_m_tvalid = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid;
    vlSelfRef.tb_top__DOT__enc_m_tdata[0U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[1U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[2U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[3U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[4U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[5U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[6U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[7U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[8U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[9U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xaU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xbU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xcU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xdU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xeU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xfU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.tb_top__DOT__enc_m_tkeep = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep;
    vlSelfRef.tb_top__DOT__enc_m_tlast = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast;
    vlSelfRef.tb_top__DOT__enc_m_tuser = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size;
    vlSelfRef.tb_top__DOT__dec_m_tvalid = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid;
    vlSelfRef.tb_top__DOT__enc_out_tvalid = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid;
    vlSelfRef.tb_top__DOT__enc_out_tdata[0U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[1U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[2U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[3U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[4U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[5U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[6U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[7U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[8U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[9U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xaU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xbU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xcU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xdU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xeU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xfU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.tb_top__DOT__enc_out_tkeep = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep;
    vlSelfRef.tb_top__DOT__enc_out_tlast = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast;
    vlSelfRef.tb_top__DOT__enc_out_tuser_size = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size;
    vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[0U] 
        = vlSelfRef.enc_s_tdata[9U];
    vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[1U] 
        = vlSelfRef.enc_s_tdata[0xaU];
    vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[2U] 
        = vlSelfRef.enc_s_tdata[0xbU];
    vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[3U] 
        = vlSelfRef.enc_s_tdata[0xcU];
    vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[4U] 
        = vlSelfRef.enc_s_tdata[0xdU];
    vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[5U] 
        = vlSelfRef.enc_s_tdata[0xeU];
    vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[6U] 
        = vlSelfRef.enc_s_tdata[0xfU];
    vlSelfRef.dec_m_tdata[0U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0U];
    vlSelfRef.dec_m_tdata[1U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[1U];
    vlSelfRef.dec_m_tdata[2U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[2U];
    vlSelfRef.dec_m_tdata[3U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[3U];
    vlSelfRef.dec_m_tdata[4U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[4U];
    vlSelfRef.dec_m_tdata[5U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[5U];
    vlSelfRef.dec_m_tdata[6U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[6U];
    vlSelfRef.dec_m_tdata[7U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[7U];
    vlSelfRef.dec_m_tdata[8U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[8U];
    vlSelfRef.dec_m_tdata[9U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[9U];
    vlSelfRef.dec_m_tdata[0xaU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.dec_m_tdata[0xbU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.dec_m_tdata[0xcU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.dec_m_tdata[0xdU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.dec_m_tdata[0xeU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.dec_m_tdata[0xfU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[1U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[1U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[2U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[2U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[3U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[3U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[4U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[4U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[5U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[5U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[6U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[6U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[7U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[7U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[8U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[8U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[9U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[9U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xaU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xbU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xcU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xdU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xeU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xfU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.dec_m_tkeep = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tkeep;
    vlSelfRef.tb_top__DOT__dec_m_tkeep = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tkeep;
    vlSelfRef.dec_m_tlast = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast;
    vlSelfRef.tb_top__DOT__dec_m_tlast = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast;
    vlSelfRef.dec_m_tuser = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tuser_size;
    vlSelfRef.tb_top__DOT__dec_m_tuser = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tuser_size;
    vlSelfRef.stat_enc_frames_out = vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out;
    vlSelfRef.tb_top__DOT__stat_enc_frames_out = vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out;
    vlSelfRef.stat_enc_oversize = vlSelfRef.tb_top__DOT__encap__DOT__stat_oversize_drops;
    vlSelfRef.tb_top__DOT__stat_enc_oversize = vlSelfRef.tb_top__DOT__encap__DOT__stat_oversize_drops;
    vlSelfRef.stat_dec_frames_out = vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out;
    vlSelfRef.tb_top__DOT__stat_dec_frames_out = vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out;
    vlSelfRef.stat_dec_bad_cksum = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum;
    vlSelfRef.tb_top__DOT__stat_dec_bad_cksum = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum;
    vlSelfRef.stat_dec_bad_port = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_port;
    vlSelfRef.tb_top__DOT__stat_dec_bad_port = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_port;
    vlSelfRef.stat_dec_oversize = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_oversize;
    vlSelfRef.tb_top__DOT__stat_dec_oversize = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_oversize;
    vlSelfRef.tb_top__DOT__decap__DOT__out_tuser_size 
        = (0xffffU & ((IData)(vlSelfRef.tb_top__DOT__decap__DOT__tuser_size_r) 
                      - (IData)(0x2aU)));
    vlSelfRef.tb_top__DOT__enc_s_tvalid = vlSelfRef.enc_s_tvalid;
    vlSelfRef.tb_top__DOT__enc_s_tdata[0U] = vlSelfRef.enc_s_tdata[0U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[1U] = vlSelfRef.enc_s_tdata[1U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[2U] = vlSelfRef.enc_s_tdata[2U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[3U] = vlSelfRef.enc_s_tdata[3U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[4U] = vlSelfRef.enc_s_tdata[4U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[5U] = vlSelfRef.enc_s_tdata[5U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[6U] = vlSelfRef.enc_s_tdata[6U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[7U] = vlSelfRef.enc_s_tdata[7U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[8U] = vlSelfRef.enc_s_tdata[8U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[9U] = vlSelfRef.enc_s_tdata[9U];
    vlSelfRef.tb_top__DOT__enc_s_tdata[0xaU] = vlSelfRef.enc_s_tdata[0xaU];
    vlSelfRef.tb_top__DOT__enc_s_tdata[0xbU] = vlSelfRef.enc_s_tdata[0xbU];
    vlSelfRef.tb_top__DOT__enc_s_tdata[0xcU] = vlSelfRef.enc_s_tdata[0xcU];
    vlSelfRef.tb_top__DOT__enc_s_tdata[0xdU] = vlSelfRef.enc_s_tdata[0xdU];
    vlSelfRef.tb_top__DOT__enc_s_tdata[0xeU] = vlSelfRef.enc_s_tdata[0xeU];
    vlSelfRef.tb_top__DOT__enc_s_tdata[0xfU] = vlSelfRef.enc_s_tdata[0xfU];
    vlSelfRef.tb_top__DOT__enc_s_tkeep = vlSelfRef.enc_s_tkeep;
    vlSelfRef.tb_top__DOT__enc_s_tlast = vlSelfRef.enc_s_tlast;
    vlSelfRef.tb_top__DOT__enc_s_tuser = vlSelfRef.enc_s_tuser;
    vlSelfRef.tb_top__DOT__dec_m_tready = vlSelfRef.dec_m_tready;
    vlSelfRef.tb_top__DOT__cfg_local_mac = vlSelfRef.cfg_local_mac;
    vlSelfRef.tb_top__DOT__cfg_peer_mac = vlSelfRef.cfg_peer_mac;
    vlSelfRef.tb_top__DOT__cfg_peer_ip = vlSelfRef.cfg_peer_ip;
    vlSelfRef.tb_top__DOT__encap__DOT__next_carry_keep 
        = (0xfffffffU & (IData)((vlSelfRef.enc_s_tkeep 
                                 >> 0x24U)));
    vlSelfRef.tb_top__DOT__decap__DOT__vck_sum = (0xfffffU 
                                                  & ((((((((((0xffffU 
                                                              & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[0U]) 
                                                             + 
                                                             (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[0U] 
                                                              >> 0x10U)) 
                                                            + 
                                                            (0xffffU 
                                                             & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[1U])) 
                                                           + 
                                                           (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[1U] 
                                                            >> 0x10U)) 
                                                          + 
                                                          (0xffffU 
                                                           & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[2U])) 
                                                         + 
                                                         (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[2U] 
                                                          >> 0x10U)) 
                                                        + 
                                                        (0xffffU 
                                                         & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[3U])) 
                                                       + 
                                                       (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[3U] 
                                                        >> 0x10U)) 
                                                      + 
                                                      (0xffffU 
                                                       & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[4U])) 
                                                     + 
                                                     (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[4U] 
                                                      >> 0x10U)));
    vlSelfRef.tb_top__DOT__decap__DOT__vck_fold = (0x1ffffU 
                                                   & ((0xfU 
                                                       & (vlSelfRef.tb_top__DOT__decap__DOT__vck_sum 
                                                          >> 0x10U)) 
                                                      + 
                                                      (0xffffU 
                                                       & vlSelfRef.tb_top__DOT__decap__DOT__vck_sum)));
    vlSelfRef.tb_top__DOT__decap__DOT__cksum_ok = (0xffffU 
                                                   == 
                                                   (0x1ffffU 
                                                    & ((0x10000U 
                                                        & vlSelfRef.tb_top__DOT__decap__DOT__vck_fold)
                                                        ? 
                                                       ((IData)(1U) 
                                                        + 
                                                        (0xffffU 
                                                         & vlSelfRef.tb_top__DOT__decap__DOT__vck_fold))
                                                        : 
                                                       (0xffffU 
                                                        & vlSelfRef.tb_top__DOT__decap__DOT__vck_fold))));
    vlSelfRef.tb_top__DOT__clk = vlSelfRef.clk;
    vlSelfRef.tb_top__DOT__rst_n = vlSelfRef.rst_n;
    vlSelfRef.tb_top__DOT__cfg_local_ip = vlSelfRef.cfg_local_ip;
    vlSelfRef.tb_top__DOT__cfg_udp_port = vlSelfRef.cfg_udp_port;
    vlSelfRef.tb_top__DOT__cfg_mtu = vlSelfRef.cfg_mtu;
    vlSelfRef.tb_top__DOT__encap__DOT__udp_len_comb 
        = (0xffffU & ((IData)(vlSelfRef.enc_s_tuser) 
                      - (IData)(6U)));
    vlSelfRef.tb_top__DOT__encap__DOT__ip_len_comb 
        = (0xffffU & ((IData)(0xeU) + (IData)(vlSelfRef.enc_s_tuser)));
    vlSelfRef.tb_top__DOT__decap__DOT__out_ready = 
        (1U & ((~ (IData)(vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid)) 
               | (IData)(vlSelfRef.dec_m_tready)));
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tvalid 
        = vlSelfRef.tb_top__DOT__enc_s_tvalid;
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[0U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[0U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[1U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[1U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[2U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[2U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[3U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[3U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[4U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[4U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[5U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[5U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[6U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[6U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[7U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[7U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[8U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[8U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[9U] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[9U];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[0xaU] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[0xaU];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[0xbU] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[0xbU];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[0xcU] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[0xcU];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[0xdU] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[0xdU];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[0xeU] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[0xeU];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata[0xfU] 
        = vlSelfRef.tb_top__DOT__enc_s_tdata[0xfU];
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tkeep 
        = vlSelfRef.tb_top__DOT__enc_s_tkeep;
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tlast 
        = vlSelfRef.tb_top__DOT__enc_s_tlast;
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tuser_size 
        = vlSelfRef.tb_top__DOT__enc_s_tuser;
    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tready 
        = vlSelfRef.tb_top__DOT__dec_m_tready;
    vlSelfRef.tb_top__DOT__encap__DOT__cfg_local_mac 
        = vlSelfRef.tb_top__DOT__cfg_local_mac;
    vlSelfRef.tb_top__DOT__encap__DOT__cfg_peer_mac 
        = vlSelfRef.tb_top__DOT__cfg_peer_mac;
    vlSelfRef.tb_top__DOT__encap__DOT__cfg_peer_ip 
        = vlSelfRef.tb_top__DOT__cfg_peer_ip;
    vlSelfRef.tb_top__DOT__encap__DOT__need_tail = 
        (0U != vlSelfRef.tb_top__DOT__encap__DOT__next_carry_keep);
    if (vlSelfRef.tb_inject_mode) {
        vlSelfRef.tb_top__DOT__dec_in_tlast = vlSelfRef.dec_s_tlast;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tlast 
            = vlSelfRef.tb_top__DOT__dec_in_tlast;
        vlSelfRef.tb_top__DOT__dec_in_tuser_size = vlSelfRef.dec_s_tuser;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tuser_size 
            = vlSelfRef.tb_top__DOT__dec_in_tuser_size;
        vlSelfRef.tb_top__DOT__encap__DOT__clk = vlSelfRef.tb_top__DOT__clk;
        vlSelfRef.tb_top__DOT__decap__DOT__clk = vlSelfRef.tb_top__DOT__clk;
        vlSelfRef.tb_top__DOT__encap__DOT__rst_n = vlSelfRef.tb_top__DOT__rst_n;
        vlSelfRef.tb_top__DOT__decap__DOT__rst_n = vlSelfRef.tb_top__DOT__rst_n;
        vlSelfRef.tb_top__DOT__encap__DOT__cfg_local_ip 
            = vlSelfRef.tb_top__DOT__cfg_local_ip;
        vlSelfRef.tb_top__DOT__decap__DOT__cfg_local_ip 
            = vlSelfRef.tb_top__DOT__cfg_local_ip;
        vlSelfRef.tb_top__DOT__encap__DOT__cfg_udp_port 
            = vlSelfRef.tb_top__DOT__cfg_udp_port;
        vlSelfRef.tb_top__DOT__decap__DOT__cfg_udp_port 
            = vlSelfRef.tb_top__DOT__cfg_udp_port;
        vlSelfRef.tb_top__DOT__encap__DOT__cfg_mtu 
            = vlSelfRef.tb_top__DOT__cfg_mtu;
        vlSelfRef.tb_top__DOT__decap__DOT__cfg_mtu 
            = vlSelfRef.tb_top__DOT__cfg_mtu;
        vlSelfRef.tb_top__DOT__dec_in_tvalid = vlSelfRef.dec_s_tvalid;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tvalid 
            = vlSelfRef.tb_top__DOT__dec_in_tvalid;
        vlSelfRef.tb_top__DOT__dec_in_tkeep = vlSelfRef.dec_s_tkeep;
    } else {
        vlSelfRef.tb_top__DOT__dec_in_tlast = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tlast 
            = vlSelfRef.tb_top__DOT__dec_in_tlast;
        vlSelfRef.tb_top__DOT__dec_in_tuser_size = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tuser_size 
            = vlSelfRef.tb_top__DOT__dec_in_tuser_size;
        vlSelfRef.tb_top__DOT__encap__DOT__clk = vlSelfRef.tb_top__DOT__clk;
        vlSelfRef.tb_top__DOT__decap__DOT__clk = vlSelfRef.tb_top__DOT__clk;
        vlSelfRef.tb_top__DOT__encap__DOT__rst_n = vlSelfRef.tb_top__DOT__rst_n;
        vlSelfRef.tb_top__DOT__decap__DOT__rst_n = vlSelfRef.tb_top__DOT__rst_n;
        vlSelfRef.tb_top__DOT__encap__DOT__cfg_local_ip 
            = vlSelfRef.tb_top__DOT__cfg_local_ip;
        vlSelfRef.tb_top__DOT__decap__DOT__cfg_local_ip 
            = vlSelfRef.tb_top__DOT__cfg_local_ip;
        vlSelfRef.tb_top__DOT__encap__DOT__cfg_udp_port 
            = vlSelfRef.tb_top__DOT__cfg_udp_port;
        vlSelfRef.tb_top__DOT__decap__DOT__cfg_udp_port 
            = vlSelfRef.tb_top__DOT__cfg_udp_port;
        vlSelfRef.tb_top__DOT__encap__DOT__cfg_mtu 
            = vlSelfRef.tb_top__DOT__cfg_mtu;
        vlSelfRef.tb_top__DOT__decap__DOT__cfg_mtu 
            = vlSelfRef.tb_top__DOT__cfg_mtu;
        vlSelfRef.tb_top__DOT__dec_in_tvalid = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tvalid 
            = vlSelfRef.tb_top__DOT__dec_in_tvalid;
        vlSelfRef.tb_top__DOT__dec_in_tkeep = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep;
    }
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tkeep 
        = vlSelfRef.tb_top__DOT__dec_in_tkeep;
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_keep 
        = (0x3fffffU & (IData)((vlSelfRef.tb_top__DOT__dec_in_tkeep 
                                >> 0x2aU)));
    if (vlSelfRef.tb_inject_mode) {
        vlSelfRef.tb_top__DOT__dec_in_tdata[0U] = vlSelfRef.dec_s_tdata[0U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[1U] = vlSelfRef.dec_s_tdata[1U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[2U] = vlSelfRef.dec_s_tdata[2U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[3U] = vlSelfRef.dec_s_tdata[3U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[4U] = vlSelfRef.dec_s_tdata[4U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[5U] = vlSelfRef.dec_s_tdata[5U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[6U] = vlSelfRef.dec_s_tdata[6U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[7U] = vlSelfRef.dec_s_tdata[7U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[8U] = vlSelfRef.dec_s_tdata[8U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[9U] = vlSelfRef.dec_s_tdata[9U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU] = 
            vlSelfRef.dec_s_tdata[0xaU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU] = 
            vlSelfRef.dec_s_tdata[0xbU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU] = 
            vlSelfRef.dec_s_tdata[0xcU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU] = 
            vlSelfRef.dec_s_tdata[0xdU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU] = 
            vlSelfRef.dec_s_tdata[0xeU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU] = 
            vlSelfRef.dec_s_tdata[0xfU];
    } else {
        vlSelfRef.tb_top__DOT__dec_in_tdata[0U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[1U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[2U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[3U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[4U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[5U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[6U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[7U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[8U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[9U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU];
    }
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[1U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[1U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[2U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[2U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[3U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[3U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[4U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[4U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[5U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[5U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[6U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[6U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[7U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[7U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[8U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[8U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[9U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[9U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xaU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xbU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xcU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xdU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xeU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xfU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU];
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[0U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[4U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[3U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[1U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[5U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[4U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[2U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[6U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[5U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[3U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[7U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[6U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[4U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[8U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[7U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[0U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[1U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[2U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[3U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[4U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[5U] 
        = (vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU] 
           >> 0x10U);
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ver_ihl 
        = (0xffU & (vlSelfRef.tb_top__DOT__dec_in_tdata[3U] 
                    >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b23_ip_proto 
        = (vlSelfRef.tb_top__DOT__dec_in_tdata[5U] 
           >> 0x18U);
    vlSelfRef.tb_top__DOT__decap__DOT__b34_udp_dport_beat0 
        = ((0xff00U & (vlSelfRef.tb_top__DOT__dec_in_tdata[9U] 
                       << 8U)) | (0xffU & (vlSelfRef.tb_top__DOT__dec_in_tdata[9U] 
                                           >> 8U)));
    vlSelfRef.tb_top__DOT__decap__DOT__b16_ip_len = 
        ((0xff00U & (vlSelfRef.tb_top__DOT__dec_in_tdata[4U] 
                     << 8U)) | (0xffU & (vlSelfRef.tb_top__DOT__dec_in_tdata[4U] 
                                         >> 8U)));
    vlSelfRef.tb_top__DOT__encap__DOT__ck_sum = (0xfffffU 
                                                 & ((IData)(0xc511U) 
                                                    + 
                                                    ((((((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_len_comb) 
                                                         + (IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr)) 
                                                        + 
                                                        (vlSelfRef.cfg_local_ip 
                                                         >> 0x10U)) 
                                                       + 
                                                       (0xffffU 
                                                        & vlSelfRef.cfg_local_ip)) 
                                                      + 
                                                      (vlSelfRef.cfg_peer_ip 
                                                       >> 0x10U)) 
                                                     + 
                                                     (0xffffU 
                                                      & vlSelfRef.cfg_peer_ip))));
    vlSelfRef.tb_top__DOT__encap__DOT__ck_fold = (0x1ffffU 
                                                  & ((0xfU 
                                                      & (vlSelfRef.tb_top__DOT__encap__DOT__ck_sum 
                                                         >> 0x10U)) 
                                                     + 
                                                     (0xffffU 
                                                      & vlSelfRef.tb_top__DOT__encap__DOT__ck_sum)));
    vlSelfRef.tb_top__DOT__encap__DOT__ip_cksum = (0xffffU 
                                                   & (~ 
                                                      ((0x10000U 
                                                        & vlSelfRef.tb_top__DOT__encap__DOT__ck_fold)
                                                        ? 
                                                       ((IData)(1U) 
                                                        + vlSelfRef.tb_top__DOT__encap__DOT__ck_fold)
                                                        : vlSelfRef.tb_top__DOT__encap__DOT__ck_fold)));
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready 
        = ((3U != (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state)) 
           & ((4U == (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state)) 
              | ((IData)(vlSelfRef.tb_top__DOT__decap__DOT__out_ready) 
                 | ((0U == (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state)) 
                    | (1U == (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state))))));
    vlSelfRef.tb_top__DOT__enc_out_tready = ((IData)(vlSelfRef.tb_inject_mode)
                                              ? (IData)(vlSelfRef.enc_m_tready)
                                              : (IData)(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready));
    vlSelfRef.tb_top__DOT__decap__DOT__need_tail = 
        (0U != vlSelfRef.tb_top__DOT__decap__DOT__next_carry_keep);
    __Vtemp_3[0U] = (IData)((((QData)((IData)((0xffU 
                                               & (IData)(
                                                         (vlSelfRef.cfg_local_mac 
                                                          >> 0x20U))))) 
                              << 0x38U) | (((QData)((IData)(
                                                            (0xffU 
                                                             & (IData)(
                                                                       (vlSelfRef.cfg_local_mac 
                                                                        >> 0x28U))))) 
                                            << 0x30U) 
                                           | (((QData)((IData)(
                                                               (0xffU 
                                                                & (IData)(vlSelfRef.cfg_peer_mac)))) 
                                               << 0x28U) 
                                              | (((QData)((IData)(
                                                                  (0xffU 
                                                                   & (IData)(
                                                                             (vlSelfRef.cfg_peer_mac 
                                                                              >> 8U))))) 
                                                  << 0x20U) 
                                                 | (QData)((IData)(
                                                                   (((IData)(
                                                                             (vlSelfRef.cfg_peer_mac 
                                                                              >> 0x10U)) 
                                                                     << 0x18U) 
                                                                    | ((0xff0000U 
                                                                        & ((IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x18U)) 
                                                                           << 0x10U)) 
                                                                       | ((0xff00U 
                                                                           & ((IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x20U)) 
                                                                              << 8U)) 
                                                                          | (0xffU 
                                                                             & (IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x28U)))))))))))));
    __Vtemp_3[1U] = (IData)(((((QData)((IData)((0xffU 
                                                & (IData)(
                                                          (vlSelfRef.cfg_local_mac 
                                                           >> 0x20U))))) 
                               << 0x38U) | (((QData)((IData)(
                                                             (0xffU 
                                                              & (IData)(
                                                                        (vlSelfRef.cfg_local_mac 
                                                                         >> 0x28U))))) 
                                             << 0x30U) 
                                            | (((QData)((IData)(
                                                                (0xffU 
                                                                 & (IData)(vlSelfRef.cfg_peer_mac)))) 
                                                << 0x28U) 
                                               | (((QData)((IData)(
                                                                   (0xffU 
                                                                    & (IData)(
                                                                              (vlSelfRef.cfg_peer_mac 
                                                                               >> 8U))))) 
                                                   << 0x20U) 
                                                  | (QData)((IData)(
                                                                    (((IData)(
                                                                              (vlSelfRef.cfg_peer_mac 
                                                                               >> 0x10U)) 
                                                                      << 0x18U) 
                                                                     | ((0xff0000U 
                                                                         & ((IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x18U)) 
                                                                            << 0x10U)) 
                                                                        | ((0xff00U 
                                                                            & ((IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x20U)) 
                                                                               << 8U)) 
                                                                           | (0xffU 
                                                                              & (IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x28U)))))))))))) 
                             >> 0x20U));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[0U] = __Vtemp_3[0U];
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[1U] = __Vtemp_3[1U];
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[2U] = (((IData)(vlSelfRef.cfg_local_mac) 
                                                   << 0x18U) 
                                                  | ((0xff0000U 
                                                      & ((IData)(
                                                                 (vlSelfRef.cfg_local_mac 
                                                                  >> 8U)) 
                                                         << 0x10U)) 
                                                     | ((0xff00U 
                                                         & ((IData)(
                                                                    (vlSelfRef.cfg_local_mac 
                                                                     >> 0x10U)) 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & (IData)(
                                                                     (vlSelfRef.cfg_local_mac 
                                                                      >> 0x18U))))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[3U] = 0x450008U;
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[4U] = (((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr) 
                                                   << 0x18U) 
                                                  | ((0xff0000U 
                                                      & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr) 
                                                         << 8U)) 
                                                     | ((0xff00U 
                                                         & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_len_comb) 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_len_comb) 
                                                              >> 8U)))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[5U] = 0x11400040U;
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[6U] = ((0xff000000U 
                                                   & (vlSelfRef.cfg_local_ip 
                                                      << 8U)) 
                                                  | ((0xff0000U 
                                                      & (vlSelfRef.cfg_local_ip 
                                                         >> 8U)) 
                                                     | ((0xff00U 
                                                         & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_cksum) 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_cksum) 
                                                              >> 8U)))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[7U] = ((0xff000000U 
                                                   & (vlSelfRef.cfg_peer_ip 
                                                      << 8U)) 
                                                  | ((0xff0000U 
                                                      & (vlSelfRef.cfg_peer_ip 
                                                         >> 8U)) 
                                                     | ((0xff00U 
                                                         & (vlSelfRef.cfg_local_ip 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & (vlSelfRef.cfg_local_ip 
                                                              >> 8U)))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[8U] = (((IData)(vlSelfRef.cfg_udp_port) 
                                                   << 0x18U) 
                                                  | ((0xff0000U 
                                                      & ((IData)(vlSelfRef.cfg_udp_port) 
                                                         << 8U)) 
                                                     | ((0xff00U 
                                                         & (vlSelfRef.cfg_peer_ip 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & (vlSelfRef.cfg_peer_ip 
                                                              >> 8U)))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[9U] = (((IData)(vlSelfRef.tb_top__DOT__encap__DOT__udp_len_comb) 
                                                   << 0x18U) 
                                                  | ((0xff0000U 
                                                      & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__udp_len_comb) 
                                                         << 8U)) 
                                                     | ((0xff00U 
                                                         & ((IData)(vlSelfRef.cfg_udp_port) 
                                                            << 8U)) 
                                                        | ((IData)(vlSelfRef.cfg_udp_port) 
                                                           >> 8U))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[0xaU] = 0U;
    vlSelfRef.tb_top__DOT__dec_in_tready = vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__decap__DOT__can_accept = vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__decap__DOT__fire_in = ((IData)(vlSelfRef.tb_top__DOT__dec_in_tvalid) 
                                                  & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready));
    vlSelfRef.dec_s_tready = ((IData)(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready) 
                              & (IData)(vlSelfRef.tb_inject_mode));
    vlSelfRef.tb_top__DOT__dec_s_tready = vlSelfRef.dec_s_tready;
    vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tready 
        = vlSelfRef.tb_top__DOT__enc_out_tready;
    vlSelfRef.tb_top__DOT__encap__DOT__out_ready = 
        (1U & ((~ (IData)(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid)) 
               | (IData)(vlSelfRef.tb_top__DOT__enc_out_tready)));
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready 
        = ((3U == (IData)(vlSelfRef.tb_top__DOT__encap__DOT__state)) 
           | ((2U != (IData)(vlSelfRef.tb_top__DOT__encap__DOT__state)) 
              & (IData)(vlSelfRef.tb_top__DOT__encap__DOT__out_ready)));
    vlSelfRef.enc_s_tready = vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__enc_s_tready = vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__encap__DOT__can_accept = vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__encap__DOT__fire_in = ((IData)(vlSelfRef.enc_s_tvalid) 
                                                  & (IData)(vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready));
}

void Vtop___024root___eval_triggers__ico(Vtop___024root* vlSelf);

bool Vtop___024root___eval_phase__ico(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_phase__ico\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Init
    CData/*0:0*/ __VicoExecute;
    // Body
    Vtop___024root___eval_triggers__ico(vlSelf);
    __VicoExecute = vlSelfRef.__VicoTriggered.any();
    if (__VicoExecute) {
        Vtop___024root___eval_ico(vlSelf);
    }
    return (__VicoExecute);
}

void Vtop___024root___eval_act(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_act\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
}

void Vtop___024root___nba_sequent__TOP__0(Vtop___024root* vlSelf);

void Vtop___024root___eval_nba(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_nba\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        Vtop___024root___nba_sequent__TOP__0(vlSelf);
    }
}

extern const VlWide<11>/*351:0*/ Vtop__ConstPool__CONST_hfcc3ede4_0;

VL_INLINE_OPT void Vtop___024root___nba_sequent__TOP__0(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___nba_sequent__TOP__0\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Init
    CData/*1:0*/ __Vdly__tb_top__DOT__encap__DOT__state;
    __Vdly__tb_top__DOT__encap__DOT__state = 0;
    IData/*31:0*/ __Vdly__tb_top__DOT__encap__DOT__stat_frames_out;
    __Vdly__tb_top__DOT__encap__DOT__stat_frames_out = 0;
    CData/*2:0*/ __Vdly__tb_top__DOT__decap__DOT__state;
    __Vdly__tb_top__DOT__decap__DOT__state = 0;
    IData/*31:0*/ __Vdly__tb_top__DOT__decap__DOT__stat_frames_out;
    __Vdly__tb_top__DOT__decap__DOT__stat_frames_out = 0;
    VlWide<6>/*175:0*/ __Vdly__tb_top__DOT__decap__DOT__carry_data;
    VL_ZERO_W(176, __Vdly__tb_top__DOT__decap__DOT__carry_data);
    IData/*21:0*/ __Vdly__tb_top__DOT__decap__DOT__carry_keep;
    __Vdly__tb_top__DOT__decap__DOT__carry_keep = 0;
    IData/*31:0*/ __Vdly__tb_top__DOT__decap__DOT__stat_drops_bad_cksum;
    __Vdly__tb_top__DOT__decap__DOT__stat_drops_bad_cksum = 0;
    VlWide<3>/*95:0*/ __Vtemp_13;
    // Body
    __Vdly__tb_top__DOT__encap__DOT__stat_frames_out 
        = vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out;
    __Vdly__tb_top__DOT__encap__DOT__state = vlSelfRef.tb_top__DOT__encap__DOT__state;
    __Vdly__tb_top__DOT__decap__DOT__carry_keep = vlSelfRef.tb_top__DOT__decap__DOT__carry_keep;
    __Vdly__tb_top__DOT__decap__DOT__carry_data[0U] 
        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[0U];
    __Vdly__tb_top__DOT__decap__DOT__carry_data[1U] 
        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[1U];
    __Vdly__tb_top__DOT__decap__DOT__carry_data[2U] 
        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[2U];
    __Vdly__tb_top__DOT__decap__DOT__carry_data[3U] 
        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[3U];
    __Vdly__tb_top__DOT__decap__DOT__carry_data[4U] 
        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[4U];
    __Vdly__tb_top__DOT__decap__DOT__carry_data[5U] 
        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[5U];
    __Vdly__tb_top__DOT__decap__DOT__stat_drops_bad_cksum 
        = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum;
    __Vdly__tb_top__DOT__decap__DOT__stat_frames_out 
        = vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out;
    __Vdly__tb_top__DOT__decap__DOT__state = vlSelfRef.tb_top__DOT__decap__DOT__state;
    if (vlSelfRef.rst_n) {
        if (((IData)(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid) 
             & (IData)(vlSelfRef.tb_top__DOT__enc_out_tready))) {
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid = 0U;
        }
        if ((2U & (IData)(vlSelfRef.tb_top__DOT__encap__DOT__state))) {
            if ((1U & (IData)(vlSelfRef.tb_top__DOT__encap__DOT__state))) {
                if (((IData)(vlSelfRef.enc_s_tvalid) 
                     & (IData)(vlSelfRef.enc_s_tlast))) {
                    __Vdly__tb_top__DOT__encap__DOT__state = 0U;
                }
            } else if (vlSelfRef.tb_top__DOT__encap__DOT__out_ready) {
                __Vdly__tb_top__DOT__encap__DOT__stat_frames_out 
                    = ((IData)(1U) + vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out);
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid = 1U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[0U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[1U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[2U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[3U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[4U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[5U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[6U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U] = 0U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U] = 0U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U] = 0U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU] = 0U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU] = 0U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU] = 0U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU] = 0U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU] = 0U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU] = 0U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep 
                    = (QData)((IData)(vlSelfRef.tb_top__DOT__encap__DOT__carry_keep));
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast = 1U;
                __Vdly__tb_top__DOT__encap__DOT__state = 0U;
            }
        } else if ((1U & (IData)(vlSelfRef.tb_top__DOT__encap__DOT__state))) {
            if (((IData)(vlSelfRef.tb_top__DOT__encap__DOT__fire_in) 
                 & (IData)(vlSelfRef.tb_top__DOT__encap__DOT__out_ready))) {
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid = 1U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[0U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[1U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[2U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[3U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[4U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[5U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__carry_data[6U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U] 
                    = vlSelfRef.enc_s_tdata[0U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U] 
                    = vlSelfRef.enc_s_tdata[1U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U] 
                    = vlSelfRef.enc_s_tdata[2U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU] 
                    = vlSelfRef.enc_s_tdata[3U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU] 
                    = vlSelfRef.enc_s_tdata[4U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU] 
                    = vlSelfRef.enc_s_tdata[5U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU] 
                    = vlSelfRef.enc_s_tdata[6U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU] 
                    = vlSelfRef.enc_s_tdata[7U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU] 
                    = vlSelfRef.enc_s_tdata[8U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep 
                    = ((vlSelfRef.enc_s_tkeep << 0x1cU) 
                       | (QData)((IData)(vlSelfRef.tb_top__DOT__encap__DOT__carry_keep)));
                if (vlSelfRef.enc_s_tlast) {
                    vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast 
                        = (1U & (~ (IData)(vlSelfRef.tb_top__DOT__encap__DOT__need_tail)));
                    if (vlSelfRef.tb_top__DOT__encap__DOT__need_tail) {
                        __Vdly__tb_top__DOT__encap__DOT__state = 2U;
                    } else {
                        __Vdly__tb_top__DOT__encap__DOT__stat_frames_out 
                            = ((IData)(1U) + vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out);
                        __Vdly__tb_top__DOT__encap__DOT__state = 0U;
                    }
                } else {
                    vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast = 0U;
                }
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[0U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[0U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[1U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[1U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[2U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[2U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[3U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[3U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[4U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[4U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[5U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[5U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[6U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[6U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_keep 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_keep;
            }
        } else if (vlSelfRef.enc_s_tvalid) {
            if (((IData)(vlSelfRef.enc_s_tuser) > (0xffffU 
                                                   & ((IData)(vlSelfRef.cfg_mtu) 
                                                      - (IData)(0xeU))))) {
                vlSelfRef.tb_top__DOT__encap__DOT__stat_oversize_drops 
                    = ((IData)(1U) + vlSelfRef.tb_top__DOT__encap__DOT__stat_oversize_drops);
                __Vdly__tb_top__DOT__encap__DOT__state = 3U;
            } else if (vlSelfRef.tb_top__DOT__encap__DOT__out_ready) {
                vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr 
                    = (0xffffU & ((IData)(1U) + (IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr)));
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid = 1U;
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[0U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[1U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[2U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[3U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[4U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[5U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[6U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[7U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[8U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__hdr[9U];
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU] 
                    = ((0xffff0000U & vlSelfRef.enc_s_tdata[3U]) 
                       | vlSelfRef.tb_top__DOT__encap__DOT__hdr[0xaU]);
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU] 
                    = ((0xffffU & vlSelfRef.enc_s_tdata[4U]) 
                       | (0xffff0000U & vlSelfRef.enc_s_tdata[4U]));
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU] 
                    = ((0xffffU & vlSelfRef.enc_s_tdata[5U]) 
                       | (0xffff0000U & vlSelfRef.enc_s_tdata[5U]));
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU] 
                    = ((0xffffU & vlSelfRef.enc_s_tdata[6U]) 
                       | (0xffff0000U & vlSelfRef.enc_s_tdata[6U]));
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU] 
                    = ((0xffffU & vlSelfRef.enc_s_tdata[7U]) 
                       | (0xffff0000U & vlSelfRef.enc_s_tdata[7U]));
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU] 
                    = ((0xffffU & vlSelfRef.enc_s_tdata[8U]) 
                       | (0xffff0000U & vlSelfRef.enc_s_tdata[8U]));
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep 
                    = (0x3ffffffffffULL | ((QData)((IData)(
                                                           (0x3fffffU 
                                                            & (IData)(
                                                                      (vlSelfRef.enc_s_tkeep 
                                                                       >> 0xeU))))) 
                                           << 0x2aU));
                vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size 
                    = (0xffffU & ((IData)(0x1cU) + (IData)(vlSelfRef.enc_s_tuser)));
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[0U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[0U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[1U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[1U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[2U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[2U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[3U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[3U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[4U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[4U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[5U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[5U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_data[6U] 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data[6U];
                vlSelfRef.tb_top__DOT__encap__DOT__carry_keep 
                    = vlSelfRef.tb_top__DOT__encap__DOT__next_carry_keep;
                if (vlSelfRef.enc_s_tlast) {
                    vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast 
                        = (1U & (~ (IData)(vlSelfRef.tb_top__DOT__encap__DOT__need_tail)));
                    if (vlSelfRef.tb_top__DOT__encap__DOT__need_tail) {
                        __Vdly__tb_top__DOT__encap__DOT__state = 2U;
                    } else {
                        __Vdly__tb_top__DOT__encap__DOT__stat_frames_out 
                            = ((IData)(1U) + vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out);
                        __Vdly__tb_top__DOT__encap__DOT__state = 0U;
                    }
                } else {
                    vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast = 0U;
                    __Vdly__tb_top__DOT__encap__DOT__state = 1U;
                }
            }
        }
        if (((IData)(vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid) 
             & (IData)(vlSelfRef.dec_m_tready))) {
            vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid = 0U;
        }
        if ((4U & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state))) {
            if ((2U & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state))) {
                __Vdly__tb_top__DOT__decap__DOT__state = 0U;
            } else if ((1U & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state))) {
                __Vdly__tb_top__DOT__decap__DOT__state = 0U;
            } else if (((IData)(vlSelfRef.tb_top__DOT__dec_in_tvalid) 
                        & (IData)(vlSelfRef.tb_top__DOT__dec_in_tlast))) {
                __Vdly__tb_top__DOT__decap__DOT__state = 0U;
            }
        } else if ((2U & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state))) {
            if ((1U & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state))) {
                if (vlSelfRef.tb_top__DOT__decap__DOT__out_ready) {
                    __Vdly__tb_top__DOT__decap__DOT__stat_frames_out 
                        = ((IData)(1U) + vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out);
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid = 1U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[0U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[1U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[1U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[2U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[2U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[3U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[3U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[4U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[4U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[5U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[5U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[6U] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[7U] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[8U] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[9U] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xaU] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xbU] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xcU] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xdU] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xeU] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xfU] = 0U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tkeep 
                        = (QData)((IData)(vlSelfRef.tb_top__DOT__decap__DOT__carry_keep));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast = 1U;
                    __Vdly__tb_top__DOT__decap__DOT__state = 0U;
                }
            } else if (((IData)(vlSelfRef.tb_top__DOT__decap__DOT__fire_in) 
                        & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__out_ready))) {
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid = 1U;
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[0U];
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[1U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[1U];
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[2U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[2U];
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[3U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[3U];
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[4U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[4U];
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[5U] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[0U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[0U]) 
                        << 0x10U) | vlSelfRef.tb_top__DOT__decap__DOT__carry_data[5U]);
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[6U] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[0U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[0U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[1U] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[1U]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[7U] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[1U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[1U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[2U] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[2U]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[8U] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[2U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[2U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[3U] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[3U]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[9U] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[3U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[3U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[4U] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[4U]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xaU] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[4U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[4U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[5U] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[5U]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xbU] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[5U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[5U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[6U] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[6U]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xcU] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[6U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[6U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[7U] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[7U]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xdU] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[7U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[7U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[8U] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[8U]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xeU] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[8U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[8U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[9U] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[9U]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xfU] 
                    = (((Vtop__ConstPool__CONST_hfcc3ede4_0[9U] 
                         & vlSelfRef.tb_top__DOT__dec_in_tdata[9U]) 
                        >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[0xaU] 
                                      & vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU]) 
                                     << 0x10U));
                vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tkeep 
                    = ((vlSelfRef.tb_top__DOT__dec_in_tkeep 
                        << 0x16U) | (QData)((IData)(vlSelfRef.tb_top__DOT__decap__DOT__carry_keep)));
                if (vlSelfRef.tb_top__DOT__dec_in_tlast) {
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast 
                        = (1U & (~ (IData)(vlSelfRef.tb_top__DOT__decap__DOT__need_tail)));
                    if (vlSelfRef.tb_top__DOT__decap__DOT__need_tail) {
                        __Vdly__tb_top__DOT__decap__DOT__state = 3U;
                    } else {
                        __Vdly__tb_top__DOT__decap__DOT__stat_frames_out 
                            = ((IData)(1U) + vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out);
                        __Vdly__tb_top__DOT__decap__DOT__state = 0U;
                    }
                } else {
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast = 0U;
                }
                __Vdly__tb_top__DOT__decap__DOT__carry_data[0U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[0U];
                __Vdly__tb_top__DOT__decap__DOT__carry_data[1U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[1U];
                __Vdly__tb_top__DOT__decap__DOT__carry_data[2U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[2U];
                __Vdly__tb_top__DOT__decap__DOT__carry_data[3U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[3U];
                __Vdly__tb_top__DOT__decap__DOT__carry_data[4U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[4U];
                __Vdly__tb_top__DOT__decap__DOT__carry_data[5U] 
                    = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[5U];
                __Vdly__tb_top__DOT__decap__DOT__carry_keep 
                    = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_keep;
            }
        } else if ((1U & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state))) {
            if (((IData)(vlSelfRef.tb_top__DOT__decap__DOT__fire_in) 
                 & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__out_ready))) {
                if (vlSelfRef.tb_top__DOT__decap__DOT__cksum_ok) {
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid = 1U;
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[0U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[1U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[1U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[2U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[2U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[3U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[3U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[4U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__carry_data[4U];
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[5U] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[0U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[0U]) 
                            << 0x10U) | vlSelfRef.tb_top__DOT__decap__DOT__carry_data[5U]);
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[6U] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[0U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[0U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[1U] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[1U]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[7U] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[1U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[1U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[2U] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[2U]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[8U] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[2U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[2U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[3U] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[3U]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[9U] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[3U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[3U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[4U] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[4U]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xaU] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[4U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[4U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[5U] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[5U]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xbU] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[5U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[5U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[6U] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[6U]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xcU] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[6U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[6U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[7U] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[7U]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xdU] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[7U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[7U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[8U] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[8U]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xeU] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[8U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[8U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[9U] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[9U]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xfU] 
                        = (((Vtop__ConstPool__CONST_hfcc3ede4_0[9U] 
                             & vlSelfRef.tb_top__DOT__dec_in_tdata[9U]) 
                            >> 0x10U) | ((Vtop__ConstPool__CONST_hfcc3ede4_0[0xaU] 
                                          & vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU]) 
                                         << 0x10U));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tkeep 
                        = ((vlSelfRef.tb_top__DOT__dec_in_tkeep 
                            << 0x16U) | (QData)((IData)(vlSelfRef.tb_top__DOT__decap__DOT__carry_keep)));
                    vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tuser_size 
                        = vlSelfRef.tb_top__DOT__decap__DOT__out_tuser_size;
                    if (vlSelfRef.tb_top__DOT__dec_in_tlast) {
                        vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast 
                            = (1U & (~ (IData)(vlSelfRef.tb_top__DOT__decap__DOT__need_tail)));
                        if (vlSelfRef.tb_top__DOT__decap__DOT__need_tail) {
                            __Vdly__tb_top__DOT__decap__DOT__state = 3U;
                        } else {
                            __Vdly__tb_top__DOT__decap__DOT__stat_frames_out 
                                = ((IData)(1U) + vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out);
                            __Vdly__tb_top__DOT__decap__DOT__state = 0U;
                        }
                    } else {
                        vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast = 0U;
                        __Vdly__tb_top__DOT__decap__DOT__state = 2U;
                    }
                    __Vdly__tb_top__DOT__decap__DOT__carry_data[0U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[0U];
                    __Vdly__tb_top__DOT__decap__DOT__carry_data[1U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[1U];
                    __Vdly__tb_top__DOT__decap__DOT__carry_data[2U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[2U];
                    __Vdly__tb_top__DOT__decap__DOT__carry_data[3U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[3U];
                    __Vdly__tb_top__DOT__decap__DOT__carry_data[4U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[4U];
                    __Vdly__tb_top__DOT__decap__DOT__carry_data[5U] 
                        = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[5U];
                    __Vdly__tb_top__DOT__decap__DOT__carry_keep 
                        = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_keep;
                } else {
                    __Vdly__tb_top__DOT__decap__DOT__stat_drops_bad_cksum 
                        = ((IData)(1U) + vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum);
                    __Vdly__tb_top__DOT__decap__DOT__state = 4U;
                }
            }
        } else if (vlSelfRef.tb_top__DOT__decap__DOT__fire_in) {
            vlSelfRef.tb_top__DOT__decap__DOT__tuser_size_r 
                = vlSelfRef.tb_top__DOT__dec_in_tuser_size;
            vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[0U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[0U];
            vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[1U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[1U];
            vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[2U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[2U];
            vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[3U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[3U];
            vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[4U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[4U];
            __Vdly__tb_top__DOT__decap__DOT__carry_data[0U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[0U];
            __Vdly__tb_top__DOT__decap__DOT__carry_data[1U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[1U];
            __Vdly__tb_top__DOT__decap__DOT__carry_data[2U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[2U];
            __Vdly__tb_top__DOT__decap__DOT__carry_data[3U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[3U];
            __Vdly__tb_top__DOT__decap__DOT__carry_data[4U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[4U];
            __Vdly__tb_top__DOT__decap__DOT__carry_data[5U] 
                = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[5U];
            __Vdly__tb_top__DOT__decap__DOT__carry_keep 
                = vlSelfRef.tb_top__DOT__decap__DOT__next_carry_keep;
            if ((0x45U != (IData)(vlSelfRef.tb_top__DOT__decap__DOT__b14_ver_ihl))) {
                __Vdly__tb_top__DOT__decap__DOT__stat_drops_bad_cksum 
                    = ((IData)(1U) + vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum);
                __Vdly__tb_top__DOT__decap__DOT__state = 4U;
            } else if ((0x11U != (IData)(vlSelfRef.tb_top__DOT__decap__DOT__b23_ip_proto))) {
                __Vdly__tb_top__DOT__decap__DOT__stat_drops_bad_cksum 
                    = ((IData)(1U) + vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum);
                __Vdly__tb_top__DOT__decap__DOT__state = 4U;
            } else if (((IData)(vlSelfRef.tb_top__DOT__decap__DOT__b34_udp_dport_beat0) 
                        != (IData)(vlSelfRef.cfg_udp_port))) {
                vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_port 
                    = ((IData)(1U) + vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_port);
                __Vdly__tb_top__DOT__decap__DOT__state = 4U;
            } else if (((IData)(vlSelfRef.tb_top__DOT__decap__DOT__b16_ip_len) 
                        > (IData)(vlSelfRef.cfg_mtu))) {
                vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_oversize 
                    = ((IData)(1U) + vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_oversize);
                __Vdly__tb_top__DOT__decap__DOT__state = 4U;
            } else if (vlSelfRef.tb_top__DOT__dec_in_tlast) {
                __Vdly__tb_top__DOT__decap__DOT__stat_drops_bad_cksum 
                    = ((IData)(1U) + vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum);
                __Vdly__tb_top__DOT__decap__DOT__state = 0U;
            } else {
                __Vdly__tb_top__DOT__decap__DOT__state = 1U;
            }
        }
    } else {
        vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid = 0U;
        vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr = 1U;
        __Vdly__tb_top__DOT__encap__DOT__stat_frames_out = 0U;
        vlSelfRef.tb_top__DOT__encap__DOT__stat_oversize_drops = 0U;
        __Vdly__tb_top__DOT__encap__DOT__state = 0U;
        vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid = 0U;
        __Vdly__tb_top__DOT__decap__DOT__stat_frames_out = 0U;
        __Vdly__tb_top__DOT__decap__DOT__stat_drops_bad_cksum = 0U;
        vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_port = 0U;
        vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_oversize = 0U;
        __Vdly__tb_top__DOT__decap__DOT__state = 0U;
    }
    vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out 
        = __Vdly__tb_top__DOT__encap__DOT__stat_frames_out;
    vlSelfRef.tb_top__DOT__encap__DOT__state = __Vdly__tb_top__DOT__encap__DOT__state;
    vlSelfRef.tb_top__DOT__decap__DOT__carry_data[0U] 
        = __Vdly__tb_top__DOT__decap__DOT__carry_data[0U];
    vlSelfRef.tb_top__DOT__decap__DOT__carry_data[1U] 
        = __Vdly__tb_top__DOT__decap__DOT__carry_data[1U];
    vlSelfRef.tb_top__DOT__decap__DOT__carry_data[2U] 
        = __Vdly__tb_top__DOT__decap__DOT__carry_data[2U];
    vlSelfRef.tb_top__DOT__decap__DOT__carry_data[3U] 
        = __Vdly__tb_top__DOT__decap__DOT__carry_data[3U];
    vlSelfRef.tb_top__DOT__decap__DOT__carry_data[4U] 
        = __Vdly__tb_top__DOT__decap__DOT__carry_data[4U];
    vlSelfRef.tb_top__DOT__decap__DOT__carry_data[5U] 
        = __Vdly__tb_top__DOT__decap__DOT__carry_data[5U];
    vlSelfRef.tb_top__DOT__decap__DOT__carry_keep = __Vdly__tb_top__DOT__decap__DOT__carry_keep;
    vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out 
        = __Vdly__tb_top__DOT__decap__DOT__stat_frames_out;
    vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum 
        = __Vdly__tb_top__DOT__decap__DOT__stat_drops_bad_cksum;
    vlSelfRef.tb_top__DOT__decap__DOT__state = __Vdly__tb_top__DOT__decap__DOT__state;
    vlSelfRef.stat_enc_frames_out = vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out;
    vlSelfRef.tb_top__DOT__stat_enc_frames_out = vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out;
    vlSelfRef.stat_enc_oversize = vlSelfRef.tb_top__DOT__encap__DOT__stat_oversize_drops;
    vlSelfRef.tb_top__DOT__stat_enc_oversize = vlSelfRef.tb_top__DOT__encap__DOT__stat_oversize_drops;
    vlSelfRef.enc_m_tlast = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast;
    vlSelfRef.tb_top__DOT__enc_m_tlast = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast;
    vlSelfRef.tb_top__DOT__enc_out_tlast = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast;
    vlSelfRef.enc_m_tuser = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size;
    vlSelfRef.tb_top__DOT__enc_m_tuser = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size;
    vlSelfRef.tb_top__DOT__enc_out_tuser_size = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size;
    vlSelfRef.enc_m_tkeep = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep;
    vlSelfRef.tb_top__DOT__enc_m_tkeep = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep;
    vlSelfRef.tb_top__DOT__enc_out_tkeep = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep;
    vlSelfRef.tb_top__DOT__encap__DOT__ck_sum = (0xfffffU 
                                                 & ((IData)(0xc511U) 
                                                    + 
                                                    ((((((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_len_comb) 
                                                         + (IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr)) 
                                                        + 
                                                        (vlSelfRef.cfg_local_ip 
                                                         >> 0x10U)) 
                                                       + 
                                                       (0xffffU 
                                                        & vlSelfRef.cfg_local_ip)) 
                                                      + 
                                                      (vlSelfRef.cfg_peer_ip 
                                                       >> 0x10U)) 
                                                     + 
                                                     (0xffffU 
                                                      & vlSelfRef.cfg_peer_ip))));
    vlSelfRef.tb_top__DOT__encap__DOT__ck_fold = (0x1ffffU 
                                                  & ((0xfU 
                                                      & (vlSelfRef.tb_top__DOT__encap__DOT__ck_sum 
                                                         >> 0x10U)) 
                                                     + 
                                                     (0xffffU 
                                                      & vlSelfRef.tb_top__DOT__encap__DOT__ck_sum)));
    vlSelfRef.tb_top__DOT__encap__DOT__ip_cksum = (0xffffU 
                                                   & (~ 
                                                      ((0x10000U 
                                                        & vlSelfRef.tb_top__DOT__encap__DOT__ck_fold)
                                                        ? 
                                                       ((IData)(1U) 
                                                        + vlSelfRef.tb_top__DOT__encap__DOT__ck_fold)
                                                        : vlSelfRef.tb_top__DOT__encap__DOT__ck_fold)));
    vlSelfRef.enc_m_tdata[0U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U];
    vlSelfRef.enc_m_tdata[1U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U];
    vlSelfRef.enc_m_tdata[2U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U];
    vlSelfRef.enc_m_tdata[3U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U];
    vlSelfRef.enc_m_tdata[4U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U];
    vlSelfRef.enc_m_tdata[5U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U];
    vlSelfRef.enc_m_tdata[6U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U];
    vlSelfRef.enc_m_tdata[7U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U];
    vlSelfRef.enc_m_tdata[8U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U];
    vlSelfRef.enc_m_tdata[9U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U];
    vlSelfRef.enc_m_tdata[0xaU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.enc_m_tdata[0xbU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.enc_m_tdata[0xcU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.enc_m_tdata[0xdU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.enc_m_tdata[0xeU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.enc_m_tdata[0xfU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[1U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[2U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[3U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[4U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[5U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[6U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[7U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[8U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[9U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xaU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xbU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xcU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xdU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xeU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.tb_top__DOT__enc_m_tdata[0xfU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[1U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[2U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[3U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[4U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[5U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[6U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[7U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[8U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[9U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xaU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xbU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xcU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xdU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xeU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.tb_top__DOT__enc_out_tdata[0xfU] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.enc_m_tvalid = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid;
    vlSelfRef.tb_top__DOT__enc_m_tvalid = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid;
    vlSelfRef.tb_top__DOT__enc_out_tvalid = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid;
    vlSelfRef.tb_top__DOT__decap__DOT__out_tuser_size 
        = (0xffffU & ((IData)(vlSelfRef.tb_top__DOT__decap__DOT__tuser_size_r) 
                      - (IData)(0x2aU)));
    vlSelfRef.stat_dec_frames_out = vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out;
    vlSelfRef.tb_top__DOT__stat_dec_frames_out = vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out;
    vlSelfRef.dec_m_tdata[0U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0U];
    vlSelfRef.dec_m_tdata[1U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[1U];
    vlSelfRef.dec_m_tdata[2U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[2U];
    vlSelfRef.dec_m_tdata[3U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[3U];
    vlSelfRef.dec_m_tdata[4U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[4U];
    vlSelfRef.dec_m_tdata[5U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[5U];
    vlSelfRef.dec_m_tdata[6U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[6U];
    vlSelfRef.dec_m_tdata[7U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[7U];
    vlSelfRef.dec_m_tdata[8U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[8U];
    vlSelfRef.dec_m_tdata[9U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[9U];
    vlSelfRef.dec_m_tdata[0xaU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.dec_m_tdata[0xbU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.dec_m_tdata[0xcU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.dec_m_tdata[0xdU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.dec_m_tdata[0xeU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.dec_m_tdata[0xfU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[1U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[1U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[2U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[2U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[3U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[3U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[4U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[4U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[5U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[5U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[6U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[6U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[7U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[7U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[8U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[8U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[9U] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[9U];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xaU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xaU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xbU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xbU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xcU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xcU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xdU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xdU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xeU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xeU];
    vlSelfRef.tb_top__DOT__dec_m_tdata[0xfU] = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata[0xfU];
    vlSelfRef.dec_m_tkeep = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tkeep;
    vlSelfRef.tb_top__DOT__dec_m_tkeep = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tkeep;
    vlSelfRef.dec_m_tlast = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast;
    vlSelfRef.tb_top__DOT__dec_m_tlast = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast;
    vlSelfRef.dec_m_tuser = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tuser_size;
    vlSelfRef.tb_top__DOT__dec_m_tuser = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tuser_size;
    vlSelfRef.stat_dec_bad_cksum = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum;
    vlSelfRef.tb_top__DOT__stat_dec_bad_cksum = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum;
    vlSelfRef.stat_dec_bad_port = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_port;
    vlSelfRef.tb_top__DOT__stat_dec_bad_port = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_port;
    vlSelfRef.stat_dec_oversize = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_oversize;
    vlSelfRef.tb_top__DOT__stat_dec_oversize = vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_oversize;
    vlSelfRef.tb_top__DOT__decap__DOT__vck_sum = (0xfffffU 
                                                  & ((((((((((0xffffU 
                                                              & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[0U]) 
                                                             + 
                                                             (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[0U] 
                                                              >> 0x10U)) 
                                                            + 
                                                            (0xffffU 
                                                             & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[1U])) 
                                                           + 
                                                           (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[1U] 
                                                            >> 0x10U)) 
                                                          + 
                                                          (0xffffU 
                                                           & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[2U])) 
                                                         + 
                                                         (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[2U] 
                                                          >> 0x10U)) 
                                                        + 
                                                        (0xffffU 
                                                         & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[3U])) 
                                                       + 
                                                       (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[3U] 
                                                        >> 0x10U)) 
                                                      + 
                                                      (0xffffU 
                                                       & vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[4U])) 
                                                     + 
                                                     (vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r[4U] 
                                                      >> 0x10U)));
    vlSelfRef.tb_top__DOT__decap__DOT__vck_fold = (0x1ffffU 
                                                   & ((0xfU 
                                                       & (vlSelfRef.tb_top__DOT__decap__DOT__vck_sum 
                                                          >> 0x10U)) 
                                                      + 
                                                      (0xffffU 
                                                       & vlSelfRef.tb_top__DOT__decap__DOT__vck_sum)));
    vlSelfRef.tb_top__DOT__decap__DOT__cksum_ok = (0xffffU 
                                                   == 
                                                   (0x1ffffU 
                                                    & ((0x10000U 
                                                        & vlSelfRef.tb_top__DOT__decap__DOT__vck_fold)
                                                        ? 
                                                       ((IData)(1U) 
                                                        + 
                                                        (0xffffU 
                                                         & vlSelfRef.tb_top__DOT__decap__DOT__vck_fold))
                                                        : 
                                                       (0xffffU 
                                                        & vlSelfRef.tb_top__DOT__decap__DOT__vck_fold))));
    vlSelfRef.dec_m_tvalid = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid;
    vlSelfRef.tb_top__DOT__dec_m_tvalid = vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid;
    vlSelfRef.tb_top__DOT__decap__DOT__out_ready = 
        (1U & ((~ (IData)(vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid)) 
               | (IData)(vlSelfRef.dec_m_tready)));
    if (vlSelfRef.tb_inject_mode) {
        vlSelfRef.tb_top__DOT__dec_in_tlast = vlSelfRef.dec_s_tlast;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tlast 
            = vlSelfRef.tb_top__DOT__dec_in_tlast;
        vlSelfRef.tb_top__DOT__dec_in_tuser_size = vlSelfRef.dec_s_tuser;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tuser_size 
            = vlSelfRef.tb_top__DOT__dec_in_tuser_size;
        vlSelfRef.tb_top__DOT__dec_in_tkeep = vlSelfRef.dec_s_tkeep;
    } else {
        vlSelfRef.tb_top__DOT__dec_in_tlast = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tlast 
            = vlSelfRef.tb_top__DOT__dec_in_tlast;
        vlSelfRef.tb_top__DOT__dec_in_tuser_size = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size;
        vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tuser_size 
            = vlSelfRef.tb_top__DOT__dec_in_tuser_size;
        vlSelfRef.tb_top__DOT__dec_in_tkeep = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep;
    }
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tkeep 
        = vlSelfRef.tb_top__DOT__dec_in_tkeep;
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_keep 
        = (0x3fffffU & (IData)((vlSelfRef.tb_top__DOT__dec_in_tkeep 
                                >> 0x2aU)));
    __Vtemp_13[0U] = (IData)((((QData)((IData)((0xffU 
                                                & (IData)(
                                                          (vlSelfRef.cfg_local_mac 
                                                           >> 0x20U))))) 
                               << 0x38U) | (((QData)((IData)(
                                                             (0xffU 
                                                              & (IData)(
                                                                        (vlSelfRef.cfg_local_mac 
                                                                         >> 0x28U))))) 
                                             << 0x30U) 
                                            | (((QData)((IData)(
                                                                (0xffU 
                                                                 & (IData)(vlSelfRef.cfg_peer_mac)))) 
                                                << 0x28U) 
                                               | (((QData)((IData)(
                                                                   (0xffU 
                                                                    & (IData)(
                                                                              (vlSelfRef.cfg_peer_mac 
                                                                               >> 8U))))) 
                                                   << 0x20U) 
                                                  | (QData)((IData)(
                                                                    (((IData)(
                                                                              (vlSelfRef.cfg_peer_mac 
                                                                               >> 0x10U)) 
                                                                      << 0x18U) 
                                                                     | ((0xff0000U 
                                                                         & ((IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x18U)) 
                                                                            << 0x10U)) 
                                                                        | ((0xff00U 
                                                                            & ((IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x20U)) 
                                                                               << 8U)) 
                                                                           | (0xffU 
                                                                              & (IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x28U)))))))))))));
    __Vtemp_13[1U] = (IData)(((((QData)((IData)((0xffU 
                                                 & (IData)(
                                                           (vlSelfRef.cfg_local_mac 
                                                            >> 0x20U))))) 
                                << 0x38U) | (((QData)((IData)(
                                                              (0xffU 
                                                               & (IData)(
                                                                         (vlSelfRef.cfg_local_mac 
                                                                          >> 0x28U))))) 
                                              << 0x30U) 
                                             | (((QData)((IData)(
                                                                 (0xffU 
                                                                  & (IData)(vlSelfRef.cfg_peer_mac)))) 
                                                 << 0x28U) 
                                                | (((QData)((IData)(
                                                                    (0xffU 
                                                                     & (IData)(
                                                                               (vlSelfRef.cfg_peer_mac 
                                                                                >> 8U))))) 
                                                    << 0x20U) 
                                                   | (QData)((IData)(
                                                                     (((IData)(
                                                                               (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x10U)) 
                                                                       << 0x18U) 
                                                                      | ((0xff0000U 
                                                                          & ((IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x18U)) 
                                                                             << 0x10U)) 
                                                                         | ((0xff00U 
                                                                             & ((IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x20U)) 
                                                                                << 8U)) 
                                                                            | (0xffU 
                                                                               & (IData)(
                                                                                (vlSelfRef.cfg_peer_mac 
                                                                                >> 0x28U)))))))))))) 
                              >> 0x20U));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[0U] = __Vtemp_13[0U];
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[1U] = __Vtemp_13[1U];
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[2U] = (((IData)(vlSelfRef.cfg_local_mac) 
                                                   << 0x18U) 
                                                  | ((0xff0000U 
                                                      & ((IData)(
                                                                 (vlSelfRef.cfg_local_mac 
                                                                  >> 8U)) 
                                                         << 0x10U)) 
                                                     | ((0xff00U 
                                                         & ((IData)(
                                                                    (vlSelfRef.cfg_local_mac 
                                                                     >> 0x10U)) 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & (IData)(
                                                                     (vlSelfRef.cfg_local_mac 
                                                                      >> 0x18U))))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[3U] = 0x450008U;
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[4U] = (((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr) 
                                                   << 0x18U) 
                                                  | ((0xff0000U 
                                                      & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr) 
                                                         << 8U)) 
                                                     | ((0xff00U 
                                                         & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_len_comb) 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_len_comb) 
                                                              >> 8U)))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[5U] = 0x11400040U;
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[6U] = ((0xff000000U 
                                                   & (vlSelfRef.cfg_local_ip 
                                                      << 8U)) 
                                                  | ((0xff0000U 
                                                      & (vlSelfRef.cfg_local_ip 
                                                         >> 8U)) 
                                                     | ((0xff00U 
                                                         & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_cksum) 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__ip_cksum) 
                                                              >> 8U)))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[7U] = ((0xff000000U 
                                                   & (vlSelfRef.cfg_peer_ip 
                                                      << 8U)) 
                                                  | ((0xff0000U 
                                                      & (vlSelfRef.cfg_peer_ip 
                                                         >> 8U)) 
                                                     | ((0xff00U 
                                                         & (vlSelfRef.cfg_local_ip 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & (vlSelfRef.cfg_local_ip 
                                                              >> 8U)))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[8U] = (((IData)(vlSelfRef.cfg_udp_port) 
                                                   << 0x18U) 
                                                  | ((0xff0000U 
                                                      & ((IData)(vlSelfRef.cfg_udp_port) 
                                                         << 8U)) 
                                                     | ((0xff00U 
                                                         & (vlSelfRef.cfg_peer_ip 
                                                            << 8U)) 
                                                        | (0xffU 
                                                           & (vlSelfRef.cfg_peer_ip 
                                                              >> 8U)))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[9U] = (((IData)(vlSelfRef.tb_top__DOT__encap__DOT__udp_len_comb) 
                                                   << 0x18U) 
                                                  | ((0xff0000U 
                                                      & ((IData)(vlSelfRef.tb_top__DOT__encap__DOT__udp_len_comb) 
                                                         << 8U)) 
                                                     | ((0xff00U 
                                                         & ((IData)(vlSelfRef.cfg_udp_port) 
                                                            << 8U)) 
                                                        | ((IData)(vlSelfRef.cfg_udp_port) 
                                                           >> 8U))));
    vlSelfRef.tb_top__DOT__encap__DOT__hdr[0xaU] = 0U;
    if (vlSelfRef.tb_inject_mode) {
        vlSelfRef.tb_top__DOT__dec_in_tdata[0U] = vlSelfRef.dec_s_tdata[0U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[1U] = vlSelfRef.dec_s_tdata[1U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[2U] = vlSelfRef.dec_s_tdata[2U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[3U] = vlSelfRef.dec_s_tdata[3U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[4U] = vlSelfRef.dec_s_tdata[4U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[5U] = vlSelfRef.dec_s_tdata[5U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[6U] = vlSelfRef.dec_s_tdata[6U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[7U] = vlSelfRef.dec_s_tdata[7U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[8U] = vlSelfRef.dec_s_tdata[8U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[9U] = vlSelfRef.dec_s_tdata[9U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU] = 
            vlSelfRef.dec_s_tdata[0xaU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU] = 
            vlSelfRef.dec_s_tdata[0xbU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU] = 
            vlSelfRef.dec_s_tdata[0xcU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU] = 
            vlSelfRef.dec_s_tdata[0xdU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU] = 
            vlSelfRef.dec_s_tdata[0xeU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU] = 
            vlSelfRef.dec_s_tdata[0xfU];
    } else {
        vlSelfRef.tb_top__DOT__dec_in_tdata[0U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[1U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[1U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[2U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[2U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[3U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[3U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[4U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[4U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[5U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[5U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[6U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[6U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[7U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[7U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[8U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[8U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[9U] = vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[9U];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xaU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xbU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xcU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xdU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xeU];
        vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU] = 
            vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata[0xfU];
    }
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[1U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[1U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[2U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[2U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[3U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[3U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[4U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[4U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[5U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[5U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[6U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[6U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[7U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[7U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[8U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[8U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[9U] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[9U];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xaU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xbU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xcU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xdU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xeU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU];
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata[0xfU] 
        = vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU];
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[0U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[4U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[3U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[1U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[5U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[4U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[2U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[6U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[5U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[3U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[7U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[6U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr[4U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[8U] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[7U] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[0U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xaU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[1U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xbU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[2U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xcU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[3U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xdU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[4U] 
        = ((vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU] 
            << 0x10U) | (vlSelfRef.tb_top__DOT__dec_in_tdata[0xeU] 
                         >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data[5U] 
        = (vlSelfRef.tb_top__DOT__dec_in_tdata[0xfU] 
           >> 0x10U);
    vlSelfRef.tb_top__DOT__decap__DOT__b14_ver_ihl 
        = (0xffU & (vlSelfRef.tb_top__DOT__dec_in_tdata[3U] 
                    >> 0x10U));
    vlSelfRef.tb_top__DOT__decap__DOT__b23_ip_proto 
        = (vlSelfRef.tb_top__DOT__dec_in_tdata[5U] 
           >> 0x18U);
    vlSelfRef.tb_top__DOT__decap__DOT__b34_udp_dport_beat0 
        = ((0xff00U & (vlSelfRef.tb_top__DOT__dec_in_tdata[9U] 
                       << 8U)) | (0xffU & (vlSelfRef.tb_top__DOT__dec_in_tdata[9U] 
                                           >> 8U)));
    vlSelfRef.tb_top__DOT__decap__DOT__b16_ip_len = 
        ((0xff00U & (vlSelfRef.tb_top__DOT__dec_in_tdata[4U] 
                     << 8U)) | (0xffU & (vlSelfRef.tb_top__DOT__dec_in_tdata[4U] 
                                         >> 8U)));
    vlSelfRef.tb_top__DOT__dec_in_tvalid = ((IData)(vlSelfRef.tb_inject_mode)
                                             ? (IData)(vlSelfRef.dec_s_tvalid)
                                             : (IData)(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid));
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tvalid 
        = vlSelfRef.tb_top__DOT__dec_in_tvalid;
    vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready 
        = ((3U != (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state)) 
           & ((4U == (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state)) 
              | ((IData)(vlSelfRef.tb_top__DOT__decap__DOT__out_ready) 
                 | ((0U == (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state)) 
                    | (1U == (IData)(vlSelfRef.tb_top__DOT__decap__DOT__state))))));
    vlSelfRef.tb_top__DOT__enc_out_tready = ((IData)(vlSelfRef.tb_inject_mode)
                                              ? (IData)(vlSelfRef.enc_m_tready)
                                              : (IData)(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready));
    vlSelfRef.tb_top__DOT__decap__DOT__need_tail = 
        (0U != vlSelfRef.tb_top__DOT__decap__DOT__next_carry_keep);
    vlSelfRef.tb_top__DOT__dec_in_tready = vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__decap__DOT__can_accept = vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__decap__DOT__fire_in = ((IData)(vlSelfRef.tb_top__DOT__dec_in_tvalid) 
                                                  & (IData)(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready));
    vlSelfRef.dec_s_tready = ((IData)(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready) 
                              & (IData)(vlSelfRef.tb_inject_mode));
    vlSelfRef.tb_top__DOT__dec_s_tready = vlSelfRef.dec_s_tready;
    vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tready 
        = vlSelfRef.tb_top__DOT__enc_out_tready;
    vlSelfRef.tb_top__DOT__encap__DOT__out_ready = 
        (1U & ((~ (IData)(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid)) 
               | (IData)(vlSelfRef.tb_top__DOT__enc_out_tready)));
    vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready 
        = ((3U == (IData)(vlSelfRef.tb_top__DOT__encap__DOT__state)) 
           | ((2U != (IData)(vlSelfRef.tb_top__DOT__encap__DOT__state)) 
              & (IData)(vlSelfRef.tb_top__DOT__encap__DOT__out_ready)));
    vlSelfRef.enc_s_tready = vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__enc_s_tready = vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__encap__DOT__can_accept = vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready;
    vlSelfRef.tb_top__DOT__encap__DOT__fire_in = ((IData)(vlSelfRef.enc_s_tvalid) 
                                                  & (IData)(vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready));
}

void Vtop___024root___eval_triggers__act(Vtop___024root* vlSelf);

bool Vtop___024root___eval_phase__act(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_phase__act\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Init
    VlTriggerVec<1> __VpreTriggered;
    CData/*0:0*/ __VactExecute;
    // Body
    Vtop___024root___eval_triggers__act(vlSelf);
    __VactExecute = vlSelfRef.__VactTriggered.any();
    if (__VactExecute) {
        __VpreTriggered.andNot(vlSelfRef.__VactTriggered, vlSelfRef.__VnbaTriggered);
        vlSelfRef.__VnbaTriggered.thisOr(vlSelfRef.__VactTriggered);
        Vtop___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

bool Vtop___024root___eval_phase__nba(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_phase__nba\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Init
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = vlSelfRef.__VnbaTriggered.any();
    if (__VnbaExecute) {
        Vtop___024root___eval_nba(vlSelf);
        vlSelfRef.__VnbaTriggered.clear();
    }
    return (__VnbaExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__ico(Vtop___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__nba(Vtop___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__act(Vtop___024root* vlSelf);
#endif  // VL_DEBUG

void Vtop___024root___eval(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Init
    IData/*31:0*/ __VicoIterCount;
    CData/*0:0*/ __VicoContinue;
    IData/*31:0*/ __VnbaIterCount;
    CData/*0:0*/ __VnbaContinue;
    // Body
    __VicoIterCount = 0U;
    vlSelfRef.__VicoFirstIteration = 1U;
    __VicoContinue = 1U;
    while (__VicoContinue) {
        if (VL_UNLIKELY((0x64U < __VicoIterCount))) {
#ifdef VL_DEBUG
            Vtop___024root___dump_triggers__ico(vlSelf);
#endif
            VL_FATAL_MT("/home/alex/mpi-shfs/fpga/open-nic-shell-tt-link/plugin/tt_link_udp_bridge/tb/tb_top.sv", 12, "", "Input combinational region did not converge.");
        }
        __VicoIterCount = ((IData)(1U) + __VicoIterCount);
        __VicoContinue = 0U;
        if (Vtop___024root___eval_phase__ico(vlSelf)) {
            __VicoContinue = 1U;
        }
        vlSelfRef.__VicoFirstIteration = 0U;
    }
    __VnbaIterCount = 0U;
    __VnbaContinue = 1U;
    while (__VnbaContinue) {
        if (VL_UNLIKELY((0x64U < __VnbaIterCount))) {
#ifdef VL_DEBUG
            Vtop___024root___dump_triggers__nba(vlSelf);
#endif
            VL_FATAL_MT("/home/alex/mpi-shfs/fpga/open-nic-shell-tt-link/plugin/tt_link_udp_bridge/tb/tb_top.sv", 12, "", "NBA region did not converge.");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        __VnbaContinue = 0U;
        vlSelfRef.__VactIterCount = 0U;
        vlSelfRef.__VactContinue = 1U;
        while (vlSelfRef.__VactContinue) {
            if (VL_UNLIKELY((0x64U < vlSelfRef.__VactIterCount))) {
#ifdef VL_DEBUG
                Vtop___024root___dump_triggers__act(vlSelf);
#endif
                VL_FATAL_MT("/home/alex/mpi-shfs/fpga/open-nic-shell-tt-link/plugin/tt_link_udp_bridge/tb/tb_top.sv", 12, "", "Active region did not converge.");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
            vlSelfRef.__VactContinue = 0U;
            if (Vtop___024root___eval_phase__act(vlSelf)) {
                vlSelfRef.__VactContinue = 1U;
            }
        }
        if (Vtop___024root___eval_phase__nba(vlSelf)) {
            __VnbaContinue = 1U;
        }
    }
}

#ifdef VL_DEBUG
void Vtop___024root___eval_debug_assertions(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_debug_assertions\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY((vlSelfRef.clk & 0xfeU))) {
        Verilated::overWidthError("clk");}
    if (VL_UNLIKELY((vlSelfRef.rst_n & 0xfeU))) {
        Verilated::overWidthError("rst_n");}
    if (VL_UNLIKELY((vlSelfRef.enc_s_tvalid & 0xfeU))) {
        Verilated::overWidthError("enc_s_tvalid");}
    if (VL_UNLIKELY((vlSelfRef.enc_s_tlast & 0xfeU))) {
        Verilated::overWidthError("enc_s_tlast");}
    if (VL_UNLIKELY((vlSelfRef.enc_m_tready & 0xfeU))) {
        Verilated::overWidthError("enc_m_tready");}
    if (VL_UNLIKELY((vlSelfRef.dec_s_tvalid & 0xfeU))) {
        Verilated::overWidthError("dec_s_tvalid");}
    if (VL_UNLIKELY((vlSelfRef.dec_s_tlast & 0xfeU))) {
        Verilated::overWidthError("dec_s_tlast");}
    if (VL_UNLIKELY((vlSelfRef.dec_m_tready & 0xfeU))) {
        Verilated::overWidthError("dec_m_tready");}
    if (VL_UNLIKELY((vlSelfRef.tb_inject_mode & 0xfeU))) {
        Verilated::overWidthError("tb_inject_mode");}
    if (VL_UNLIKELY((vlSelfRef.cfg_local_mac & 0ULL))) {
        Verilated::overWidthError("cfg_local_mac");}
    if (VL_UNLIKELY((vlSelfRef.cfg_peer_mac & 0ULL))) {
        Verilated::overWidthError("cfg_peer_mac");}
}
#endif  // VL_DEBUG
