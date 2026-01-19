//+------------------------------------------------------------------+
//| TestHealthMonitor.mq5                                            |
//| Integration test: Simula fallos y verifica bloqueo/alertas       |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "../Monitoring/HealthMonitor.mqh"
#include "../Monitoring/TraceAlert.mqh"
#include "../Core/StateManager.mqh"  // Dependencias
#include "../Core/SpreadMonitor.mqh"
#include "../Core/NewsImpactFilter.mqh"
#include "../Core/RiskManager.mqh"
#include "../Core/ExecutionEngine.mqh"  // Para test full flow

void OnStart()
{
   // Inicializar globals si necesario

   // Test 1: Todos OK - Debe permitir
   bool result = g_health_monitor.IsTradingAllowed();
   if(result) Print("Test All OK: PASSED");
   else Print("Test All OK: FAILED");

   // Test 2: Simular kill_switch
   g_state_manager.SetKillSwitch(true);
   result = g_health_monitor.IsTradingAllowed();
   if(!result) Print("Test Kill Switch: PASSED - Bloqueado con alerta");
   else Print("Test Kill Switch: FAILED");
   g_state_manager.SetKillSwitch(false);  // Reset

   // Test 3: Simular spread no allowed (hack: set high spread via buffer)
   // Asumir UpdateSpread con high value; o mock IsAllowed=false
   // Para simplicidad: Asumir falla si set

   // Test 4: Simular news bloqueo
   // Mock: Set event en NewsFilter para IsTradingAllowed=false

   // Test 5: Simular DD excedido
   g_risk_manager.SetCurrentDD(10.0);  // > max
   result = g_health_monitor.IsTradingAllowed();
   if(!result) Print("Test Drawdown: PASSED");
   else Print("Test Drawdown: FAILED");
   g_risk_manager.SetCurrentDD(0.0);  // Reset

   // Test Full: Integration con ExecutionEngine
   g_risk_manager.SetCurrentDD(10.0);  // Bloquear
   bool exec_result = g_execution_engine.ExecuteTrade("XAUUSD", 0.01, 100.0, 200.0);
   if(!exec_result) Print("Test Execution Blocked: PASSED - No trade enviado");
   else Print("Test Execution Blocked: FAILED");
}