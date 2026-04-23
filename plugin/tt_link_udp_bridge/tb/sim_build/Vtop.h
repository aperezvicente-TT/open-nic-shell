// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Primary model header
//
// This header should be included by all source files instantiating the design.
// The class here is then constructed to instantiate the design.
// See the Verilator manual for examples.

#ifndef VERILATED_VTOP_H_
#define VERILATED_VTOP_H_  // guard

#include "verilated.h"
#include "svdpi.h"

class Vtop__Syms;
class Vtop___024root;
class VerilatedFstC;

// This class is the main interface to the Verilated model
class alignas(VL_CACHE_LINE_BYTES) Vtop VL_NOT_FINAL : public VerilatedModel {
  private:
    // Symbol table holding complete model state (owned by this class)
    Vtop__Syms* const vlSymsp;

  public:

    // CONSTEXPR CAPABILITIES
    // Verilated with --trace?
    static constexpr bool traceCapable = true;

    // PORTS
    // The application code writes and reads these signals to
    // propagate new values into/out from the Verilated model.
    VL_IN8(&clk,0,0);
    VL_IN8(&rst_n,0,0);
    VL_IN8(&enc_s_tvalid,0,0);
    VL_IN8(&enc_s_tlast,0,0);
    VL_OUT8(&enc_s_tready,0,0);
    VL_OUT8(&enc_m_tvalid,0,0);
    VL_OUT8(&enc_m_tlast,0,0);
    VL_IN8(&enc_m_tready,0,0);
    VL_IN8(&dec_s_tvalid,0,0);
    VL_IN8(&dec_s_tlast,0,0);
    VL_OUT8(&dec_s_tready,0,0);
    VL_OUT8(&dec_m_tvalid,0,0);
    VL_OUT8(&dec_m_tlast,0,0);
    VL_IN8(&dec_m_tready,0,0);
    VL_IN8(&tb_inject_mode,0,0);
    VL_IN16(&enc_s_tuser,15,0);
    VL_OUT16(&enc_m_tuser,15,0);
    VL_IN16(&dec_s_tuser,15,0);
    VL_OUT16(&dec_m_tuser,15,0);
    VL_IN16(&cfg_udp_port,15,0);
    VL_IN16(&cfg_mtu,15,0);
    VL_INW(&enc_s_tdata,511,0,16);
    VL_OUTW(&enc_m_tdata,511,0,16);
    VL_INW(&dec_s_tdata,511,0,16);
    VL_OUTW(&dec_m_tdata,511,0,16);
    VL_IN(&cfg_local_ip,31,0);
    VL_IN(&cfg_peer_ip,31,0);
    VL_OUT(&stat_enc_frames_out,31,0);
    VL_OUT(&stat_enc_oversize,31,0);
    VL_OUT(&stat_dec_frames_out,31,0);
    VL_OUT(&stat_dec_bad_cksum,31,0);
    VL_OUT(&stat_dec_bad_port,31,0);
    VL_OUT(&stat_dec_oversize,31,0);
    VL_IN64(&enc_s_tkeep,63,0);
    VL_OUT64(&enc_m_tkeep,63,0);
    VL_IN64(&dec_s_tkeep,63,0);
    VL_OUT64(&dec_m_tkeep,63,0);
    VL_IN64(&cfg_local_mac,47,0);
    VL_IN64(&cfg_peer_mac,47,0);

    // CELLS
    // Public to allow access to /* verilator public */ items.
    // Otherwise the application code can consider these internals.

    // Root instance pointer to allow access to model internals,
    // including inlined /* verilator public_flat_* */ items.
    Vtop___024root* const rootp;

    // CONSTRUCTORS
    /// Construct the model; called by application code
    /// If contextp is null, then the model will use the default global context
    /// If name is "", then makes a wrapper with a
    /// single model invisible with respect to DPI scope names.
    explicit Vtop(VerilatedContext* contextp, const char* name = "TOP");
    explicit Vtop(const char* name = "TOP");
    /// Destroy the model; called (often implicitly) by application code
    virtual ~Vtop();
  private:
    VL_UNCOPYABLE(Vtop);  ///< Copying not allowed

  public:
    // API METHODS
    /// Evaluate the model.  Application must call when inputs change.
    void eval() { eval_step(); }
    /// Evaluate when calling multiple units/models per time step.
    void eval_step();
    /// Evaluate at end of a timestep for tracing, when using eval_step().
    /// Application must call after all eval() and before time changes.
    void eval_end_step() {}
    /// Simulation complete, run final blocks.  Application must call on completion.
    void final();
    /// Are there scheduled events to handle?
    bool eventsPending();
    /// Returns time at next time slot. Aborts if !eventsPending()
    uint64_t nextTimeSlot();
    /// Trace signals in the model; called by application code
    void trace(VerilatedTraceBaseC* tfp, int levels, int options = 0) { contextp()->trace(tfp, levels, options); }
    /// Retrieve name of this model instance (as passed to constructor).
    const char* name() const;

    // Abstract methods from VerilatedModel
    const char* hierName() const override final;
    const char* modelName() const override final;
    unsigned threads() const override final;
    /// Prepare for cloning the model at the process level (e.g. fork in Linux)
    /// Release necessary resources. Called before cloning.
    void prepareClone() const;
    /// Re-init after cloning the model at the process level (e.g. fork in Linux)
    /// Re-allocate necessary resources. Called after cloning.
    void atClone() const;
    std::unique_ptr<VerilatedTraceConfig> traceConfig() const override final;
  private:
    // Internal functions - trace registration
    void traceBaseModel(VerilatedTraceBaseC* tfp, int levels, int options);
};

#endif  // guard
