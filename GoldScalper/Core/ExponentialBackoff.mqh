//+------------------------------------------------------------------+
//| ExponentialBackoff.mqh - Ported from Python exponential_backoff.py|
//| Implements retry logic with strategies (exponential, fibonacci,  |
//| linear, constant, aggressive). Aggressive: 50ms base.            |
//| Integrates with HealthMonitor for API/fetch retries and enhanced |
//| breakers on critical errors.                                     |
//|                                                                  |
//| Best Practices:                                                  |
//| - Deterministic delays with jitter option                        |
//| - Metrics tracking for audit                                     |
//| - Critical error detection to trigger breakers                   |
//+------------------------------------------------------------------+
#ifndef EXPONENTIAL_BACKOFF_MQH
#define EXPONENTIAL_BACKOFF_MQH
#property strict

#include "HealthMonitor.mqh" // For integration
#include "ConfigManager.mqh" // Updated

// Enums ported from Python
enum BackoffStrategy
{
   STRATEGY_EXPONENTIAL = 0,
   STRATEGY_FIBONACCI,
   STRATEGY_LINEAR,
   STRATEGY_CONSTANT,
   STRATEGY_AGGRESSIVE  // For quick recovery in HFT
};

// BackoffConfig struct - Ported from dataclass
struct BackoffConfig
{
   string operation_name;
   int    max_retries;       // Default 3
   double base_delay;        // Seconds, default 0.1
   double max_delay;         // Default 5.0
   BackoffStrategy strategy; // Default EXPONENTIAL
   bool   jitter;            // Default true
   double timeout;           // Optional, 0 if none
   string critical_errors[]; // List of critical error strings
   bool   retry_on_timeout;  // Default true
   bool   circuit_breaker_integration; // Default true
   double target_latency_ms; // Default 50.0
};

// RetryMetrics struct - For monitoring
struct RetryMetrics
{
   string total_attempts;
   int    total_attempts;
   int    successful_attempts;
   int    failed_attempts;
   double total_retry_delay;
   double average_retry_time;
   string last_error;
   int    consecutive_failures;
   int    circuit_breaker_triggers;
};

// ExponentialBackoff class - Core port
class ExponentialBackoff
{
private:
   BackoffConfig m_config;
   RetryMetrics  m_metrics;
   int           m_fibonacci_seq[20];  // Pre-generated Fibonacci

   // Helper: Generate Fibonacci sequence
   void GenerateFibonacci()
   {
      m_fibonacci_seq[0] = 0;
      m_fibonacci_seq[1] = 1;
      for (int i = 2; i < 20; i++)
         m_fibonacci_seq[i] = m_fibonacci_seq[i-1] + m_fibonacci_seq[i-2];
   }

   // Calculate delay based on strategy
   double CalculateDelay(int attempt)
   {
      if (attempt == 0) return 0.0;

      double delay = 0.0;
      switch (m_config.strategy)
      {
         case STRATEGY_EXPONENTIAL:
            delay = MathMin(m_config.base_delay * MathPow(2, attempt), m_config.max_delay);
            break;
         case STRATEGY_FIBONACCI:
            int fib_index = MathMin(attempt, 19);
            delay = MathMin(m_config.base_delay * m_fibonacci_seq[fib_index], m_config.max_delay);
            break;
         case STRATEGY_LINEAR:
            delay = MathMin(m_config.base_delay * attempt, m_config.max_delay);
            break;
         case STRATEGY_CONSTANT:
            delay = m_config.base_delay;
            break;
         case STRATEGY_AGGRESSIVE:
            delay = MathMin(m_config.base_delay * MathPow(1.5, attempt), m_config.max_delay / 2.0);
            break;
      }

      // Apply jitter
      if (m_config.jitter && delay > 0.0)
         delay = MathRand() / 32767.0 * delay + 0.5 * delay;  // Uniform 0.5-1.5 * delay

      return delay;
   }

   // Check if error is critical
   bool IsCriticalError(string error_str)
   {
      StringToLower(error_str);
      for (int i = 0; i < ArraySize(m_config.critical_errors); i++)
      {
         if (StringFind(error_str, m_config.critical_errors[i]) != -1) return true;
      }
      return false;
   }

   // Determine if should retry
   bool ShouldRetry(string error, int attempt)
   {
      if (attempt >= m_config.max_retries) return false;
      if (IsCriticalError(error)) return false;
      // Timeout check if applicable (handled externally in MQL5)
      // Circuit breaker: Integrate with HealthMonitor
      if (m_config.circuit_breaker_integration && g_health_monitor.GetState() == HEALTH_HALTED) return false;
      return true;
   }

public:
   ExponentialBackoff(BackoffConfig &config)
   {
      m_config = config;
      ZeroMemory(m_metrics);
      m_metrics.operation_name = config.operation_name;
      GenerateFibonacci();
   }

   // Execute with retries: Takes a function pointer returning bool success, returns bool
   typedef bool (*FetchFunc)();  // Function to retry, returns true on success
   bool Execute(FetchFunc func, string &out_error)  // out_error for last error
   {
      datetime start_time = TimeCurrent();
      out_error = "";
      int attempt = 0;

      while (attempt <= m_config.max_retries)
      {
         m_metrics.total_attempts++;

         double delay = CalculateDelay(attempt);
         if (delay > 0.0) Sleep((int)(delay * 1000));  // Delay in ms
         m_metrics.total_retry_delay += delay;

         if (func())
         {
            m_metrics.successful_attempts++;
            m_metrics.consecutive_failures = 0;
            // Log success if retried
            if (attempt > 0) Print("RETRY_SUCCESS: Operation=", m_config.operation_name, " Attempts=", attempt + 1);
            return true;
         }
         else
         {
            m_metrics.failed_attempts++;
            m_metrics.consecutive_failures++;
            out_error = "Fetch failed";  // Placeholder; enhance with actual error if possible
            m_metrics.last_error = out_error;

            // Check if retry
            if (!ShouldRetry(out_error, attempt))
            {
               Print("RETRY_CRITICAL_FAILURE: Operation=", m_config.operation_name, " Error=", out_error);
               break;
            }

            // Log retry
            if (attempt < m_config.max_retries)
               Print("RETRY_ATTEMPT: Operation=", m_config.operation_name, " Attempt=", attempt + 1);

            // Trigger HealthMonitor breaker if consecutive high
            if (m_config.circuit_breaker_integration && m_metrics.consecutive_failures >= 3)
            {
               g_health_monitor.SetState(HEALTH_CRITICAL);
               m_metrics.circuit_breaker_triggers++;
            }
         }

         attempt++;
      }

      // Failure
      double total_time = TimeCurrent() - start_time;
      m_metrics.average_retry_time = total_time / (double)MathMax(m_metrics.total_attempts, 1);
      Print("RETRY_FINAL_FAILURE: Operation=", m_config.operation_name, " Total Attempts=", m_metrics.total_attempts, " Error=", out_error);
      return false;
   }

   // Get metrics as string for logging
   string GetMetrics()
   {
      return StringFormat("Success Rate: %.2f, Total Delay: %.2f, Avg Time: %.2f, Consec Fails: %d",
                          (double)m_metrics.successful_attempts / (double)MathMax(m_metrics.total_attempts, 1),
                          m_metrics.total_retry_delay, m_metrics.average_retry_time, m_metrics.consecutive_failures);
   }

   void ResetMetrics()
   {
      ZeroMemory(m_metrics);
      m_metrics.operation_name = m_config.operation_name;
   }
};

#endif  // EXPONENTIAL_BACKOFF_MQH