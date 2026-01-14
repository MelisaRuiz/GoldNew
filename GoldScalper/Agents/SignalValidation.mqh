//+------------------------------------------------------------------+
//| SignalValidationAgent.mqh - Signal validation agent              |
//| Ports Python signal_validation_agent.py: LLM validation with     |
//| Anthropic (temp=0 deterministic), multi-inference consensus,     |
//| long shadow filter (pause line from EAS chino).                  |
//|                                                                  |
//| Best Practices:                                                  |
//| - Multi-inference (3 calls) for consensus (majority vote).       |
//| - Long shadow filter on recent candle to avoid pauses.           |
//| - Uses MarketAnalyzer's HttpPostJson for fetches.                |
//| - Integrates with SignalModule to override confidence.           |
//+------------------------------------------------------------------+
#ifndef SIGNAL_VALIDATION_AGENT_MQH
#define SIGNAL_VALIDATION_AGENT_MQH
#property strict

#include "MarketAnalyzer.mqh" // For HttpPostJson and CJsonNode
#include "SignalModule.mqh"   // For TradingSignal
#include "TraceAlert.mqh"     // For logging

// SignalValidationAgent class
class SignalValidationAgent
{
private:
   string m_anthropic_key; // API key
   int    m_num_inferences; // Number of inferences for consensus (e.g., 3)
   double m_conf_boost;     // Confidence boost if consensus valid (e.g., 0.1)

   /**
    * Performs a single LLM validation call using Anthropic API.
    * @param prompt The prompt for validation.
    * @param out_valid Reference to store valid flag.
    * @param out_reason Reference to store reason.
    * @return True if call succeeds, false otherwise.
    */
   bool SingleLLMCall(string prompt, bool &out_valid, string &out_reason)
   {
      string url = "https://api.anthropic.com/v1/complete";
      string body = "{\"prompt\": \"" + prompt + "\", \"model\": \"claude-2\", \"temperature\": 0, \"max_tokens_to_sample\": 100}";
      string headers = "Authorization: Bearer " + m_anthropic_key + "\r\n";
      CJsonNode j;
      if (!HttpPostJson(url, body, j, headers))
      {
         return false;
      }
      CJsonNode *completion = j.GetChildByKey("completion");
      if (completion == NULL) return false;
      CJsonNode parsed;
      if (!parsed.ParseString(completion.AsString())) return false;
      out_valid = parsed.GetChildByKey("valid").AsBool();
      out_reason = parsed.GetChildByKey("reason").AsString();
      return true;
   }

   /**
    * Applies long shadow filter (pause line from EAS chino) on recent candle.
    * Checks if upper or lower shadow > body * 2.
    * @param symbol The symbol to check.
    * @param tf The timeframe.
    * @return True if no long shadow (pass), false if long shadow detected (filter out).
    */
   bool LongShadowFilter(string symbol, ENUM_TIMEFRAMES tf)
   {
      MqlRates rates[1];
      if (CopyRates(symbol, tf, 1, 1, rates) != 1) return false; // Get last completed candle

      double body = MathAbs(rates[0].open - rates[0].close);
      double upper_shadow = rates[0].high - MathMax(rates[0].open, rates[0].close);
      double lower_shadow = MathMin(rates[0].open, rates[0].close) - rates[0].low;

      if (upper_shadow > body * 2 || lower_shadow > body * 2)
      {
         g_trace.Log(TRACE_WARN, "VALIDATION", "Long shadow detected - filtering signal");
         return false; // Filter out
      }
      return true; // Pass
   }

public:
   /**
    * Constructor for SignalValidationAgent.
    * @param anthropic_key The Anthropic API key.
    * @param num_inferences Number of inferences for consensus (default 3).
    * @param conf_boost Confidence boost if consensus valid (default 0.1).
    */
   SignalValidationAgent(string anthropic_key, int num_inferences = 3, double conf_boost = 0.1)
   {
      m_anthropic_key = anthropic_key;
      m_num_inferences = num_inferences;
      m_conf_boost = conf_boost;
   }

   /**
    * Validates a signal using multi-inference LLM consensus and long shadow filter.
    * Overrides confidence if valid (adds boost based on consensus strength).
    * @param sig Reference to TradingSignal to validate and modify.
    * @param symbol The symbol for context.
    * @param tf The timeframe for long shadow check.
    * @return True if signal is valid after validation, false otherwise.
    */
   bool Validate(TradingSignal &sig, string symbol, ENUM_TIMEFRAMES tf)
   {
      if (StringLen(m_anthropic_key) == 0) return false;

      // Step 1: Long shadow filter
      if (!LongShadowFilter(symbol, tf))
      {
         sig.valid = false;
         sig.reason = "Long shadow filter rejected";
         return false;
      }

      // Step 2: Multi-inference LLM consensus
      string prompt = StringFormat("Validate signal for %s: Type=%s, Confidence=%.2f, RSI=%.2f, MACD=%.2f. Criteria: RSI>30, MACD>0, Confidence>0.75. Output: valid (true/false), reason.", symbol, EnumToString(sig.type), sig.confidence, sig.rsi, sig.macd);

      int valid_count = 0;
      string reasons = "";
      for (int i = 0; i < m_num_inferences; i++)
      {
         bool llm_valid;
         string llm_reason;
         if (SingleLLMCall(prompt, llm_valid, llm_reason))
         {
            if (llm_valid) valid_count++;
            reasons += llm_reason + "; ";
         }
         else
         {
            g_trace.Log(TRACE_WARN, "VALIDATION", "LLM call failed - skipping inference " + IntegerToString(i));
         }
      }

      // Consensus: Majority vote
      bool consensus_valid = (valid_count > m_num_inferences / 2);
      if (consensus_valid)
      {
         // Override confidence: Boost based on consensus strength
         double strength = (double)valid_count / m_num_inferences;
         sig.confidence += strength * m_conf_boost;
         sig.confidence = MathMin(1.0, sig.confidence);
         sig.reason = "Consensus valid: " + reasons;
         return true;
      }
      else
      {
         sig.valid = false;
         sig.reason = "Consensus rejected: " + reasons;
         return false;
      }
   }
};

#endif // SIGNAL_VALIDATION_AGENT_MQH