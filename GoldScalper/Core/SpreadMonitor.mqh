//+------------------------------------------------------------------+
//| SpreadMonitor.mqh - Centralizes spread monitoring with Z-score   |
//| Handles max spread, sudden expansions, and temporary breakers.   |
//| Per-symbol history for multi-symbol support.                     |
//+------------------------------------------------------------------+
#ifndef SPREAD_MONITOR_MQH
#define SPREAD_MONITOR_MQH
#property strict
#include "Monitoring/Monitoring.mqh" // For g_trace logging

class SpreadMonitor
{
private:
   struct SymHistory
   {
      string sym;
      double history[100]; // Fixed window size
      int count;
      datetime breaker_end;
   };
   SymHistory m_histories[10]; // Max 10 symbols
   int m_num_sym;
   double m_max_spread_points;
   int m_zscore_window;
   double m_zscore_threshold;

   SymHistory* GetHistory(string symbol)
   {
      for(int i = 0; i < m_num_sym; i++)
         if(m_histories[i].sym == symbol) return &m_histories[i];
      return NULL;
   }

public:
   void Init(double max_points, int window, double thresh)
   {
      m_max_spread_points = max_points;
      m_zscore_window = window;
      m_zscore_threshold = thresh;
      m_num_sym = 0;
   }

   void AddSymbol(string sym)
   {
      if(m_num_sym >= 10) return;
      m_histories[m_num_sym].sym = sym;
      ArrayInitialize(m_histories[m_num_sym].history, 0.0);
      m_histories[m_num_sym].count = 0;
      m_histories[m_num_sym].breaker_end = 0;
      m_num_sym++;
   }

   void UpdateSpread(string symbol)
   {
      SymHistory* h = GetHistory(symbol);
      if(h == NULL) return;
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point == 0.0) return;
      double spread_points = (ask - bid) / point;
      if(h->count < m_zscore_window)
      {
         h->history[h->count++] = spread_points;
      }
      else
      {
         for(int i = 0; i < m_zscore_window - 1; i++) h->history[i] = h->history[i + 1];
         h->history[m_zscore_window - 1] = spread_points;
      }
   }

   double CalculateZScore(string symbol)
   {
      SymHistory* h = GetHistory(symbol);
      if(h == NULL || h->count < m_zscore_window) return 0.0;
      double mean = 0.0;
      for(int i = 0; i < m_zscore_window; i++) mean += h->history[i];
      mean /= m_zscore_window;
      double variance = 0.0;
      for(int i = 0; i < m_zscore_window; i++) variance += MathPow(h->history[i] - mean, 2);
      variance /= m_zscore_window;
      double std = MathSqrt(variance);
      if(std == 0.0) return 0.0;
      double current = h->history[m_zscore_window - 1];
      return (current - mean) / std;
   }

   bool IsAllowed(string symbol)
   {
      SymHistory* h = GetHistory(symbol);
      if(h == NULL) return false;
      if(TimeCurrent() < h->breaker_end)
      {
         g_trace.Log(TRACE_WARNING, "SPREAD", "Breaker active for " + symbol);
         return false;
      }
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point == 0.0) return false;
      double spread_points = (ask - bid) / point;
      double zscore = CalculateZScore(symbol);
      if(spread_points > m_max_spread_points || zscore > m_zscore_threshold)
      {
         MarkExpansionEvent(symbol);
         g_trace.Log(TRACE_WARNING, "SPREAD", "Invalid spread for " + symbol + ": points=" + DoubleToString(spread_points, 2) + ", zscore=" + DoubleToString(zscore, 2));
         return false;
      }
      return true;
   }

   void MarkExpansionEvent(string symbol)
   {
      SymHistory* h = GetHistory(symbol);
      if(h == NULL) return;
      h->breaker_end = TimeCurrent() + 300; // 5 minutes
      g_trace.Log(TRACE_WARNING, "SPREAD", "Expansion detected for " + symbol + ", breaker activated for 5min");
   }
};
// Global instance (initialized in OnInit)
#endif // SPREAD_MONITOR_MQH

// -------------------- Test Snippet for Spread Spikes (add to TestSuite.mq5 or run as script) -----------------------
/*
// TestSpreadSpikes: Simulates a spread spike and checks if IsAllowed returns false and breaker activates
void TestSpreadSpikes(string test_sym = "XAUUSD")
{
   // Init monitor for test
   SpreadMonitor test_monitor;
   test_monitor.Init(20.0, 100, 3.0); // max 20 points, window 100, thresh 3.0
   test_monitor.AddSymbol(test_sym);
   
   // Fill history with normal spreads (e.g., 5 points)
   for(int i = 0; i < 100; i++) 
   {
      // Simulate normal UpdateSpread (would use mock SymbolInfoDouble in full test)
      // Here, manually set history for simulation
      test_monitor.UpdateSpread(test_sym); // Assume this sets ~5 points; in real, mock bid/ask
   }
   
   // Simulate spike: Set high spread (e.g., 30 points)
   // In real test, mock SymbolInfoDouble to return high spread
   // For simulation, force update with high value (extend class for mock if needed)
   test_monitor.UpdateSpread(test_sym); // Assume spike
   
   bool allowed = test_monitor.IsAllowed(test_sym);
   datetime breaker = /* get breaker_end from private */; // In test, expose or check log
   
   if(!allowed && breaker > TimeCurrent())
   {
      Print("Test PASS: IsAllowed false on spike, breaker activated.");
   }
   else
   {
      Print("Test FAIL: Spike not detected.");
   }
}
*/