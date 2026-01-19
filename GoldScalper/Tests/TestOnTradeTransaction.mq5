//+------------------------------------------------------------------+
//| TestOnTradeTransaction.mq5                                       |
//| Simula DEAL_ADD con profit +/- y verifica updates/persistencia   |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "../Core/RiskManager.mqh"
#include "../Core/StateManager.mqh"

input double TestProfit = 100.0;  // Profit positivo para win
input double TestLoss = -50.0;    // Profit negativo para loss

void OnStart()
{
   // Inicializar
   g_state_manager.LoadState();  // Cargar si existe

   // Simular DEAL_ADD win
   MqlTradeTransaction trans_win;
   trans_win.type = TRADE_TRANSACTION_DEAL_ADD;
   trans_win.profit = TestProfit;
   trans_win.deal = 12345;  // Ticket simulado

   OnTradeTransaction(trans_win, NULL, NULL);  // Llamar manualmente

   Print("Post-Win: Consec Losses: ", g_risk_manager.GetConsecLosses(), " DD: ", g_risk_manager.GetCurrentDD());
   if (g_risk_manager.GetConsecLosses() == 0) Print("Test Win: PASSED"); else Print("Test Win: FAILED");

   // Simular DEAL_ADD loss
   MqlTradeTransaction trans_loss;
   trans_loss.type = TRADE_TRANSACTION_DEAL_ADD;
   trans_loss.profit = TestLoss;
   trans_loss.deal = 67890;

   OnTradeTransaction(trans_loss, NULL, NULL);

   Print("Post-Loss: Consec Losses: ", g_risk_manager.GetConsecLosses(), " DD: ", g_risk_manager.GetCurrentDD());
   if (g_risk_manager.GetConsecLosses() == 1 && g_risk_manager.GetCurrentDD() > 0) Print("Test Loss: PASSED"); else Print("Test Loss: FAILED");

   // Verificar persistencia: "Reinicio" simulado
   StateManager temp_state;
   temp_state.LoadState();
   if (temp_state.GetConsecLosses() == g_risk_manager.GetConsecLosses() && temp_state.GetCurrentDD() == g_risk_manager.GetCurrentDD()) {
      Print("Test Persistencia: PASSED");
   } else {
      Print("Test Persistencia: FAILED");
   }
}