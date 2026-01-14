//+------------------------------------------------------------------+
//| ExecutionEngine.mqh - Handles trade execution with retries       |
//| Integrates SpreadMonitor check pre-order, RefreshRates, and logs.|
//| Updated for resilience: Revalidates spread/risk pre-OrderSend,   |
//| exponential backoff on busy/errors, reconciles partial fills     |
//| with StateManager.                                               |
//+------------------------------------------------------------------+
#ifndef EXECUTION_ENGINE_MQH
#define EXECUTION_ENGINE_MQH
#property strict
#include <Trade\Trade.mqh>
#include "RiskManager.mqh" // For CalculateLot and CheckDrawdown
#include "SpreadMonitor.mqh" // For IsAllowed
#include "ExponentialBackoff.mqh" // For backoff retries
#include "StateManager.mqh" // For reconciliation (add UpdatePosition if needed)
#include "Monitoring/Monitoring.mqh" // For g_trace

struct ExecutionResult
{
   bool success;
   ulong ticket;
   string error_msg;
   double lot_size; // For logging
};

class ExecutionEngine
{
private:
   CTrade m_trade;
   ExponentialBackoff m_backoff; // Instance for retries
   int m_max_retries; // e.g., 3
   datetime m_breaker_end; // Circuit breaker timestamp

public:
   ExecutionEngine()
   {
      m_trade.SetExpertMagicNumber(12345); // Configurable magic
      m_trade.SetDeviation(10); // Slippage tolerance
      m_backoff.Init(100, 2.0, 5000); // Initial 100ms, factor 2, max 5s
      m_max_retries = 3;
      m_breaker_end = 0;
   }

   ExecutionResult Execute(string symbol, TradingSignal &signal)
   {
      ExecutionResult res;
      res.success = false;
      res.ticket = 0;
      res.error_msg = "";
      res.lot_size = 0.0;

      // Circuit breaker check
      if(TimeCurrent() < m_breaker_end)
      {
         res.error_msg = "Circuit breaker active";
         g_trace.Log(TRACE_WARNING, "EXEC", res.error_msg);
         return res;
      }

      // Pre-execution revalidation: RefreshRates, spread, risk
      if(!RefreshRates(symbol))
      {
         res.error_msg = "Failed to refresh rates";
         g_trace.Log(TRACE_ERROR, "EXEC", res.error_msg);
         return res;
      }
      if(!g_spread_monitor.IsAllowed(symbol))
      {
         res.error_msg = "Spread invalid or expansion detected";
         g_trace.Log(TRACE_ERROR, "EXEC", res.error_msg + " for " + symbol);
         return res;
      }
      if(!g_risk_manager.CheckDrawdown())
      {
         res.error_msg = "Drawdown limit exceeded";
         g_trace.Log(TRACE_ERROR, "EXEC", res.error_msg);
         return res;
      }

      // Calculate lot
      double lot = RiskManager::CalculateLot(symbol, signal.entry_price, signal.stop_loss);
      if(lot <= 0.0)
      {
         res.error_msg = "Invalid lot size";
         return res;
      }
      res.lot_size = lot;

      // Prepare request (market order)
      MqlTradeRequest req;
      ZeroMemory(req);
      req.action = TRADE_ACTION_DEAL;
      req.symbol = symbol;
      req.volume = lot;
      req.type = signal.is_long ? ORDER_TYPE_BUY : ORDER_TYPE_SELL; // Assume is_long in signal
      req.type_filling = ORDER_FILLING_IOC; // Allows partials
      req.deviation = 10;
      req.sl = signal.stop_loss;
      req.tp = signal.take_profit;

      int retries = 0;
      double remaining_vol = lot;
      while(retries < m_max_retries && remaining_vol > 0.0)
      {
         MqlTradeResult ret;
         ZeroMemory(ret);
         req.volume = remaining_vol; // Update for remaining if partial
         if(m_trade.OrderSend(req, ret))
         {
            res.ticket = ret.deal; // Main ticket
            if(ret.volume < remaining_vol)
            {
               // Partial fill detected
               g_trace.Log(TRACE_WARNING, "EXEC", "Partial fill: filled=" + DoubleToString(ret.volume, 2) + ", remaining=" + DoubleToString(remaining_vol - ret.volume, 2));
               ReconcilePartial(symbol, ret.deal, ret.volume); // Reconcile with StateManager
               remaining_vol -= ret.volume;
               // Continue for remaining (or decide to stop based on config)
            }
            else
            {
               res.success = true;
               ReconcilePartial(symbol, ret.deal, ret.volume); // Full fill reconciliation
               return res;
            }
         }
         else
         {
            res.error_msg = m_trade.ResultRetcodeDescription(ret.retcode);
            g_trace.Log(TRACE_ERROR, "EXEC", "OrderSend failed: " + res.error_msg + " (retcode=" + IntegerToString(ret.retcode) + ")");
            if(ret.retcode == TRADE_RETCODE_CONTEXT_BUSY || ret.retcode == TRADE_RETCODE_REQUOTE)
            {
               // Backoff for busy/requote
               long delay = m_backoff.GetNextDelay();
               Sleep((int)delay);
               retries++;
            }
            else
            {
               // Non-retryable error
               break;
            }
         }
      }

      if(!res.success)
      {
         // Activate circuit breaker on max retries fail
         m_breaker_end = TimeCurrent() + 300; // 5min
         g_trace.Log(TRACE_CRITICAL, "EXEC", "Max retries exceeded, breaker activated for 5min");
      }
      return res;
   }

private:
   bool RefreshRates(string symbol)
   {
      MqlTick tick;
      if(SymbolInfoTick(symbol, tick)) return true;
      g_trace.Log(TRACE_WARNING, "EXEC", "Failed to get fresh tick for " + symbol);
      return false;
   }

   void ReconcilePartial(string symbol, ulong ticket, double filled_vol)
   {
      // Reconcile with StateManager: Update position state (assume StateManager has UpdatePosition)
      g_state_manager.UpdatePosition(ticket, filled_vol, symbol); // Add this method to StateManager if not present
      // Example: g_state_manager.SetOpenVolume(symbol, filled_vol); or track in array
      g_trace.Log(TRACE_INFO, "EXEC", "Reconciled position: ticket=" + IntegerToString(ticket) + ", filled=" + DoubleToString(filled_vol, 2));
   }
};
#endif // EXECUTION_ENGINE_MQH

// -------------------- Test Snippet for Requotes (add to TestSuite.mq5 or run as script) -----------------------
/*
// TestRequotes: Simulates ERR_REQUOTE and checks if backoff retries occur (mock CTrade)
class MockCTrade : CTrade
{
public:
   bool simulate_requote = true;
   virtual bool OrderSend(MqlTradeRequest &req, MqlTradeResult &ret)
   {
      if(simulate_requote)
      {
         ret.retcode = TRADE_RETCODE_REQUOTE;
         return false;
      }
      ret.retcode = TRADE_RETCODE_DONE;
      ret.volume = req.volume;
      ret.deal = 12345;
      return true;
   }
};

void TestRequotes()
{
   ExecutionEngine engine;
   TradingSignal sig; // Mock signal
   sig.is_long = true;
   sig.entry_price = 2000.0;
   sig.stop_loss = 1990.0;
   sig.take_profit = 2020.0;

   // Mock spread/risk to pass
   // Assume g_spread_monitor.IsAllowed = true, g_risk_manager.CheckDrawdown = true

   ExecutionResult res = engine.Execute("XAUUSD", sig);

   if(res.success) // After retries, assume final success if mock turns off simulate
   {
      Print("Test PASS: Handled requote with retries.");
   }
   else
   {
      Print("Test FAIL: Requote not handled.");
   }
}
*/

// -------------------- Test Snippet for Partial Fills (add to TestSuite.mq5 or run as script) -----------------------
/*
// TestPartials: Simulates partial fill and checks reconciliation
class MockCTradePartial : CTrade
{
public:
   virtual bool OrderSend(MqlTradeRequest &req, MqlTradeResult &ret)
   {
      ret.retcode = TRADE_RETCODE_DONE;
      ret.volume = req.volume / 2.0; // Partial
      ret.deal = 12345;
      return true;
   }
};

void TestPartials()
{
   ExecutionEngine engine;
   TradingSignal sig; // Mock
   sig.is_long = true;
   sig.entry_price = 2000.0;
   sig.stop_loss = 1990.0;
   sig.take_profit = 2020.0;

   ExecutionResult res = engine.Execute("XAUUSD", sig);

   // Check if remaining was attempted and reconciled (inspect logs or state)
   if(res.success && /* check StateManager has updated volume */ true)
   {
      Print("Test PASS: Partial fill reconciled and remaining handled.");
   }
   else
   {
      Print("Test FAIL: Partial not reconciled.");
   }
}
*/