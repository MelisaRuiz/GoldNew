//+------------------------------------------------------------------+
//| CircuitBreaker.mqh - Circuit breaker pattern for resilience      |
//| Ports Python infrastructure: States (CLOSED/OPEN/HALF_OPEN),     |
//| failure threshold, timeout reset. Integrates with HealthMonitor. |
//|                                                                  |
//| Best Practices:                                                  |
//| - Threshold-based state transitions.                             |
//| - Half-open for probation after timeout.                         |
//| - Metrics for audit.                                             |
//+------------------------------------------------------------------+
#ifndef CIRCUIT_BREAKER_MQH
#define CIRCUIT_BREAKER_MQH
#property strict

#include "TraceAlert.mqh" // For logging

enum BreakerState
{
   BREAKER_CLOSED = 0,   // Normal operation
   BREAKER_OPEN,         // Halted, backoff
   BREAKER_HALF_OPEN     // Probation mode
};

struct BreakerMetrics
{
   int    failure_count;
   int    success_count;
   datetime last_failure;
   datetime timeout_end;
};

// CircuitBreaker class
class CircuitBreaker
{
private:
   int          m_failure_threshold; // e.g., 5 failures to open
   datetime     m_timeout_duration;  // Seconds to half-open after open
   BreakerState m_state;
   BreakerMetrics m_metrics;

public:
   CircuitBreaker(int threshold = 5, int timeout_sec = 300)
   {
      m_failure_threshold = threshold;
      m_timeout_duration = timeout_sec;
      m_state = BREAKER_CLOSED;
      ZeroMemory(m_metrics);
   }

   /**
    * Records a failure and checks if breaker should open.
    */
   void RecordFailure()
   {
      m_metrics.failure_count++;
      m_metrics.last_failure = TimeCurrent();
      if (m_state == BREAKER_HALF_OPEN)
      {
         // Immediate open on failure in probation
         Open();
      }
      else if (m_metrics.failure_count >= m_failure_threshold)
      {
         Open();
      }
      g_trace.Log(TRACE_WARN, "BREAKER", "Failure recorded. Count: " + IntegerToString(m_metrics.failure_count));
   }

   /**
    * Records a success and resets counters if in half-open.
    */
   void RecordSuccess()
   {
      m_metrics.success_count++;
      if (m_state == BREAKER_HALF_OPEN)
      {
         Close();
      }
      else
      {
         m_metrics.failure_count = 0; // Reset on success
      }
      g_trace.Log(TRACE_INFO, "BREAKER", "Success recorded.");
   }

   /**
    * Checks if operation is allowed (not open).
    * Transitions half-open if timeout passed.
    * @return True if allowed, false if open.
    */
   bool IsAllowed()
   {
      if (m_state == BREAKER_OPEN && TimeCurrent() > m_metrics.timeout_end)
      {
         HalfOpen();
      }
      return m_state != BREAKER_OPEN;
   }

   // State transitions
   void Open()
   {
      m_state = BREAKER_OPEN;
      m_metrics.timeout_end = TimeCurrent() + m_timeout_duration;
      g_trace.Log(TRACE_CRITICAL, "BREAKER", "Circuit opened. Timeout until: " + TimeToString(m_metrics.timeout_end));
   }

   void HalfOpen()
   {
      m_state = BREAKER_HALF_OPEN;
      m_metrics.failure_count = 0;
      m_metrics.success_count = 0;
      g_trace.Log(TRACE_INFO, "BREAKER", "Circuit half-open (probation).");
   }

   void Close()
   {
      m_state = BREAKER_CLOSED;
      m_metrics.failure_count = 0;
      m_metrics.success_count = 0;
      g_trace.Log(TRACE_INFO, "BREAKER", "Circuit closed (normal).");
   }

   string GetStatus()
   {
      return EnumToString(m_state) + " Failures: " + IntegerToString(m_metrics.failure_count);
   }
};

#endif // CIRCUIT_BREAKER_MQH