// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Tracing implementation internals
#include "verilated_fst_c.h"
#include "Vtop__Syms.h"


void Vtop___024root__trace_chg_0_sub_0(Vtop___024root* vlSelf, VerilatedFst::Buffer* bufp);

void Vtop___024root__trace_chg_0(void* voidSelf, VerilatedFst::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_chg_0\n"); );
    // Init
    Vtop___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtop___024root*>(voidSelf);
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    if (VL_UNLIKELY(!vlSymsp->__Vm_activity)) return;
    // Body
    Vtop___024root__trace_chg_0_sub_0((&vlSymsp->TOP), bufp);
}

void Vtop___024root__trace_chg_0_sub_0(Vtop___024root* vlSelf, VerilatedFst::Buffer* bufp) {
    (void)vlSelf;  // Prevent unused variable warning
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_chg_0_sub_0\n"); );
    auto &vlSelfRef = std::ref(*vlSelf).get();
    // Init
    uint32_t* const oldp VL_ATTR_UNUSED = bufp->oldp(vlSymsp->__Vm_baseCode + 1);
    // Body
    bufp->chgBit(oldp+0,(vlSelfRef.clk));
    bufp->chgBit(oldp+1,(vlSelfRef.rst_n));
    bufp->chgBit(oldp+2,(vlSelfRef.enc_s_tvalid));
    bufp->chgWData(oldp+3,(vlSelfRef.enc_s_tdata),512);
    bufp->chgQData(oldp+19,(vlSelfRef.enc_s_tkeep),64);
    bufp->chgBit(oldp+21,(vlSelfRef.enc_s_tlast));
    bufp->chgSData(oldp+22,(vlSelfRef.enc_s_tuser),16);
    bufp->chgBit(oldp+23,(vlSelfRef.enc_s_tready));
    bufp->chgBit(oldp+24,(vlSelfRef.enc_m_tvalid));
    bufp->chgWData(oldp+25,(vlSelfRef.enc_m_tdata),512);
    bufp->chgQData(oldp+41,(vlSelfRef.enc_m_tkeep),64);
    bufp->chgBit(oldp+43,(vlSelfRef.enc_m_tlast));
    bufp->chgSData(oldp+44,(vlSelfRef.enc_m_tuser),16);
    bufp->chgBit(oldp+45,(vlSelfRef.enc_m_tready));
    bufp->chgBit(oldp+46,(vlSelfRef.dec_s_tvalid));
    bufp->chgWData(oldp+47,(vlSelfRef.dec_s_tdata),512);
    bufp->chgQData(oldp+63,(vlSelfRef.dec_s_tkeep),64);
    bufp->chgBit(oldp+65,(vlSelfRef.dec_s_tlast));
    bufp->chgSData(oldp+66,(vlSelfRef.dec_s_tuser),16);
    bufp->chgBit(oldp+67,(vlSelfRef.dec_s_tready));
    bufp->chgBit(oldp+68,(vlSelfRef.dec_m_tvalid));
    bufp->chgWData(oldp+69,(vlSelfRef.dec_m_tdata),512);
    bufp->chgQData(oldp+85,(vlSelfRef.dec_m_tkeep),64);
    bufp->chgBit(oldp+87,(vlSelfRef.dec_m_tlast));
    bufp->chgSData(oldp+88,(vlSelfRef.dec_m_tuser),16);
    bufp->chgBit(oldp+89,(vlSelfRef.dec_m_tready));
    bufp->chgBit(oldp+90,(vlSelfRef.tb_inject_mode));
    bufp->chgQData(oldp+91,(vlSelfRef.cfg_local_mac),48);
    bufp->chgQData(oldp+93,(vlSelfRef.cfg_peer_mac),48);
    bufp->chgIData(oldp+95,(vlSelfRef.cfg_local_ip),32);
    bufp->chgIData(oldp+96,(vlSelfRef.cfg_peer_ip),32);
    bufp->chgSData(oldp+97,(vlSelfRef.cfg_udp_port),16);
    bufp->chgSData(oldp+98,(vlSelfRef.cfg_mtu),16);
    bufp->chgIData(oldp+99,(vlSelfRef.stat_enc_frames_out),32);
    bufp->chgIData(oldp+100,(vlSelfRef.stat_enc_oversize),32);
    bufp->chgIData(oldp+101,(vlSelfRef.stat_dec_frames_out),32);
    bufp->chgIData(oldp+102,(vlSelfRef.stat_dec_bad_cksum),32);
    bufp->chgIData(oldp+103,(vlSelfRef.stat_dec_bad_port),32);
    bufp->chgIData(oldp+104,(vlSelfRef.stat_dec_oversize),32);
    bufp->chgBit(oldp+105,(vlSelfRef.tb_top__DOT__clk));
    bufp->chgBit(oldp+106,(vlSelfRef.tb_top__DOT__rst_n));
    bufp->chgBit(oldp+107,(vlSelfRef.tb_top__DOT__enc_s_tvalid));
    bufp->chgWData(oldp+108,(vlSelfRef.tb_top__DOT__enc_s_tdata),512);
    bufp->chgQData(oldp+124,(vlSelfRef.tb_top__DOT__enc_s_tkeep),64);
    bufp->chgBit(oldp+126,(vlSelfRef.tb_top__DOT__enc_s_tlast));
    bufp->chgSData(oldp+127,(vlSelfRef.tb_top__DOT__enc_s_tuser),16);
    bufp->chgBit(oldp+128,(vlSelfRef.tb_top__DOT__enc_s_tready));
    bufp->chgBit(oldp+129,(vlSelfRef.tb_top__DOT__enc_m_tvalid));
    bufp->chgWData(oldp+130,(vlSelfRef.tb_top__DOT__enc_m_tdata),512);
    bufp->chgQData(oldp+146,(vlSelfRef.tb_top__DOT__enc_m_tkeep),64);
    bufp->chgBit(oldp+148,(vlSelfRef.tb_top__DOT__enc_m_tlast));
    bufp->chgSData(oldp+149,(vlSelfRef.tb_top__DOT__enc_m_tuser),16);
    bufp->chgBit(oldp+150,(vlSelfRef.tb_top__DOT__enc_m_tready));
    bufp->chgBit(oldp+151,(vlSelfRef.tb_top__DOT__dec_s_tvalid));
    bufp->chgWData(oldp+152,(vlSelfRef.tb_top__DOT__dec_s_tdata),512);
    bufp->chgQData(oldp+168,(vlSelfRef.tb_top__DOT__dec_s_tkeep),64);
    bufp->chgBit(oldp+170,(vlSelfRef.tb_top__DOT__dec_s_tlast));
    bufp->chgSData(oldp+171,(vlSelfRef.tb_top__DOT__dec_s_tuser),16);
    bufp->chgBit(oldp+172,(vlSelfRef.tb_top__DOT__dec_s_tready));
    bufp->chgBit(oldp+173,(vlSelfRef.tb_top__DOT__dec_m_tvalid));
    bufp->chgWData(oldp+174,(vlSelfRef.tb_top__DOT__dec_m_tdata),512);
    bufp->chgQData(oldp+190,(vlSelfRef.tb_top__DOT__dec_m_tkeep),64);
    bufp->chgBit(oldp+192,(vlSelfRef.tb_top__DOT__dec_m_tlast));
    bufp->chgSData(oldp+193,(vlSelfRef.tb_top__DOT__dec_m_tuser),16);
    bufp->chgBit(oldp+194,(vlSelfRef.tb_top__DOT__dec_m_tready));
    bufp->chgBit(oldp+195,(vlSelfRef.tb_top__DOT__tb_inject_mode));
    bufp->chgQData(oldp+196,(vlSelfRef.tb_top__DOT__cfg_local_mac),48);
    bufp->chgQData(oldp+198,(vlSelfRef.tb_top__DOT__cfg_peer_mac),48);
    bufp->chgIData(oldp+200,(vlSelfRef.tb_top__DOT__cfg_local_ip),32);
    bufp->chgIData(oldp+201,(vlSelfRef.tb_top__DOT__cfg_peer_ip),32);
    bufp->chgSData(oldp+202,(vlSelfRef.tb_top__DOT__cfg_udp_port),16);
    bufp->chgSData(oldp+203,(vlSelfRef.tb_top__DOT__cfg_mtu),16);
    bufp->chgIData(oldp+204,(vlSelfRef.tb_top__DOT__stat_enc_frames_out),32);
    bufp->chgIData(oldp+205,(vlSelfRef.tb_top__DOT__stat_enc_oversize),32);
    bufp->chgIData(oldp+206,(vlSelfRef.tb_top__DOT__stat_dec_frames_out),32);
    bufp->chgIData(oldp+207,(vlSelfRef.tb_top__DOT__stat_dec_bad_cksum),32);
    bufp->chgIData(oldp+208,(vlSelfRef.tb_top__DOT__stat_dec_bad_port),32);
    bufp->chgIData(oldp+209,(vlSelfRef.tb_top__DOT__stat_dec_oversize),32);
    bufp->chgBit(oldp+210,(vlSelfRef.tb_top__DOT__enc_out_tvalid));
    bufp->chgWData(oldp+211,(vlSelfRef.tb_top__DOT__enc_out_tdata),512);
    bufp->chgQData(oldp+227,(vlSelfRef.tb_top__DOT__enc_out_tkeep),64);
    bufp->chgBit(oldp+229,(vlSelfRef.tb_top__DOT__enc_out_tlast));
    bufp->chgSData(oldp+230,(vlSelfRef.tb_top__DOT__enc_out_tuser_size),16);
    bufp->chgBit(oldp+231,(vlSelfRef.tb_top__DOT__enc_out_tready));
    bufp->chgBit(oldp+232,(vlSelfRef.tb_top__DOT__dec_in_tvalid));
    bufp->chgWData(oldp+233,(vlSelfRef.tb_top__DOT__dec_in_tdata),512);
    bufp->chgQData(oldp+249,(vlSelfRef.tb_top__DOT__dec_in_tkeep),64);
    bufp->chgBit(oldp+251,(vlSelfRef.tb_top__DOT__dec_in_tlast));
    bufp->chgSData(oldp+252,(vlSelfRef.tb_top__DOT__dec_in_tuser_size),16);
    bufp->chgBit(oldp+253,(vlSelfRef.tb_top__DOT__dec_in_tready));
    bufp->chgBit(oldp+254,(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tvalid));
    bufp->chgWData(oldp+255,(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tdata),512);
    bufp->chgQData(oldp+271,(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tkeep),64);
    bufp->chgBit(oldp+273,(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tlast));
    bufp->chgSData(oldp+274,(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tuser_size),16);
    bufp->chgBit(oldp+275,(vlSelfRef.tb_top__DOT__decap__DOT__s_axis_tready));
    bufp->chgBit(oldp+276,(vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tvalid));
    bufp->chgWData(oldp+277,(vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tdata),512);
    bufp->chgQData(oldp+293,(vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tkeep),64);
    bufp->chgBit(oldp+295,(vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tlast));
    bufp->chgSData(oldp+296,(vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tuser_size),16);
    bufp->chgBit(oldp+297,(vlSelfRef.tb_top__DOT__decap__DOT__m_axis_tready));
    bufp->chgIData(oldp+298,(vlSelfRef.tb_top__DOT__decap__DOT__cfg_local_ip),32);
    bufp->chgSData(oldp+299,(vlSelfRef.tb_top__DOT__decap__DOT__cfg_udp_port),16);
    bufp->chgSData(oldp+300,(vlSelfRef.tb_top__DOT__decap__DOT__cfg_mtu),16);
    bufp->chgIData(oldp+301,(vlSelfRef.tb_top__DOT__decap__DOT__stat_frames_out),32);
    bufp->chgIData(oldp+302,(vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_cksum),32);
    bufp->chgIData(oldp+303,(vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_bad_port),32);
    bufp->chgIData(oldp+304,(vlSelfRef.tb_top__DOT__decap__DOT__stat_drops_oversize),32);
    bufp->chgBit(oldp+305,(vlSelfRef.tb_top__DOT__decap__DOT__clk));
    bufp->chgBit(oldp+306,(vlSelfRef.tb_top__DOT__decap__DOT__rst_n));
    bufp->chgCData(oldp+307,(vlSelfRef.tb_top__DOT__decap__DOT__state),3);
    bufp->chgWData(oldp+308,(vlSelfRef.tb_top__DOT__decap__DOT__carry_data),176);
    bufp->chgIData(oldp+314,(vlSelfRef.tb_top__DOT__decap__DOT__carry_keep),22);
    bufp->chgWData(oldp+315,(vlSelfRef.tb_top__DOT__decap__DOT__ip_hdr_r),160);
    bufp->chgSData(oldp+320,(vlSelfRef.tb_top__DOT__decap__DOT__tuser_size_r),16);
    bufp->chgIData(oldp+321,(vlSelfRef.tb_top__DOT__decap__DOT__vck_sum),20);
    bufp->chgIData(oldp+322,(vlSelfRef.tb_top__DOT__decap__DOT__vck_fold),17);
    bufp->chgBit(oldp+323,(vlSelfRef.tb_top__DOT__decap__DOT__cksum_ok));
    bufp->chgCData(oldp+324,(vlSelfRef.tb_top__DOT__decap__DOT__b14_ver_ihl),8);
    bufp->chgWData(oldp+325,(vlSelfRef.tb_top__DOT__decap__DOT__b14_ip_hdr),160);
    bufp->chgSData(oldp+330,(vlSelfRef.tb_top__DOT__decap__DOT__b16_ip_len),16);
    bufp->chgCData(oldp+331,(vlSelfRef.tb_top__DOT__decap__DOT__b23_ip_proto),8);
    bufp->chgSData(oldp+332,(vlSelfRef.tb_top__DOT__decap__DOT__b34_udp_dport_beat0),16);
    bufp->chgBit(oldp+333,(vlSelfRef.tb_top__DOT__decap__DOT__out_ready));
    bufp->chgBit(oldp+334,(vlSelfRef.tb_top__DOT__decap__DOT__can_accept));
    bufp->chgBit(oldp+335,(vlSelfRef.tb_top__DOT__decap__DOT__fire_in));
    bufp->chgSData(oldp+336,(vlSelfRef.tb_top__DOT__decap__DOT__out_tuser_size),16);
    bufp->chgWData(oldp+337,(vlSelfRef.tb_top__DOT__decap__DOT__next_carry_data),176);
    bufp->chgIData(oldp+343,(vlSelfRef.tb_top__DOT__decap__DOT__next_carry_keep),22);
    bufp->chgBit(oldp+344,(vlSelfRef.tb_top__DOT__decap__DOT__need_tail));
    bufp->chgBit(oldp+345,(vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tvalid));
    bufp->chgWData(oldp+346,(vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tdata),512);
    bufp->chgQData(oldp+362,(vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tkeep),64);
    bufp->chgBit(oldp+364,(vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tlast));
    bufp->chgSData(oldp+365,(vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tuser_size),16);
    bufp->chgBit(oldp+366,(vlSelfRef.tb_top__DOT__encap__DOT__s_axis_tready));
    bufp->chgBit(oldp+367,(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tvalid));
    bufp->chgWData(oldp+368,(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tdata),512);
    bufp->chgQData(oldp+384,(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tkeep),64);
    bufp->chgBit(oldp+386,(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tlast));
    bufp->chgSData(oldp+387,(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tuser_size),16);
    bufp->chgBit(oldp+388,(vlSelfRef.tb_top__DOT__encap__DOT__m_axis_tready));
    bufp->chgQData(oldp+389,(vlSelfRef.tb_top__DOT__encap__DOT__cfg_local_mac),48);
    bufp->chgQData(oldp+391,(vlSelfRef.tb_top__DOT__encap__DOT__cfg_peer_mac),48);
    bufp->chgIData(oldp+393,(vlSelfRef.tb_top__DOT__encap__DOT__cfg_local_ip),32);
    bufp->chgIData(oldp+394,(vlSelfRef.tb_top__DOT__encap__DOT__cfg_peer_ip),32);
    bufp->chgSData(oldp+395,(vlSelfRef.tb_top__DOT__encap__DOT__cfg_udp_port),16);
    bufp->chgSData(oldp+396,(vlSelfRef.tb_top__DOT__encap__DOT__cfg_mtu),16);
    bufp->chgIData(oldp+397,(vlSelfRef.tb_top__DOT__encap__DOT__stat_frames_out),32);
    bufp->chgIData(oldp+398,(vlSelfRef.tb_top__DOT__encap__DOT__stat_oversize_drops),32);
    bufp->chgBit(oldp+399,(vlSelfRef.tb_top__DOT__encap__DOT__clk));
    bufp->chgBit(oldp+400,(vlSelfRef.tb_top__DOT__encap__DOT__rst_n));
    bufp->chgCData(oldp+401,(vlSelfRef.tb_top__DOT__encap__DOT__state),2);
    bufp->chgSData(oldp+402,(vlSelfRef.tb_top__DOT__encap__DOT__ip_id_ctr),16);
    bufp->chgSData(oldp+403,(vlSelfRef.tb_top__DOT__encap__DOT__ip_len_comb),16);
    bufp->chgSData(oldp+404,(vlSelfRef.tb_top__DOT__encap__DOT__udp_len_comb),16);
    bufp->chgWData(oldp+405,(vlSelfRef.tb_top__DOT__encap__DOT__carry_data),224);
    bufp->chgIData(oldp+412,(vlSelfRef.tb_top__DOT__encap__DOT__carry_keep),28);
    bufp->chgIData(oldp+413,(vlSelfRef.tb_top__DOT__encap__DOT__ck_sum),20);
    bufp->chgIData(oldp+414,(vlSelfRef.tb_top__DOT__encap__DOT__ck_fold),17);
    bufp->chgSData(oldp+415,(vlSelfRef.tb_top__DOT__encap__DOT__ip_cksum),16);
    bufp->chgWData(oldp+416,(vlSelfRef.tb_top__DOT__encap__DOT__hdr),336);
    bufp->chgBit(oldp+427,(vlSelfRef.tb_top__DOT__encap__DOT__out_ready));
    bufp->chgBit(oldp+428,(vlSelfRef.tb_top__DOT__encap__DOT__can_accept));
    bufp->chgBit(oldp+429,(vlSelfRef.tb_top__DOT__encap__DOT__fire_in));
    bufp->chgWData(oldp+430,(vlSelfRef.tb_top__DOT__encap__DOT__next_carry_data),224);
    bufp->chgIData(oldp+437,(vlSelfRef.tb_top__DOT__encap__DOT__next_carry_keep),28);
    bufp->chgBit(oldp+438,(vlSelfRef.tb_top__DOT__encap__DOT__need_tail));
}

void Vtop___024root__trace_cleanup(void* voidSelf, VerilatedFst* /*unused*/) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_cleanup\n"); );
    // Init
    Vtop___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtop___024root*>(voidSelf);
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VlUnpacked<CData/*0:0*/, 1> __Vm_traceActivity;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        __Vm_traceActivity[__Vi0] = 0;
    }
    // Body
    vlSymsp->__Vm_activity = false;
    __Vm_traceActivity[0U] = 0U;
}
