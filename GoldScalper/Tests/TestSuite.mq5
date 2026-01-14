//+------------------------------------------------------------------+
//| TestSuite.mq5 - Expanded with TestHarness for mocks.             |
//| Runs unit/integration tests: Agents, risk, spread, news, full    |
//| flow. Use for CI.                                                |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "../Core/Config.mqh" // Adjust paths to new structure
#include "../Agents/AgentOrchestrator.mqh" // Example
#include "../Core/RiskManager.mqh"
#include "../Core/SpreadMonitor.mqh"
#include "../Core/SessionManager.mqh"
#include "../Core/ExecutionEngine.mqh"
#include "../Monitoring/Monitoring.mqh"

// TestHarness: Mocks for ticks/spreads/news
class TestHarness
{
public:
   // Mock rates (for CopyRates)
   MqlRates mock_rates[];
   void SetMockRates(MqlRates &rates[]) { ArrayCopy(mock_rates, rates); }
   int CopyRates(string sym, ENUM_TIMEFRAMES tf, datetime start, int count, MqlRates &out[])
   {
      // Simulate CopyRates
      ArrayResize(out, count);
      ArrayCopy(out, mock_rates, 0, 0, count);
      return count;
   }
   
   // Mock SymbolInfoDouble (for spread)
   double mock_spread;
   void SetMockSpread(double spread) { mock_spread = spread; }
   double SymbolInfoDouble(string sym, ENUM_SYMBOL_INFO_DOUBLE prop)
   {
      if(prop == SYMBOL_SPREAD_FLOAT) return mock_spread;
      if(prop == SYMBOL_ASK) return 2000.0 + mock_spread / 2;
      if(prop == SYMBOL_BID) return 2000.0 - mock_spread / 2;
      if(prop == SYMBOL_POINT) return 0.01;
      return 0.0;
   }
   
   // Mock news events (inject to SessionManager's news_filter)
   NewsEvent mock_events[];
   void SetMockNews(NewsEvent &events[]) 
   {
      ArrayCopy(mock_events, events);
      // Inject into global or test instance
   }
   
   // Mock AccountEquity for risk
   double mock_equity = 10000.0;
   double AccountEquity() { return mock_equity; }
};

// Global test harness
TestHarness g_harness;

// Unit test: Risk consecutive losses
void TestConsecLosses()
{
   RiskManager rm;
   g_state_manager.SetConsecLosses(0);
   g_state_manager.SetCurrentDD(0.0);
   g_state_manager.SetKillSwitch(false);
   
   for(int i = 0; i < 5; i++)
   {
      rm.RecordTrade(false, -0.1);
   }
   
   if(g_state_manager.GetKillSwitch() && g_state_manager.GetConsecLosses() == 5)
      Print("PASS: Consec losses trigger kill_switch");
   else
      Print("FAIL: Consec losses");
}

// Integration test: Spread spike
void TestSpreadSpike()
{
   SpreadMonitor sm;
   sm.Init(20.0, 100, 3.0);
   sm.AddSymbol("XAUUSD");
   
   g_harness.SetMockSpread(5.0); // Normal
   for(int i = 0; i < 99; i++) sm.UpdateSpread("XAUUSD");
   
   g_harness.SetMockSpread(50.0); // Spike
   sm.UpdateSpread("XAUUSD");
   
   if(!sm.IsAllowed("XAUUSD"))
      Print("PASS: Spike detected");
   else
      Print("FAIL: Spike not detected");
}

// Integration test: News event block (NFP)
void TestNfpBlock()
{
   SessionManager sm;
   NewsEvent nfp;
   nfp.title = "NFP";
   nfp.impact = NEWS_HIGH;
   nfp.start = TimeCurrent() - 1800;
   nfp.end = TimeCurrent() + 1800;
   ArrayResize(nfp.symbols, 1);
   nfp.symbols[0] = "USD";
   
   NewsEvent events[1];
   events[0] = nfp;
   g_harness.SetMockNews(events);
   sm.m_news_filter.m_events = events; // Direct inject for test
   
   if(!sm.IsTradingSessionActive("XAUUSD"))
      Print("PASS: NFP blocks trading");
   else
      Print("FAIL: NFP not blocking");
}

// Full flow test: Signal to execution
void TestFullFlow()
{
   // Setup mocks: Rates for signals, normal spread, no news
   MqlRates rates[10]; // Mock bars for FVG/BOS
   // Fill rates with sample data...
   g_harness.SetMockRates(rates);
   g_harness.SetMockSpread(10.0); // Allowed
   NewsEvent no_events[0];
   g_harness.SetMockNews(no_events);
   
   // Run orchestrator, signal, execution
   AgentOrchestrator orch;
   // orch.ProcessSymbol... assert signal valid
   ExecutionEngine ee;
   TradingSignal sig; // Mock valid signal
   ExecutionResult res = ee.Execute("XAUUSD", sig);
   
   if(res.success)
      Print("PASS: Full flow execution");
   else
      Print("FAIL: Full flow");
}

// Run all tests
void OnStart()
{
   TestConsecLosses();
   TestSpreadSpike();
   TestNfpBlock();
   TestFullFlow();
   // Add more: Backtest simulation (load historical rates, run OnTimer loops)
}