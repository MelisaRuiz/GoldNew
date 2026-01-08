//+------------------------------------------------------------------+
//| ExecutionEngine.mqh - Order execution for Gold Scalper EA        |
//| Ports Python's execution_engine.py: Handles orders with retries  |
//| (max 2), slippage tolerance, CTrade. Adds duplicate prevention   |
//| and price limits. Called from main after signal approval.        |
//|                                                                  |
//| Best Practices:                                                  |
//| - Uses CTrade for reliable order sending                         |
//| - Retries on failures (e.g., requotes)                           |
//| - Prevents duplicates by checking open positions                 |
//| - Validates prices against market (bid/ask bounds)               |
//+------------------------------------------------------------------+
#ifndef EXECUTION_ENGINE_MQH
#define EXECUTION_ENGINE_MQH
#property strict

#include <Trade\Trade.mqh>  // For CTrade
#include "SignalModule.mqh" // For TradingSignal struct
#include "RiskManager.mqh"  // For lot size calculation (assume exists)
#include "ConfigManager.mqh" // Updated to ConfigManager

// ExecutionResult struct - For traceability
struct ExecutionResult
{
   bool   success;     // True if order placed
   ulong  ticket;      // Order ticket if success
   string error_msg;   // Reason if failed
};

// ExecutionEngine class - Ports Python logic to MQL5
class ExecutionEngine
{
private:
   CTrade m_trade;               // CTrade instance for orders
   int    m_max_retries;         // Max retries (from config, default 2)
   int    m_slippage_pts;        // Slippage tolerance in points
   double m_price_tolerance;     // Price limit tolerance (e.g., 0.5% from market)

   // Helper: Check for duplicate orders/positions
   bool HasDuplicate(string symbol, int direction)
   {
      int total = PositionsTotal();
      for (int i = 0; i < total; i++)
      {
         if (PositionGetSymbol(i) == symbol && PositionGetInteger(POSITION_TYPE) == (direction == 1 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
         {
            // Check if similar (e.g., same symbol and direction, within recent time)
            if (MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - SymbolInfoDouble(symbol, SYMBOL_ASK)) < m_price_tolerance * SymbolInfoDouble(symbol, SYMBOL_ASK))
               return true; // Duplicate detected
         }
      }
      total = OrdersTotal();
      for (int i = 0; i < total; i++)
      {
         if (OrderGetSymbol(i) == symbol && OrderGetInteger(ORDER_TYPE) == (direction == 1 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT))
            return true; // Pending duplicate
      }
      return false;
   }

   // Helper: Validate price limits (entry within bid/ask, SL/TP reasonable)
   bool ValidatePrices(string symbol, const TradingSignal &sig)
   {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double spread = ask - bid;
      
      // Entry price within tolerance of market
      double market_price = (sig.direction == 1) ? ask : bid;
      if (MathAbs(sig.entry_price - market_price) > m_price_tolerance * market_price + spread)
      {
         Print("Invalid entry price: ", sig.entry_price, " vs market ", market_price);
         return false;
      }
      
      // SL/TP distance valid (e.g., min levels)
      double sl_dist = MathAbs(sig.entry_price - sig.stop_loss);
      double tp_dist = MathAbs(sig.entry_price - sig.take_profit);
      double min_sl = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(symbol, SYMBOL_POINT);
      if (sl_dist < min_sl || tp_dist < min_sl * 1.5) // Arbitrary RR check
      {
         Print("Invalid SL/TP distances: SL=", sl_dist, ", TP=", tp_dist, " min=", min_sl);
         return false;
      }
      
      return true;
   }

public:
   // Constructor - Initialize defaults
   ExecutionEngine()
   {
      m_max_retries = 2;      // Hardcoded or from config
      m_slippage_pts = 3;    // Hardcoded
      m_price_tolerance = 0.005;        // 0.5% tolerance
   }

   // Execute method: Place order based on signal, with retries
   ExecutionResult Execute(string symbol, const TradingSignal &sig)
   {
      ExecutionResult res;
      res.success = false;
      res.ticket = 0;
      res.error_msg = "";

      // Step 1: Duplicate prevention
      if (HasDuplicate(symbol, sig.direction))
      {
         res.error_msg = "Duplicate order detected";
         return res;
      }

      // Step 2: Price limit validation
      if (!ValidatePrices(symbol, sig))
      {
         res.error_msg = "Price validation failed";
         return res;
      }

      // Step 3: Calculate lot size (from RiskManager, assume fixed 0.3% risk)
      double lot = RiskManager::CalculateLot(symbol, sig.entry_price, sig.stop_loss); // Static call, assume implemented

      // Step 4: Prepare order request
      MqlTradeRequest req;
      ZeroMemory(req);
      req.action = TRADE_ACTION_DEAL;
      req.symbol = symbol;
      req.volume = lot;
      req.type = (sig.direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      req.price = NormalizeDouble(sig.entry_price, _Digits);
      req.sl = NormalizeDouble(sig.stop_loss, _Digits);
      req.tp = NormalizeDouble(sig.take_profit, _Digits);
      req.deviation = m_slippage_pts;
      req.comment = "GoldScalper_" + EnumToString(sig.type);
      req.magic = 123456; // EA magic number

      MqlTradeResult trade_res;
      int retries = 0;
      while (retries <= m_max_retries)
      {
         if (m_trade.PositionOpen(req, trade_res))
         {
            res.success = true;
            res.ticket = trade_res.order;
            Print("Order executed: Ticket=", res.ticket, " Volume=", lot);
            return res;
         }
         else
         {
            retries++;
            res.error_msg = "Execution failed: Ret=", trade_res.retcode, " Comment=", trade_res.comment;
            Print(res.error_msg, " Retry ", retries);
            if (retries > m_max_retries) break;
            Sleep(1000); // 1s backoff between retries
         }
      }

      return res;
   }
};

#endif  // EXECUTION_ENGINE_MQH