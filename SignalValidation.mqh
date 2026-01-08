//+------------------------------------------------------------------+
//| SignalValidation.mqh - Validates signals with LLM fallback       |
//| Ports Python signal_validation_agent.py: Uses rules + LLM.       |
//| Deterministic (temperature=0), with heuristic fallback.          |
//|                                                                  |
//| Best Practices:                                                  |
//| - Uses MarketAnalyzer for LLM.                                   |
//| - Fallback to RSI/MACD rules if LLM fails.                       |
//+------------------------------------------------------------------+
#ifndef SIGNAL_VALIDATION_MQH
#define SIGNAL_VALIDATION_MQH
#property strict

#include "MarketAnalyzer.mqh" // For ValidateSignalWithLLM
#include "SignalModule.mqh"   // For TradingSignal

// SignalValidation class
class SignalValidation
{
private:
   MarketAnalyzer *m_analyzer;

public:
   SignalValidation(MarketAnalyzer *analyzer)
   {
      m_analyzer = analyzer;
   }

   bool Validate(TradingSignal &sig, string symbol)
   {
      if (m_analyzer == NULL) return false;
      return m_analyzer.ValidateSignalWithLLM(sig, symbol);
   }
};

#endif // SIGNAL_VALIDATION_MQH