//+------------------------------------------------------------------+
//| SimulatePartialFill.mq5 - helper script to simulate OnTradeTransaction events
//| Usage: run on chart where EA is attached to exercise reconciliation paths.
//+------------------------------------------------------------------+
#property script_show_inputs
#include "../Core/ExecutionEngine.mqh"
#include "../Core/StateManager.mqh"

void OnStart()
{
   // This script emulates two partial DEAL_ADD events for a known ticket/request id.
   // NOTE: On a real platform you cannot synthesize platform transaction callbacks.
   // This script calls g_execution_engine.HandleTradeTransaction directly to test logic.

   // Ensure engine loaded
   g_execution_engine.Init();

   // Create a fake pending request entry to simulate a real order
   ulong fake_ticket = 9999999; // unique in test
   string symbol = "XAUUSD";
   double requested = 0.10;
   ExecutionEngine::TradeSide side = ExecutionEngine::SIDE_BUY;

   // Add pending request via engine API (we rely on the engine being accessible)
   ulong client_id = g_execution_engine.AddPendingRequest(fake_ticket, symbol, requested, side);

   // Simulate first partial fill
   MqlTradeTransaction trans1; ZeroMemory(trans1);
   MqlTradeRequest req1; ZeroMemory(req1);
   MqlTradeResult res1; ZeroMemory(res1);
   trans1.type = TRADE_TRANSACTION_DEAL_ADD;
   trans1.order = fake_ticket;
   trans1.volume = 0.04;
   g_execution_engine.HandleTradeTransaction(trans1, req1, res1);

   // Simulate second partial fill
   MqlTradeTransaction trans2; ZeroMemory(trans2);
   trans2.type = TRADE_TRANSACTION_DEAL_ADD;
   trans2.order = fake_ticket;
   trans2.volume = 0.06;
   g_execution_engine.HandleTradeTransaction(trans2, req1, res1);

   Print("SimulatePartialFill finished - check pending_requests.csv and expected_map.csv");
}
