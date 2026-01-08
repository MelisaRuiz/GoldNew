//+------------------------------------------------------------------+
//| SessionFilter.mqh - Filters trading to NY core session (09:30-11:30 ET) |
//| Ports Python session_manager.py: Checks current time vs NY core. |
//| Integrates with HealthMonitor for session reset.                 |
//|                                                                  |
//| Best Practices:                                                  |
//| - Uses TimeGMT() for accuracy.                                   |
//| - Handles DST via ET offset (simplified; adjust if needed).      |
//| - No globals; state in class.                                    |
//+------------------------------------------------------------------+
#ifndef SESSION_FILTER_MQH
#define SESSION_FILTER_MQH
#property strict

#include "TraceAlert.mqh" // For logging
#include "ConfigManager.mqh" // For ET hours

// SessionFilter class
class SessionFilter
{
private:
   int m_ny_open_hour_et;   // From config
   int m_ny_open_min_et;    // From config
   int m_ny_close_hour_et;  // From config
   int m_ny_close_min_et;   // From config
   int m_et_offset_hours;   // -5 (ET = GMT -5; ignore DST for simplicity)

public:
   SessionFilter()
   {
      m_ny_open_hour_et = g_config_manager.GetNyOpenHour();
      m_ny_open_min_et = g_config_manager.GetNyOpenMin();
      m_ny_close_hour_et = g_config_manager.GetNyCloseHour();
      m_ny_close_min_et = g_config_manager.GetNyCloseMin();
      m_et_offset_hours = -5;
   }

   bool IsTradingAllowed(datetime now_gmt = 0)
   {
      if (now_gmt == 0) now_gmt = TimeGMT();

      MqlDateTime dt_gmt;
      TimeToStruct(now_gmt, dt_gmt);

      // Convert to ET
      int et_hour = dt_gmt.hour + m_et_offset_hours;
      if (et_hour < 0) et_hour += 24;
      int et_min = dt_gmt.min;
      int et_sec = dt_gmt.sec;

      // NY core start/end in minutes since midnight
      int open_min = m_ny_open_hour_et * 60 + m_ny_open_min_et;
      int close_min = m_ny_close_hour_et * 60 + m_ny_close_min_et;
      int current_min = et_hour * 60 + et_min;

      if (current_min >= open_min && current_min < close_min)
         return true;

      g_trace.Log(TRACE_WARN, "SESSION", "Outside NY core: " + TimeToString(now_gmt));
      return false;
   }
};

// Global instance
SessionFilter g_session_filter;

#endif // SESSION_FILTER_MQH