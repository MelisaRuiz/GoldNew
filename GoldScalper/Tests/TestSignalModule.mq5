//+------------------------------------------------------------------+
//| TestSignalModule.mq5 - Unit test script for SignalModule        |
//| Tests GenerateSignal() with mock data (simulates BOS retest).    |
//| Verifies confidence >0.75 and RR>1.5. Runs in MT5 tester.       |
//+------------------------------------------------------------------+
#property script_show_window false
#property strict

#include "SignalModule.mqh"
#include "LiquidityAnalysisAgent.mqh" // For mock LiquidityResult

// Mock LiquidityResult for testing
LiquidityResult CreateMockLiquidity(double score, double atr)
{
   LiquidityResult mock;
   mock.liquidity_score = score;
   mock.atr_volatility = atr;
   mock.regime = HIGH_LIQUIDITY;
   mock.multi_tf_aligned = true;
   string zones[1] = {"Mock FVG"};
   ArrayCopy(mock.zones, zones);
   return mock;
}

// Test function
void TestGenerateSignal()
{
   SignalModule module(0.75, 2.0); // min_conf 0.75, rr 2.0

   // Mock liquidity for BOS retest simulation
   LiquidityResult liq = CreateMockLiquidity(0.85, 10.0); // High score, ATR 10

   TradingSignal sig = module.GenerateSignal("XAUUSD", PERIOD_M15, liq);

   // Verifications
   if (sig.confidence > 0.75)
      Print("Test PASSED: Confidence = ", sig.confidence, " > 0.75");
   else
      Print("Test FAILED: Confidence = ", sig.confidence, " <= 0.75");

   double rr = MathAbs(sig.take_profit - sig.entry_price) / MathAbs(sig.entry_price - sig.stop_loss);
   if (rr > 1.5)
      Print("Test PASSED: RR = ", rr, " > 1.5");
   else
      Print("Test FAILED: RR = ", rr, " <= 1.5");

   if (sig.valid)
      Print("Overall Test PASSED: Valid signal generated");
   else
      Print("Overall Test FAILED: Invalid signal");
}

// OnStart for script execution
void OnStart()
{
   TestGenerateSignal();
}