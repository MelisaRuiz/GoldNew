//+------------------------------------------------------------------+
//|  GoldScalper.mq5                                                  |
//|  Unified EA: GoldScalper (modular)                                |
//+------------------------------------------------------------------+
#property copyright "GoldScalper / Melisa Ruiz"
#property link    "https://github.com/MelisaRuiz/GoldNew"
#property version "1.06"
#property strict

#include <Trade\Trade.mqh>
#include <Crypt.mqh>              // for local SHA256 if needed

#include "Core/StateManager.mqh"
#include "Agents/AgentOrchestrator.mqh"
#include "Core/NewsImpactFilter.mqh"
#include "Core/ExecutionEngine.mqh"
#include "Core/ExponentialBackoff.mqh"
#include "Core/RiskManager.mqh"
#include "Core/SpreadMonitor.mqh"
#include "Core/SessionManager.mqh"
#include "Monitoring/TraceAlert.mqh"
#include "Monitoring/HealthMonitor.mqh"

// Global instances expected by modules
extern ExecutionEngine g_execution_engine;
extern RiskManager g_risk_manager;
extern StateManager g_state_manager;
extern SpreadMonitor g_spread_monitor;
extern SessionManager g_session_manager;
extern TraceAlert g_trace;
extern HealthMonitor *g_health_monitor;

// Local expected map (fallback only)
static ulong  g_expected_ids[];   // key (order/ticket or client id)
static double g_expected_vols[];  // value (remaining expected volume)
static string g_run_id = "";

// Helper: compute SHA256 hex locally (best-effort)
string ComputeSha256HexLocal(const string s)
{
   #ifdef __MQL5__
      uchar in_bytes[]; int in_len = StringToCharArray(s, in_bytes);
      if(in_len <= 0) return "";
      uchar hash[]; ArrayResize(hash, 32);
      bool ok = CryptEncode(CRYPT_HASH_SHA256, in_bytes, hash);
      if(!ok) return "";
      string hex = "";
      for(int i=0;i<ArraySize(hash);i++) hex += StringFormat("%02X", hash[i]);
      return hex;
   #else
      return "";
   #endif
}

// Atomic file write helper (best-effort)
bool AtomicWriteFile(const string filename, string &lines[], int count)
{
   string tmp = filename + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE | FILE_COMMON | FILE_ANSI);
   if(h == INVALID_HANDLE) { g_trace.Log(TRACE_ERROR, "STATE", "AtomicWriteFile open tmp failed "+tmp); return false; }
   for(int i=0;i<count;i++) FileWriteString(h, lines[i] + "\n");
   FileClose(h);

   // Write final by reading tmp content and writing it to final file (reduce partial window)
   int htmp = FileOpen(tmp, FILE_READ | FILE_COMMON | FILE_ANSI);
   if(htmp == INVALID_HANDLE) { FileDelete(tmp); g_trace.Log(TRACE_ERROR, "STATE", "AtomicWriteFile reopen tmp failed"); return false; }
   string content = "";
   while(!FileIsEnding(htmp)) content += FileReadString(htmp);
   FileClose(htmp);

   int hdest = FileOpen(filename, FILE_WRITE | FILE_COMMON | FILE_ANSI);
   if(hdest == INVALID_HANDLE) { FileDelete(tmp); g_trace.Log(TRACE_ERROR, "STATE", "AtomicWriteFile open dest failed "+filename); return false; }
   FileWriteString(hdest, content);
   FileClose(hdest);

   FileDelete(tmp);
   return true;
}

void ExpectedMapSaveToFile()
{
   string filename = "expected_map.csv";
   int cnt = ArraySize(g_expected_ids);
   string lines[]; ArrayResize(lines, cnt);
   for(int i=0;i<cnt;i++)
   {
      // fields: id,vol,run_id,trace_hash
      string canon = StringFormat("%llu|%.10f|%s", (ulong)g_expected_ids[i], g_expected_vols[i], g_run_id);
      string hash = ComputeSha256HexLocal(canon);
      lines[i] = StringFormat("%llu,%.10f,%s,%s", (ulong)g_expected_ids[i], g_expected_vols[i], g_run_id, hash);
   }
   if(!AtomicWriteFile(filename, lines, cnt)) g_trace.Log(TRACE_WARNING, "STATE", "ExpectedMapSaveToFile failed");
   else g_trace.Log(TRACE_DEBUG, "STATE", StringFormat("Expected map saved (%d entries) to %s", cnt, filename));
}

void ExpectedMapLoadFromFile()
{
   ArrayResize(g_expected_ids, 0);
   ArrayResize(g_expected_vols, 0);
   string filename = "expected_map.csv";
   int h = FileOpen(filename, FILE_READ | FILE_COMMON | FILE_ANSI);
   if(h == INVALID_HANDLE) { g_trace.Log(TRACE_DEBUG, "STATE", "ExpectedMapLoadFromFile: no file (ok)"); return; }
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      if(StringLen(line) <= 0) continue;
      string parts[]; int n = StringSplit(line, ',', parts);
      if(n < 2) continue;
      ulong id = (ulong)StringToInteger(parts[0]);
      double vol = StringToDouble(parts[1]);
      ArrayResize(g_expected_ids, ArraySize(g_expected_ids)+1);
      ArrayResize(g_expected_vols, ArraySize(g_expected_vols)+1);
      g_expected_ids[ArraySize(g_expected_ids)-1] = id;
      g_expected_vols[ArraySize(g_expected_vols)-1] = vol;
   }
   FileClose(h);
   g_trace.Log(TRACE_DEBUG, "STATE", StringFormat("Expected map loaded (%d entries)", ArraySize(g_expected_ids)));
}

void ExpectedMapAdd(ulong key, double vol)
{
   if(key == 0) return;
   for(int i=0;i<ArraySize(g_expected_ids);i++)
      if(g_expected_ids[i] == key) { g_expected_vols[i] = vol; ExpectedMapSaveToFile(); return; }
   int n = ArraySize(g_expected_ids);
   ArrayResize(g_expected_ids, n+1);
   ArrayResize(g_expected_vols, n+1);
   g_expected_ids[n] = key; g_expected_vols[n] = vol;
   ExpectedMapSaveToFile();
}

bool ExpectedMapTryGet(ulong key, double &out_vol)
{
   for(int i=0;i<ArraySize(g_expected_ids);i++)
      if(g_expected_ids[i] == key) { out_vol = g_expected_vols[i]; return true; }
   return false;
}

void ExpectedMapDelete(ulong key)
{
   for(int i=0;i<ArraySize(g_expected_ids);i++)
      if(g_expected_ids[i] == key)
      {
         int last = ArraySize(g_expected_ids)-1;
         if(i != last) { g_expected_ids[i] = g_expected_ids[last]; g_expected_vols[i] = g_expected_vols[last]; }
         ArrayResize(g_expected_ids, last); ArrayResize(g_expected_vols, last);
         ExpectedMapSaveToFile();
         return;
      }
}

// parse symbols list (same as before)
static string g_symbols[]; static int g_symbols_count = 0;
void ParseSymbolsList() { /* existing parsing logic, omitted for brevity in this snippet */ }

// OnInit / OnDeinit
int OnInit()
{
   g_run_id = StringFormat("%d_%d", (int)TimeCurrent(), (int)(MathRand() & 0xFFFF));
   ExpectedMapLoadFromFile();
   // other init steps omitted for brevity...
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ExpectedMapSaveToFile();
}

// OnTimer, OnTradeTransaction (key parts shown)
// OnTradeTransaction must attempt to correlate order->pending and persist EA map
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   // correlate key prefer order > deal > req.request_id
   ulong key = 0;
   if(trans.order > 0) key = (ulong)trans.order;
   else if(trans.deal > 0) key = (ulong)trans.deal;
   else if(req.request_id > 0) key = (ulong)req.request_id;

   // First let ExecutionEngine reconcile authoritative map
   g_execution_engine.HandleTradeTransaction(trans, req, res);

   // second update EA fallback expected_map.csv for demo
   double expected = 0.0;
   if(key != 0 && ExpectedMapTryGet(key, expected))
   {
      double filled_vol = 0.0;
      if(trans.volume > 0.0) filled_vol = trans.volume;
      else if(res.volume > 0.0) filled_vol = res.volume;
      double remaining = expected;
      if(filled_vol > 0.0) remaining = MathMax(0.0, expected - filled_vol);

      if(remaining <= 1e-9) ExpectedMapDelete(key);
      else ExpectedMapAdd(key, remaining);
   }

   // record with RiskManager (existing)
   double pnl = trans.profit;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl_pct = (equity != 0.0) ? (pnl / equity * 100.0) : 0.0;
   bool is_win = pnl > 0.0;
   g_risk_manager.RecordTrade((ulong)trans.order, is_win, pnl_pct);

   // persist EA-level state
   g_state_manager.Save();
}
