//+------------------------------------------------------------------+
//| TestNewsImpactFilter.mq5                                         |
//| Test fetch y IsTradingAllowed con mock JSON                      |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "../Core/NewsImpactFilter.mqh"

// Mock WebRequest: Retorna JSON fijo
#define WebRequest MockWebRequest
int MockWebRequest(string method, string url, string headers, int timeout, char &post[], char &result[], string &out_headers)
{
   string mock_json = "[{\"date\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + ":00Z\", \"country\":\"USD\", \"impact\":\"High\", \"name\":\"Test Event\"}, {\"date\":\"2023-01-01T00:00:00Z\", \"country\":\"USD\", \"impact\":\"Low\", \"name\":\"Old Event\"}]";
   StringToCharArray(mock_json, result);
   return 200;
}

void OnStart()
{
   NewsImpactFilter filter;

   // Test FetchNews: Actualiza m_events
   filter.FetchNews();
   if(filter.m_event_count > 0) Print("Test Fetch: PASSED - Events: ", filter.m_event_count);
   else Print("Test Fetch: FAILED");

   // Test IsHighImpactWindow: Debe ser true para evento actual (ventana)
   if(filter.IsHighImpactWindow()) Print("Test HighImpact (durante ventana): PASSED");
   else Print("Test HighImpact: FAILED");

   // Simular tiempo fuera de ventana
   // (Manual: Cambia TimeCurrent() mock si necesario)
   if(!filter.IsTradingAllowed()) Print("Test TradingAllowed (bloqueado): PASSED");
   else Print("Test TradingAllowed: FAILED");
}

#undef WebRequest  // Restaurar original