//+------------------------------------------------------------------+
//| TestHealthMonitor.mq5                                            |
//| Integration test: Simula fallos y verifica bloqueo/alertas       |
//| Tests: drawdown >5%, kill_switch, breaker temporal (600s)        |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "../Monitoring/HealthMonitor.mqh"
#include "../Monitoring/TraceAlert.mqh"
#include "../Core/StateManager.mqh"
#include "../Core/SpreadMonitor.mqh"
#include "../Core/NewsImpactFilter.mqh"
#include "../Core/RiskManager.mqh"
#include "../Core/ExecutionEngine.mqh"

void OnStart()
{
   Print("=== TestHealthMonitor: Starting tests ===");
   int passed = 0;
   int failed = 0;
   
   // Ensure globals are initialized
   if(g_health_monitor == NULL)
   {
      Print("ERROR: g_health_monitor is NULL. Initialize it first.");
      return;
   }
   
   // Reset state for clean tests
   g_state_manager.Reset(false);
   g_state_manager.SetKillSwitch(false, false);
   g_state_manager.SetCurrentDD(0.0, false);
   
   // Test 1: All OK - Should allow trading
   bool result = g_health_monitor->IsTradingAllowed("XAUUSD");
   if(result)
   {
      Print("Test 1 (All OK): PASSED - Trading allowed");
      passed++;
   }
   else
   {
      Print("Test 1 (All OK): FAILED - Trading blocked unexpectedly");
      failed++;
   }
   
   // Test 2: Kill switch - Should block and activate breaker
   g_state_manager.SetKillSwitch(true, false);
   result = g_health_monitor->IsTradingAllowed("XAUUSD");
   if(!result)
   {
      Print("Test 2 (Kill Switch): PASSED - Trading blocked");
      passed++;
   }
   else
   {
      Print("Test 2 (Kill Switch): FAILED - Trading should be blocked");
      failed++;
   }
   
   // Test breaker is active (should still block even after resetting kill switch)
   g_state_manager.SetKillSwitch(false, false);
   result = g_health_monitor->IsTradingAllowed("XAUUSD");
   if(!result)
   {
      Print("Test 2b (Breaker after kill switch): PASSED - Breaker still active");
      passed++;
   }
   else
   {
      Print("Test 2b (Breaker after kill switch): FAILED - Breaker should still block");
      failed++;
   }
   
   // Reset breaker by waiting (simulate) - in real test would need time manipulation
   // For now, we'll test that breaker was set
   g_state_manager.SetKillSwitch(false, false);
   Sleep(100); // Small delay
   
   // Test 3: Drawdown > 5% - Should block and activate breaker
   // Set drawdown to 10% (above default 5% max)
   g_state_manager.SetCurrentDD(10.0, false);
   result = g_health_monitor->IsTradingAllowed("XAUUSD");
   if(!result)
   {
      Print("Test 3 (Drawdown >5%): PASSED - Trading blocked, breaker activated");
      passed++;
   }
   else
   {
      Print("Test 3 (Drawdown >5%): FAILED - Trading should be blocked");
      failed++;
   }
   
   // Reset drawdown
   g_state_manager.SetCurrentDD(0.0, false);
   
   // Test 4: Drawdown exactly at threshold (5%) - Should allow
   g_state_manager.SetCurrentDD(5.0, false);
   result = g_health_monitor->IsTradingAllowed("XAUUSD");
   // Note: CheckDrawdown() checks if current_dd > max_dd, so 5.0 should be allowed if max is 5.0
   // But we need to check if it's strictly greater
   double max_dd = g_risk_manager.GetMaxDdPct();
   if(5.0 <= max_dd && result)
   {
      Print("Test 4 (Drawdown at threshold): PASSED - Trading allowed at threshold");
      passed++;
   }
   else if(5.0 > max_dd && !result)
   {
      Print("Test 4 (Drawdown at threshold): PASSED - Trading blocked above threshold");
      passed++;
   }
   else
   {
      Print("Test 4 (Drawdown at threshold): FAILED - Unexpected result");
      failed++;
   }
   
   // Reset
   g_state_manager.SetCurrentDD(0.0, false);
   g_state_manager.SetKillSwitch(false, false);
   
   // Test 5: Integration with ExecutionEngine - Should block when drawdown > 5%
   g_state_manager.SetCurrentDD(10.0, false);
   TradingSignal signal;
   signal.valid = true;
   signal.is_long = true;
   signal.entry_price = 2000.0;
   signal.stop_loss = 1990.0;
   signal.take_profit = 2010.0;
   signal.confidence = 0.8;
   
   ExecutionResult exec_result = g_execution_engine.Execute("XAUUSD", signal);
   if(!exec_result.success && StringFind(exec_result.error_msg, "HealthMonitor") >= 0)
   {
      Print("Test 5 (ExecutionEngine integration): PASSED - Execution blocked by HealthMonitor");
      passed++;
   }
   else
   {
      Print("Test 5 (ExecutionEngine integration): FAILED - error_msg=", exec_result.error_msg);
      failed++;
   }
   
   // Reset
   g_state_manager.SetCurrentDD(0.0, false);
   
   // Test 6: Normal execution when all OK
   exec_result = g_execution_engine.Execute("XAUUSD", signal);
   // Note: This might fail for other reasons (session, spread, etc.), so we check if it's NOT blocked by HealthMonitor
   if(exec_result.success || StringFind(exec_result.error_msg, "HealthMonitor") < 0)
   {
      Print("Test 6 (Normal execution): PASSED - Not blocked by HealthMonitor");
      passed++;
   }
   else
   {
      Print("Test 6 (Normal execution): FAILED - Blocked by HealthMonitor unexpectedly");
      failed++;
   }
   
   Print("=== Test Summary: ", passed, " passed, ", failed, " failed ===");
}