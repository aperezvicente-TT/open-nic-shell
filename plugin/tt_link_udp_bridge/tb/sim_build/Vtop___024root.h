// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtop.h for the primary calling header

#ifndef VERILATED_VTOP___024ROOT_H_
#define VERILATED_VTOP___024ROOT_H_  // guard

#include "verilated.h"


class Vtop__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtop___024root final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    // Anonymous structures to workaround compiler member-count bugs
    struct {
        VL_IN8(clk,0,0);
        VL_IN8(rst_n,0,0);
        VL_IN8(enc_s_tvalid,0,0);
        VL_IN8(enc_s_tlast,0,0);
        VL_OUT8(enc_s_tready,0,0);
        VL_OUT8(enc_m_tvalid,0,0);
        VL_OUT8(enc_m_tlast,0,0);
        VL_IN8(enc_m_tready,0,0);
        VL_IN8(dec_s_tvalid,0,0);
        VL_IN8(dec_s_tlast,0,0);
        VL_OUT8(dec_s_tready,0,0);
        VL_OUT8(dec_m_tvalid,0,0);
        VL_OUT8(dec_m_tlast,0,0);
        VL_IN8(dec_m_tready,0,0);
        VL_IN8(tb_inject_mode,0,0);
        CData/*0:0*/ tb_top__DOT__clk;
        CData/*0:0*/ tb_top__DOT__rst_n;
        CData/*0:0*/ tb_top__DOT__enc_s_tvalid;
        CData/*0:0*/ tb_top__DOT__enc_s_tlast;
        CData/*0:0*/ tb_top__DOT__enc_s_tready;
        CData/*0:0*/ tb_top__DOT__enc_m_tvalid;
        CData/*0:0*/ tb_top__DOT__enc_m_tlast;
        CData/*0:0*/ tb_top__DOT__enc_m_tready;
        CData/*0:0*/ tb_top__DOT__dec_s_tvalid;
        CData/*0:0*/ tb_top__DOT__dec_s_tlast;
        CData/*0:0*/ tb_top__DOT__dec_s_tready;
        CData/*0:0*/ tb_top__DOT__dec_m_tvalid;
        CData/*0:0*/ tb_top__DOT__dec_m_tlast;
        CData/*0:0*/ tb_top__DOT__dec_m_tready;
        CData/*0:0*/ tb_top__DOT__tb_inject_mode;
        CData/*0:0*/ tb_top__DOT__enc_out_tvalid;
        CData/*0:0*/ tb_top__DOT__enc_out_tlast;
        CData/*0:0*/ tb_top__DOT__enc_out_tready;
        CData/*0:0*/ tb_top__DOT__dec_in_tvalid;
        CData/*0:0*/ tb_top__DOT__dec_in_tlast;
        CData/*0:0*/ tb_top__DOT__dec_in_tready;
        CData/*0:0*/ tb_top__DOT__encap__DOT__s_axis_tvalid;
        CData/*0:0*/ tb_top__DOT__encap__DOT__s_axis_tlast;
        CData/*0:0*/ tb_top__DOT__encap__DOT__s_axis_tready;
        CData/*0:0*/ tb_top__DOT__encap__DOT__m_axis_tvalid;
        CData/*0:0*/ tb_top__DOT__encap__DOT__m_axis_tlast;
        CData/*0:0*/ tb_top__DOT__encap__DOT__m_axis_tready;
        CData/*0:0*/ tb_top__DOT__encap__DOT__clk;
        CData/*0:0*/ tb_top__DOT__encap__DOT__rst_n;
        CData/*1:0*/ tb_top__DOT__encap__DOT__state;
        CData/*0:0*/ tb_top__DOT__encap__DOT__out_ready;
        CData/*0:0*/ tb_top__DOT__encap__DOT__can_accept;
        CData/*0:0*/ tb_top__DOT__encap__DOT__fire_in;
        CData/*0:0*/ tb_top__DOT__encap__DOT__need_tail;
        CData/*0:0*/ tb_top__DOT__decap__DOT__s_axis_tvalid;
        CData/*0:0*/ tb_top__DOT__decap__DOT__s_axis_tlast;
        CData/*0:0*/ tb_top__DOT__decap__DOT__s_axis_tready;
        CData/*0:0*/ tb_top__DOT__decap__DOT__m_axis_tvalid;
        CData/*0:0*/ tb_top__DOT__decap__DOT__m_axis_tlast;
        CData/*0:0*/ tb_top__DOT__decap__DOT__m_axis_tready;
        CData/*0:0*/ tb_top__DOT__decap__DOT__clk;
        CData/*0:0*/ tb_top__DOT__decap__DOT__rst_n;
        CData/*2:0*/ tb_top__DOT__decap__DOT__state;
        CData/*0:0*/ tb_top__DOT__decap__DOT__cksum_ok;
        CData/*7:0*/ tb_top__DOT__decap__DOT__b14_ver_ihl;
        CData/*7:0*/ tb_top__DOT__decap__DOT__b23_ip_proto;
        CData/*0:0*/ tb_top__DOT__decap__DOT__out_ready;
        CData/*0:0*/ tb_top__DOT__decap__DOT__can_accept;
        CData/*0:0*/ tb_top__DOT__decap__DOT__fire_in;
    };
    struct {
        CData/*0:0*/ tb_top__DOT__decap__DOT__need_tail;
        CData/*0:0*/ __VstlFirstIteration;
        CData/*0:0*/ __VicoFirstIteration;
        CData/*0:0*/ __Vtrigprevexpr___TOP__clk__0;
        CData/*0:0*/ __VactContinue;
        VL_IN16(enc_s_tuser,15,0);
        VL_OUT16(enc_m_tuser,15,0);
        VL_IN16(dec_s_tuser,15,0);
        VL_OUT16(dec_m_tuser,15,0);
        VL_IN16(cfg_udp_port,15,0);
        VL_IN16(cfg_mtu,15,0);
        SData/*15:0*/ tb_top__DOT__enc_s_tuser;
        SData/*15:0*/ tb_top__DOT__enc_m_tuser;
        SData/*15:0*/ tb_top__DOT__dec_s_tuser;
        SData/*15:0*/ tb_top__DOT__dec_m_tuser;
        SData/*15:0*/ tb_top__DOT__cfg_udp_port;
        SData/*15:0*/ tb_top__DOT__cfg_mtu;
        SData/*15:0*/ tb_top__DOT__enc_out_tuser_size;
        SData/*15:0*/ tb_top__DOT__dec_in_tuser_size;
        SData/*15:0*/ tb_top__DOT__encap__DOT__s_axis_tuser_size;
        SData/*15:0*/ tb_top__DOT__encap__DOT__m_axis_tuser_size;
        SData/*15:0*/ tb_top__DOT__encap__DOT__cfg_udp_port;
        SData/*15:0*/ tb_top__DOT__encap__DOT__cfg_mtu;
        SData/*15:0*/ tb_top__DOT__encap__DOT__ip_id_ctr;
        SData/*15:0*/ tb_top__DOT__encap__DOT__ip_len_comb;
        SData/*15:0*/ tb_top__DOT__encap__DOT__udp_len_comb;
        SData/*15:0*/ tb_top__DOT__encap__DOT__ip_cksum;
        SData/*15:0*/ tb_top__DOT__decap__DOT__s_axis_tuser_size;
        SData/*15:0*/ tb_top__DOT__decap__DOT__m_axis_tuser_size;
        SData/*15:0*/ tb_top__DOT__decap__DOT__cfg_udp_port;
        SData/*15:0*/ tb_top__DOT__decap__DOT__cfg_mtu;
        SData/*15:0*/ tb_top__DOT__decap__DOT__tuser_size_r;
        SData/*15:0*/ tb_top__DOT__decap__DOT__b16_ip_len;
        SData/*15:0*/ tb_top__DOT__decap__DOT__b34_udp_dport_beat0;
        SData/*15:0*/ tb_top__DOT__decap__DOT__out_tuser_size;
        VL_INW(enc_s_tdata,511,0,16);
        VL_OUTW(enc_m_tdata,511,0,16);
        VL_INW(dec_s_tdata,511,0,16);
        VL_OUTW(dec_m_tdata,511,0,16);
        VL_IN(cfg_local_ip,31,0);
        VL_IN(cfg_peer_ip,31,0);
        VL_OUT(stat_enc_frames_out,31,0);
        VL_OUT(stat_enc_oversize,31,0);
        VL_OUT(stat_dec_frames_out,31,0);
        VL_OUT(stat_dec_bad_cksum,31,0);
        VL_OUT(stat_dec_bad_port,31,0);
        VL_OUT(stat_dec_oversize,31,0);
        VlWide<16>/*511:0*/ tb_top__DOT__enc_s_tdata;
        VlWide<16>/*511:0*/ tb_top__DOT__enc_m_tdata;
        VlWide<16>/*511:0*/ tb_top__DOT__dec_s_tdata;
        VlWide<16>/*511:0*/ tb_top__DOT__dec_m_tdata;
        IData/*31:0*/ tb_top__DOT__cfg_local_ip;
        IData/*31:0*/ tb_top__DOT__cfg_peer_ip;
        IData/*31:0*/ tb_top__DOT__stat_enc_frames_out;
        IData/*31:0*/ tb_top__DOT__stat_enc_oversize;
        IData/*31:0*/ tb_top__DOT__stat_dec_frames_out;
        IData/*31:0*/ tb_top__DOT__stat_dec_bad_cksum;
        IData/*31:0*/ tb_top__DOT__stat_dec_bad_port;
        IData/*31:0*/ tb_top__DOT__stat_dec_oversize;
        VlWide<16>/*511:0*/ tb_top__DOT__enc_out_tdata;
        VlWide<16>/*511:0*/ tb_top__DOT__dec_in_tdata;
        VlWide<16>/*511:0*/ tb_top__DOT__encap__DOT__s_axis_tdata;
        VlWide<16>/*511:0*/ tb_top__DOT__encap__DOT__m_axis_tdata;
        IData/*31:0*/ tb_top__DOT__encap__DOT__cfg_local_ip;
    };
    struct {
        IData/*31:0*/ tb_top__DOT__encap__DOT__cfg_peer_ip;
        IData/*31:0*/ tb_top__DOT__encap__DOT__stat_frames_out;
        IData/*31:0*/ tb_top__DOT__encap__DOT__stat_oversize_drops;
        VlWide<7>/*223:0*/ tb_top__DOT__encap__DOT__carry_data;
        IData/*27:0*/ tb_top__DOT__encap__DOT__carry_keep;
        IData/*19:0*/ tb_top__DOT__encap__DOT__ck_sum;
        IData/*16:0*/ tb_top__DOT__encap__DOT__ck_fold;
        VlWide<11>/*335:0*/ tb_top__DOT__encap__DOT__hdr;
        VlWide<7>/*223:0*/ tb_top__DOT__encap__DOT__next_carry_data;
        IData/*27:0*/ tb_top__DOT__encap__DOT__next_carry_keep;
        VlWide<16>/*511:0*/ tb_top__DOT__decap__DOT__s_axis_tdata;
        VlWide<16>/*511:0*/ tb_top__DOT__decap__DOT__m_axis_tdata;
        IData/*31:0*/ tb_top__DOT__decap__DOT__cfg_local_ip;
        IData/*31:0*/ tb_top__DOT__decap__DOT__stat_frames_out;
        IData/*31:0*/ tb_top__DOT__decap__DOT__stat_drops_bad_cksum;
        IData/*31:0*/ tb_top__DOT__decap__DOT__stat_drops_bad_port;
        IData/*31:0*/ tb_top__DOT__decap__DOT__stat_drops_oversize;
        VlWide<6>/*175:0*/ tb_top__DOT__decap__DOT__carry_data;
        IData/*21:0*/ tb_top__DOT__decap__DOT__carry_keep;
        VlWide<5>/*159:0*/ tb_top__DOT__decap__DOT__ip_hdr_r;
        IData/*19:0*/ tb_top__DOT__decap__DOT__vck_sum;
        IData/*16:0*/ tb_top__DOT__decap__DOT__vck_fold;
        VlWide<5>/*159:0*/ tb_top__DOT__decap__DOT__b14_ip_hdr;
        VlWide<6>/*175:0*/ tb_top__DOT__decap__DOT__next_carry_data;
        IData/*21:0*/ tb_top__DOT__decap__DOT__next_carry_keep;
        IData/*31:0*/ __VactIterCount;
        VL_IN64(enc_s_tkeep,63,0);
        VL_OUT64(enc_m_tkeep,63,0);
        VL_IN64(dec_s_tkeep,63,0);
        VL_OUT64(dec_m_tkeep,63,0);
        VL_IN64(cfg_local_mac,47,0);
        VL_IN64(cfg_peer_mac,47,0);
        QData/*63:0*/ tb_top__DOT__enc_s_tkeep;
        QData/*63:0*/ tb_top__DOT__enc_m_tkeep;
        QData/*63:0*/ tb_top__DOT__dec_s_tkeep;
        QData/*63:0*/ tb_top__DOT__dec_m_tkeep;
        QData/*47:0*/ tb_top__DOT__cfg_local_mac;
        QData/*47:0*/ tb_top__DOT__cfg_peer_mac;
        QData/*63:0*/ tb_top__DOT__enc_out_tkeep;
        QData/*63:0*/ tb_top__DOT__dec_in_tkeep;
        QData/*63:0*/ tb_top__DOT__encap__DOT__s_axis_tkeep;
        QData/*63:0*/ tb_top__DOT__encap__DOT__m_axis_tkeep;
        QData/*47:0*/ tb_top__DOT__encap__DOT__cfg_local_mac;
        QData/*47:0*/ tb_top__DOT__encap__DOT__cfg_peer_mac;
        QData/*63:0*/ tb_top__DOT__decap__DOT__s_axis_tkeep;
        QData/*63:0*/ tb_top__DOT__decap__DOT__m_axis_tkeep;
    };
    VlTriggerVec<1> __VstlTriggered;
    VlTriggerVec<1> __VicoTriggered;
    VlTriggerVec<1> __VactTriggered;
    VlTriggerVec<1> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vtop__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vtop___024root(Vtop__Syms* symsp, const char* v__name);
    ~Vtop___024root();
    VL_UNCOPYABLE(Vtop___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
