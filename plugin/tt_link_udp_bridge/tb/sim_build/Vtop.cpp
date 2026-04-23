// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vtop__pch.h"
#include "verilated_fst_c.h"

//============================================================
// Constructors

Vtop::Vtop(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vtop__Syms(contextp(), _vcname__, this)}
    , clk{vlSymsp->TOP.clk}
    , rst_n{vlSymsp->TOP.rst_n}
    , enc_s_tvalid{vlSymsp->TOP.enc_s_tvalid}
    , enc_s_tlast{vlSymsp->TOP.enc_s_tlast}
    , enc_s_tready{vlSymsp->TOP.enc_s_tready}
    , enc_m_tvalid{vlSymsp->TOP.enc_m_tvalid}
    , enc_m_tlast{vlSymsp->TOP.enc_m_tlast}
    , enc_m_tready{vlSymsp->TOP.enc_m_tready}
    , dec_s_tvalid{vlSymsp->TOP.dec_s_tvalid}
    , dec_s_tlast{vlSymsp->TOP.dec_s_tlast}
    , dec_s_tready{vlSymsp->TOP.dec_s_tready}
    , dec_m_tvalid{vlSymsp->TOP.dec_m_tvalid}
    , dec_m_tlast{vlSymsp->TOP.dec_m_tlast}
    , dec_m_tready{vlSymsp->TOP.dec_m_tready}
    , tb_inject_mode{vlSymsp->TOP.tb_inject_mode}
    , enc_s_tuser{vlSymsp->TOP.enc_s_tuser}
    , enc_m_tuser{vlSymsp->TOP.enc_m_tuser}
    , dec_s_tuser{vlSymsp->TOP.dec_s_tuser}
    , dec_m_tuser{vlSymsp->TOP.dec_m_tuser}
    , cfg_udp_port{vlSymsp->TOP.cfg_udp_port}
    , cfg_mtu{vlSymsp->TOP.cfg_mtu}
    , enc_s_tdata{vlSymsp->TOP.enc_s_tdata}
    , enc_m_tdata{vlSymsp->TOP.enc_m_tdata}
    , dec_s_tdata{vlSymsp->TOP.dec_s_tdata}
    , dec_m_tdata{vlSymsp->TOP.dec_m_tdata}
    , cfg_local_ip{vlSymsp->TOP.cfg_local_ip}
    , cfg_peer_ip{vlSymsp->TOP.cfg_peer_ip}
    , stat_enc_frames_out{vlSymsp->TOP.stat_enc_frames_out}
    , stat_enc_oversize{vlSymsp->TOP.stat_enc_oversize}
    , stat_dec_frames_out{vlSymsp->TOP.stat_dec_frames_out}
    , stat_dec_bad_cksum{vlSymsp->TOP.stat_dec_bad_cksum}
    , stat_dec_bad_port{vlSymsp->TOP.stat_dec_bad_port}
    , stat_dec_oversize{vlSymsp->TOP.stat_dec_oversize}
    , enc_s_tkeep{vlSymsp->TOP.enc_s_tkeep}
    , enc_m_tkeep{vlSymsp->TOP.enc_m_tkeep}
    , dec_s_tkeep{vlSymsp->TOP.dec_s_tkeep}
    , dec_m_tkeep{vlSymsp->TOP.dec_m_tkeep}
    , cfg_local_mac{vlSymsp->TOP.cfg_local_mac}
    , cfg_peer_mac{vlSymsp->TOP.cfg_peer_mac}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
    contextp()->traceBaseModelCbAdd(
        [this](VerilatedTraceBaseC* tfp, int levels, int options) { traceBaseModel(tfp, levels, options); });
}

Vtop::Vtop(const char* _vcname__)
    : Vtop(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vtop::~Vtop() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vtop___024root___eval_debug_assertions(Vtop___024root* vlSelf);
#endif  // VL_DEBUG
void Vtop___024root___eval_static(Vtop___024root* vlSelf);
void Vtop___024root___eval_initial(Vtop___024root* vlSelf);
void Vtop___024root___eval_settle(Vtop___024root* vlSelf);
void Vtop___024root___eval(Vtop___024root* vlSelf);

void Vtop::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vtop::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vtop___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_activity = true;
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vtop___024root___eval_static(&(vlSymsp->TOP));
        Vtop___024root___eval_initial(&(vlSymsp->TOP));
        Vtop___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vtop___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vtop::eventsPending() { return false; }

uint64_t Vtop::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "%Error: No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vtop::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vtop___024root___eval_final(Vtop___024root* vlSelf);

VL_ATTR_COLD void Vtop::final() {
    Vtop___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vtop::hierName() const { return vlSymsp->name(); }
const char* Vtop::modelName() const { return "Vtop"; }
unsigned Vtop::threads() const { return 1; }
void Vtop::prepareClone() const { contextp()->prepareClone(); }
void Vtop::atClone() const {
    contextp()->threadPoolpOnClone();
}
std::unique_ptr<VerilatedTraceConfig> Vtop::traceConfig() const {
    return std::unique_ptr<VerilatedTraceConfig>{new VerilatedTraceConfig{false, false, false}};
};

//============================================================
// Trace configuration

void Vtop___024root__trace_decl_types(VerilatedFst* tracep);

void Vtop___024root__trace_init_top(Vtop___024root* vlSelf, VerilatedFst* tracep);

VL_ATTR_COLD static void trace_init(void* voidSelf, VerilatedFst* tracep, uint32_t code) {
    // Callback from tracep->open()
    Vtop___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtop___024root*>(voidSelf);
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    if (!vlSymsp->_vm_contextp__->calcUnusedSigs()) {
        VL_FATAL_MT(__FILE__, __LINE__, __FILE__,
            "Turning on wave traces requires Verilated::traceEverOn(true) call before time 0.");
    }
    vlSymsp->__Vm_baseCode = code;
    if (strlen(vlSymsp->name())) tracep->pushPrefix(std::string{vlSymsp->name()}, VerilatedTracePrefixType::SCOPE_MODULE);
    Vtop___024root__trace_decl_types(tracep);
    Vtop___024root__trace_init_top(vlSelf, tracep);
    if (strlen(vlSymsp->name())) tracep->popPrefix();
}

VL_ATTR_COLD void Vtop___024root__trace_register(Vtop___024root* vlSelf, VerilatedFst* tracep);

VL_ATTR_COLD void Vtop::traceBaseModel(VerilatedTraceBaseC* tfp, int levels, int options) {
    (void)levels; (void)options;
    VerilatedFstC* const stfp = dynamic_cast<VerilatedFstC*>(tfp);
    if (VL_UNLIKELY(!stfp)) {
        vl_fatal(__FILE__, __LINE__, __FILE__,"'Vtop::trace()' called on non-VerilatedFstC object;"
            " use --trace-fst with VerilatedFst object, and --trace with VerilatedVcd object");
    }
    stfp->spTrace()->addModel(this);
    stfp->spTrace()->addInitCb(&trace_init, &(vlSymsp->TOP));
    Vtop___024root__trace_register(&(vlSymsp->TOP), stfp->spTrace());
}
