// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtop.h for the primary calling header

#include "Vtop__pch.h"
#include "Vtop___024root.h"

VL_ATTR_COLD void Vtop___024root___eval_static(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_static\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vtop___024root___eval_initial(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_initial\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
}

VL_ATTR_COLD void Vtop___024root___eval_final(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_final\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__stl(Vtop___024root* vlSelf);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vtop___024root___eval_phase__stl(Vtop___024root* vlSelf);

VL_ATTR_COLD void Vtop___024root___eval_settle(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_settle\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Init
    IData/*31:0*/ __VstlIterCount;
    CData/*0:0*/ __VstlContinue;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    __VstlContinue = 1U;
    while (__VstlContinue) {
        if (VL_UNLIKELY((0x64U < __VstlIterCount))) {
#ifdef VL_DEBUG
            Vtop___024root___dump_triggers__stl(vlSelf);
#endif
            VL_FATAL_MT("/home/alex/mpi-shfs/fpga/open-nic-shell-tt-link/plugin/tt_link_udp_bridge/tb/tb_top.sv", 12, "", "Settle region did not converge.");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
        __VstlContinue = 0U;
        if (Vtop___024root___eval_phase__stl(vlSelf)) {
            __VstlContinue = 1U;
        }
        vlSelfRef.__VstlFirstIteration = 0U;
    }
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__stl(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___dump_triggers__stl\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1U & (~ vlSelfRef.__VstlTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelfRef.__VstlTriggered.word(0U))) {
        VL_DBG_MSGF("         'stl' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

void Vtop___024root___ico_sequent__TOP__0(Vtop___024root* vlSelf);

VL_ATTR_COLD void Vtop___024root___eval_stl(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_stl\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VstlTriggered.word(0U))) {
        Vtop___024root___ico_sequent__TOP__0(vlSelf);
    }
}

VL_ATTR_COLD void Vtop___024root___eval_triggers__stl(Vtop___024root* vlSelf);

VL_ATTR_COLD bool Vtop___024root___eval_phase__stl(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___eval_phase__stl\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Init
    CData/*0:0*/ __VstlExecute;
    // Body
    Vtop___024root___eval_triggers__stl(vlSelf);
    __VstlExecute = vlSelfRef.__VstlTriggered.any();
    if (__VstlExecute) {
        Vtop___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__ico(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___dump_triggers__ico\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1U & (~ vlSelfRef.__VicoTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelfRef.__VicoTriggered.word(0U))) {
        VL_DBG_MSGF("         'ico' region trigger index 0 is active: Internal 'ico' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__act(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___dump_triggers__act\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1U & (~ vlSelfRef.__VactTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelfRef.__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 0 is active: @(posedge clk)\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtop___024root___dump_triggers__nba(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___dump_triggers__nba\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1U & (~ vlSelfRef.__VnbaTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 0 is active: @(posedge clk)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vtop___024root___ctor_var_reset(Vtop___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root___ctor_var_reset\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelf->clk = VL_RAND_RESET_I(1);
    vlSelf->rst_n = VL_RAND_RESET_I(1);
    vlSelf->enc_s_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->enc_s_tdata);
    vlSelf->enc_s_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->enc_s_tlast = VL_RAND_RESET_I(1);
    vlSelf->enc_s_tuser = VL_RAND_RESET_I(16);
    vlSelf->enc_s_tready = VL_RAND_RESET_I(1);
    vlSelf->enc_m_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->enc_m_tdata);
    vlSelf->enc_m_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->enc_m_tlast = VL_RAND_RESET_I(1);
    vlSelf->enc_m_tuser = VL_RAND_RESET_I(16);
    vlSelf->enc_m_tready = VL_RAND_RESET_I(1);
    vlSelf->dec_s_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->dec_s_tdata);
    vlSelf->dec_s_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->dec_s_tlast = VL_RAND_RESET_I(1);
    vlSelf->dec_s_tuser = VL_RAND_RESET_I(16);
    vlSelf->dec_s_tready = VL_RAND_RESET_I(1);
    vlSelf->dec_m_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->dec_m_tdata);
    vlSelf->dec_m_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->dec_m_tlast = VL_RAND_RESET_I(1);
    vlSelf->dec_m_tuser = VL_RAND_RESET_I(16);
    vlSelf->dec_m_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_inject_mode = VL_RAND_RESET_I(1);
    vlSelf->cfg_local_mac = VL_RAND_RESET_Q(48);
    vlSelf->cfg_peer_mac = VL_RAND_RESET_Q(48);
    vlSelf->cfg_local_ip = VL_RAND_RESET_I(32);
    vlSelf->cfg_peer_ip = VL_RAND_RESET_I(32);
    vlSelf->cfg_udp_port = VL_RAND_RESET_I(16);
    vlSelf->cfg_mtu = VL_RAND_RESET_I(16);
    vlSelf->stat_enc_frames_out = VL_RAND_RESET_I(32);
    vlSelf->stat_enc_oversize = VL_RAND_RESET_I(32);
    vlSelf->stat_dec_frames_out = VL_RAND_RESET_I(32);
    vlSelf->stat_dec_bad_cksum = VL_RAND_RESET_I(32);
    vlSelf->stat_dec_bad_port = VL_RAND_RESET_I(32);
    vlSelf->stat_dec_oversize = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__clk = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__rst_n = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__enc_s_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__enc_s_tdata);
    vlSelf->tb_top__DOT__enc_s_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__enc_s_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__enc_s_tuser = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__enc_s_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__enc_m_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__enc_m_tdata);
    vlSelf->tb_top__DOT__enc_m_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__enc_m_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__enc_m_tuser = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__enc_m_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__dec_s_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__dec_s_tdata);
    vlSelf->tb_top__DOT__dec_s_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__dec_s_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__dec_s_tuser = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__dec_s_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__dec_m_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__dec_m_tdata);
    vlSelf->tb_top__DOT__dec_m_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__dec_m_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__dec_m_tuser = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__dec_m_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__tb_inject_mode = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__cfg_local_mac = VL_RAND_RESET_Q(48);
    vlSelf->tb_top__DOT__cfg_peer_mac = VL_RAND_RESET_Q(48);
    vlSelf->tb_top__DOT__cfg_local_ip = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__cfg_peer_ip = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__cfg_udp_port = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__cfg_mtu = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__stat_enc_frames_out = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__stat_enc_oversize = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__stat_dec_frames_out = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__stat_dec_bad_cksum = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__stat_dec_bad_port = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__stat_dec_oversize = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__enc_out_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__enc_out_tdata);
    vlSelf->tb_top__DOT__enc_out_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__enc_out_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__enc_out_tuser_size = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__enc_out_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__dec_in_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__dec_in_tdata);
    vlSelf->tb_top__DOT__dec_in_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__dec_in_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__dec_in_tuser_size = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__dec_in_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__encap__DOT__s_axis_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__encap__DOT__s_axis_tdata);
    vlSelf->tb_top__DOT__encap__DOT__s_axis_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__encap__DOT__s_axis_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__encap__DOT__s_axis_tuser_size = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__encap__DOT__s_axis_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__encap__DOT__m_axis_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__encap__DOT__m_axis_tdata);
    vlSelf->tb_top__DOT__encap__DOT__m_axis_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__encap__DOT__m_axis_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__encap__DOT__m_axis_tuser_size = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__encap__DOT__m_axis_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__encap__DOT__cfg_local_mac = VL_RAND_RESET_Q(48);
    vlSelf->tb_top__DOT__encap__DOT__cfg_peer_mac = VL_RAND_RESET_Q(48);
    vlSelf->tb_top__DOT__encap__DOT__cfg_local_ip = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__encap__DOT__cfg_peer_ip = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__encap__DOT__cfg_udp_port = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__encap__DOT__cfg_mtu = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__encap__DOT__stat_frames_out = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__encap__DOT__stat_oversize_drops = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__encap__DOT__clk = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__encap__DOT__rst_n = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__encap__DOT__state = VL_RAND_RESET_I(2);
    vlSelf->tb_top__DOT__encap__DOT__ip_id_ctr = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__encap__DOT__ip_len_comb = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__encap__DOT__udp_len_comb = VL_RAND_RESET_I(16);
    VL_RAND_RESET_W(224, vlSelf->tb_top__DOT__encap__DOT__carry_data);
    vlSelf->tb_top__DOT__encap__DOT__carry_keep = VL_RAND_RESET_I(28);
    vlSelf->tb_top__DOT__encap__DOT__ck_sum = VL_RAND_RESET_I(20);
    vlSelf->tb_top__DOT__encap__DOT__ck_fold = VL_RAND_RESET_I(17);
    vlSelf->tb_top__DOT__encap__DOT__ip_cksum = VL_RAND_RESET_I(16);
    VL_RAND_RESET_W(336, vlSelf->tb_top__DOT__encap__DOT__hdr);
    vlSelf->tb_top__DOT__encap__DOT__out_ready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__encap__DOT__can_accept = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__encap__DOT__fire_in = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(224, vlSelf->tb_top__DOT__encap__DOT__next_carry_data);
    vlSelf->tb_top__DOT__encap__DOT__next_carry_keep = VL_RAND_RESET_I(28);
    vlSelf->tb_top__DOT__encap__DOT__need_tail = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__s_axis_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__decap__DOT__s_axis_tdata);
    vlSelf->tb_top__DOT__decap__DOT__s_axis_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__decap__DOT__s_axis_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__s_axis_tuser_size = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__decap__DOT__s_axis_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__m_axis_tvalid = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(512, vlSelf->tb_top__DOT__decap__DOT__m_axis_tdata);
    vlSelf->tb_top__DOT__decap__DOT__m_axis_tkeep = VL_RAND_RESET_Q(64);
    vlSelf->tb_top__DOT__decap__DOT__m_axis_tlast = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__m_axis_tuser_size = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__decap__DOT__m_axis_tready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__cfg_local_ip = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__decap__DOT__cfg_udp_port = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__decap__DOT__cfg_mtu = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__decap__DOT__stat_frames_out = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__decap__DOT__stat_drops_bad_cksum = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__decap__DOT__stat_drops_bad_port = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__decap__DOT__stat_drops_oversize = VL_RAND_RESET_I(32);
    vlSelf->tb_top__DOT__decap__DOT__clk = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__rst_n = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__state = VL_RAND_RESET_I(3);
    VL_RAND_RESET_W(176, vlSelf->tb_top__DOT__decap__DOT__carry_data);
    vlSelf->tb_top__DOT__decap__DOT__carry_keep = VL_RAND_RESET_I(22);
    VL_RAND_RESET_W(160, vlSelf->tb_top__DOT__decap__DOT__ip_hdr_r);
    vlSelf->tb_top__DOT__decap__DOT__tuser_size_r = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__decap__DOT__vck_sum = VL_RAND_RESET_I(20);
    vlSelf->tb_top__DOT__decap__DOT__vck_fold = VL_RAND_RESET_I(17);
    vlSelf->tb_top__DOT__decap__DOT__cksum_ok = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__b14_ver_ihl = VL_RAND_RESET_I(8);
    VL_RAND_RESET_W(160, vlSelf->tb_top__DOT__decap__DOT__b14_ip_hdr);
    vlSelf->tb_top__DOT__decap__DOT__b16_ip_len = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__decap__DOT__b23_ip_proto = VL_RAND_RESET_I(8);
    vlSelf->tb_top__DOT__decap__DOT__b34_udp_dport_beat0 = VL_RAND_RESET_I(16);
    vlSelf->tb_top__DOT__decap__DOT__out_ready = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__can_accept = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__fire_in = VL_RAND_RESET_I(1);
    vlSelf->tb_top__DOT__decap__DOT__out_tuser_size = VL_RAND_RESET_I(16);
    VL_RAND_RESET_W(176, vlSelf->tb_top__DOT__decap__DOT__next_carry_data);
    vlSelf->tb_top__DOT__decap__DOT__next_carry_keep = VL_RAND_RESET_I(22);
    vlSelf->tb_top__DOT__decap__DOT__need_tail = VL_RAND_RESET_I(1);
    vlSelf->__Vtrigprevexpr___TOP__clk__0 = VL_RAND_RESET_I(1);
}
