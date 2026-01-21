//+------------------------------------------------------------------+
//|  GoldScalper.mq5                                                  |
//|  Unified EA: GoldScalper (modular)                                |
//+------------------------------------------------------------------+
#property copyright "GoldScalper / Melisa Ruiz"
#property link    "https://github.com/MelisaRuiz/GoldNew"
#property version "1.06"
#property strict

#include <Trade\Trade.mqh>
#include <Crypt.mqh>              // for local SHA256 if needed

#include "Core/StateManager.mqh"
#include "Agents/AgentOrchestrator.mqh"
#include "Core/NewsImpactFilter.mqh"
#include "Core/ExecutionEngine.mqh"
#include "Core/ExponentialBackoff.mqh"
#include "Core/RiskManager.mqh"
#include "Core/SpreadMonitor.mqh"
#include "Core/SessionManager.mqh"
#include "Core/ImmutableCore.mqh"
#include "Monitoring/TraceAlert.mqh"
#include "Monitoring/HealthMonitor.mqh"

// Global instances expected by modules
extern ExecutionEngine g_execution_engine;
extern RiskManager g_risk_manager;
extern StateManager g_state_manager;
extern SpreadMonitor g_spread_monitor;
extern SessionManager g_session_manager;
extern NewsImpactFilter g_news_filter;
extern TraceAlert g_trace;
extern HealthMonitor *g_health_monitor;

// ExpectedMap unified in ExecutionEngine - uses pending_requests.csv only
// Removed EA-level duplication to avoid inconsistencies

// parse symbols list (same as before)
static string g_symbols[]; static int g_symbols_count = 0;
void ParseSymbolsList() { /* existing parsing logic, omitted for brevity in this snippet */ }

// OnInit / OnDeinit
int OnInit()
{
   // INMUTABLE: Validar símbolo XAUUSD exclusivamente
   string chart_symbol = _Symbol;
   if(!ImmutableCore::ValidateSymbol(chart_symbol))
   {
      Print("ERROR: EA only supports ", ImmutableCore::GetAllowedSymbol(), ", chart symbol is: ", chart_symbol);
      return INIT_FAILED;
   }
   
   // Initialize news filter
   g_news_filter.Init();
   
   // Set timer for news refresh every 300 seconds
   EventSetTimer(300);
   
   // ExecutionEngine handles all pending request persistence via pending_requests.csv
   // No EA-level ExpectedMap needed - unified in ExecutionEngine
   
   // INMUTABLE: Verificar configuración de riesgo
   double base_risk = g_risk_manager.GetEffectiveRiskPct();
   if(MathAbs(base_risk - ImmutableCore::GetBaseRiskPct()) > 0.001)
   {
      Print("WARNING: Risk config mismatch - Immutable requires ", ImmutableCore::GetBaseRiskPct(), "%, got ", base_risk);
   }
   
   // other init steps omitted for brevity...
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   // ExecutionEngine persists pending_requests.csv automatically
   // No need for EA-level ExpectedMap save
   EventKillTimer(); // Clean up timer
}

// OnTimer: refresh news every 300 seconds
void OnTimer()
{
   g_news_filter.Refresh();
}

// OnTradeTransaction: unified reconciliation via ExecutionEngine only
// ExecutionEngine handles all pending request tracking and persistence in pending_requests.csv
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   // ExecutionEngine reconciles all pending requests and persists to pending_requests.csv
   // This is the single source of truth - no EA-level ExpectedMap duplication
   g_execution_engine.HandleTradeTransaction(trans, req, res);

   // Record trade result with RiskManager
   double pnl = trans.profit;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl_pct = (equity != 0.0) ? (pnl / equity * 100.0) : 0.0;
   bool is_win = pnl > 0.0;
   g_risk_manager.RecordTrade((ulong)trans.order, is_win, pnl_pct);

   // Persist global state (drawdown, kill_switch, etc.)
   g_state_manager.Save();
}
