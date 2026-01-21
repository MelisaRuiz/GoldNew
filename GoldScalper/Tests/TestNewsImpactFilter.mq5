//+------------------------------------------------------------------+
//| TestNewsImpactFilter.mq5                                         |
//| Test fetch, Refresh() y IsTradingAllowed con mock JSON           |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "../Core/NewsImpactFilter.mqh"

// Mock WebRequest: Retorna JSON fijo con formato faireconomy
#define WebRequest MockWebRequest
static int g_mock_call_count = 0;
int MockWebRequest(string method, string url, string headers, int timeout, char &post[], char &result[], string &out_headers)
{
   g_mock_call_count++;
   
   // Create mock JSON in faireconomy format with high-impact event
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   string date_str = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
   string time_str = StringFormat("%02d:%02d", dt.hour, dt.min);
   
   // High-impact event happening now (within window)
   string mock_json = "["
      "{\"id\":\"1\",\"event\":\"Test High Impact Event\",\"date\":\"" + date_str + "\",\"time\":\"" + time_str + "\","
      "\"currency\":\"USD\",\"impact\":\"High\",\"actual\":0.0,\"forecast\":0.0,\"previous\":0.0},"
      "{\"id\":\"2\",\"event\":\"Old Low Impact Event\",\"date\":\"2023-01-01\",\"time\":\"00:00\","
      "\"currency\":\"EUR\",\"impact\":\"Low\",\"actual\":0.0,\"forecast\":0.0,\"previous\":0.0}"
   "]";
   
   StringToCharArray(mock_json, result);
   return 200;
}

void OnStart()
{
   Print("=== TestNewsImpactFilter: Starting tests ===");
   int passed = 0;
   int failed = 0;
   
   NewsImpactFilter filter;
   filter.Init();
   
   // Test 1: Refresh() should fetch news on first call
   g_mock_call_count = 0;
   bool refresh_result = filter.Refresh();
   int event_count = filter.GetEventsCount();
   
   if(refresh_result && event_count > 0 && g_mock_call_count > 0)
   {
      Print("Test 1 (Refresh - first call): PASSED - Events: ", event_count, ", WebRequest calls: ", g_mock_call_count);
      passed++;
   }
   else
   {
      Print("Test 1 (Refresh - first call): FAILED - refresh_result=", refresh_result, ", events=", event_count, ", calls=", g_mock_call_count);
      failed++;
   }
   
   // Test 2: Refresh() should respect throttle (not call FetchNews if <300s)
   datetime last_fetch = filter.GetLastFetch();
   g_mock_call_count = 0;
   bool refresh_result2 = filter.Refresh();
   int event_count2 = filter.GetEventsCount();
   
   if(refresh_result2 && g_mock_call_count == 0)
   {
      Print("Test 2 (Refresh - throttle): PASSED - Throttled correctly, no new WebRequest call");
      passed++;
   }
   else
   {
      Print("Test 2 (Refresh - throttle): FAILED - Expected throttle but got calls=", g_mock_call_count);
      failed++;
   }
   
   // Test 3: IsTradingAllowed should return false for high-impact event
   // Create a high-impact event that affects current symbol
   NewsEvent test_events[];
   ArrayResize(test_events, 1);
   test_events[0].id = "test_high";
   test_events[0].title = "High Impact Test Event";
   test_events[0].start = TimeCurrent() - 30*60; // 30 minutes ago
   test_events[0].end = TimeCurrent() + 30*60;   // 30 minutes from now
   test_events[0].impact = NEWS_HIGH;
   test_events[0].currency = "USD";
   ArrayResize(test_events[0].symbols, 1);
   test_events[0].symbols[0] = "USD";
   test_events[0].actual = 0.0;
   test_events[0].forecast = 0.0;
   test_events[0].previous = 0.0;
   
   filter.SetEvents(test_events);
   bool trading_allowed = filter.IsTradingAllowed("XAUUSD"); // Gold often affected by USD news
   
   if(!trading_allowed)
   {
      Print("Test 3 (IsTradingAllowed - high-impact blocked): PASSED - Trading correctly blocked");
      passed++;
   }
   else
   {
      Print("Test 3 (IsTradingAllowed - high-impact blocked): FAILED - Trading should be blocked");
      failed++;
   }
   
   // Test 4: CheckEventImpact should return proper result structure
   NewsImpactResult impact_result = filter.CheckEventImpact("XAUUSD");
   if(impact_result.impact == NEWS_HIGH && !impact_result.trading_allowed && StringLen(impact_result.reason) > 0)
   {
      Print("Test 4 (CheckEventImpact - structure): PASSED - impact=", impact_result.impact, ", reason=", impact_result.reason);
      passed++;
   }
   else
   {
      Print("Test 4 (CheckEventImpact - structure): FAILED - impact=", impact_result.impact, ", allowed=", impact_result.trading_allowed);
      failed++;
   }
   
   Print("=== Test Summary: ", passed, " passed, ", failed, " failed ===");
}

#undef WebRequest  // Restaurar original