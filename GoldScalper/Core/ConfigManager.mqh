//+------------------------------------------------------------------+
//| ConfigManager.mqh - Merged Config and ImmutableCore |
//| Centralized constants with validation for Gold Scalper EA |
//+------------------------------------------------------------------+
#ifndef _CONFIG_MANAGER_MQH_
#define _CONFIG_MANAGER_MQH_
#property strict
//------------------ Enums & Structs --------------------------------
enum RiskLevel
{
   LOW_RISK = 0,
   MEDIUM_RISK,
   HIGH_RISK
};
struct ConfigManagerConfig
{
   // From Config
   string alpha_key;
   string fred_key;
   double min_confidence;
   double default_rr;
   int ny_open_hour;
   int ny_open_min;
   int ny_close_hour;
   int ny_close_min;
   int lookback_bars;
   double min_zone_strength;
   double atr_multiplier;
   double min_fvg_points;
   double high_spread_threshold;
   int cache_ttl;
   // From ImmutableCore
   double min_rr;
   double max_rr;
   ENUM_TIMEFRAMES primary_tf;
   ENUM_TIMEFRAMES confirm_tf;
   double ob_tolerance_pts;
   string allowed_symbols[];
   double max_lot_size;
   double base_risk_pct;
   int max_consec_losses;
   double max_dd_pct;
   double sl_multiplier;
   RiskLevel risk_level;
};
struct ConfigStatus
{
   bool valid;
   string message;
};
//------------------ ConfigManager Class -----------------------------
class ConfigManager
{
private:
   ConfigManagerConfig m_config;
   bool m_valid;
   string m_error;
   void ValidateConfig()
   {
      m_valid = true;
      m_error = "";
      // Validate from original Config (mostly >0 checks)
      if (m_config.min_confidence < 0.0 || m_config.min_confidence > 1.0)
      {
         m_valid = false;
         m_error += "Min confidence out of range (0-1); ";
      }
      if (m_config.default_rr <= 0.0)
      {
         m_valid = false;
         m_error += "Default RR must be >0; ";
      }
      if (m_config.lookback_bars <= 0)
      {
         m_valid = false;
         m_error += "Lookback bars must be >0; ";
      }
      if (m_config.min_zone_strength < 1.0 || m_config.min_zone_strength > 10.0)
      {
         m_valid = false;
         m_error += "Min zone strength out of range (1-10); ";
      }
      if (m_config.atr_multiplier <= 0.0)
      {
         m_valid = false;
         m_error += "ATR multiplier must be >0; ";
      }
      if (m_config.min_fvg_points <= 0.0)
      {
         m_valid = false;
         m_error += "Min FVG points must be >0; ";
      }
      if (m_config.high_spread_threshold <= 0.0)
      {
         m_valid = false;
         m_error += "High spread threshold must be >0; ";
      }
      if (m_config.cache_ttl <= 0)
      {
         m_valid = false;
         m_error += "Cache TTL must be >0; ";
      }
      // Validate from ImmutableCore
      if (m_config.min_rr <= 0.0 || m_config.min_rr >= m_config.max_rr)
         { m_valid = false; m_error += "Invalid RR range; "; }
      if (m_config.atr_multiplier <= 0.0)
         { m_valid = false; m_error += "Invalid ATR multiplier; "; }
      if (m_config.primary_tf == PERIOD_CURRENT || m_config.confirm_tf == PERIOD_CURRENT)
         { m_valid = false; m_error += "Invalid timeframes; "; }
      if (m_config.min_zone_strength <= 0.0)
         { m_valid = false; m_error += "Invalid min zone strength; "; }
      if (m_config.min_fvg_points <= 0.0)
         { m_valid = false; m_error += "Invalid min FVG points; "; }
      if (m_config.high_spread_threshold <= 0.0)
         { m_valid = false; m_error += "Invalid spread threshold; "; }
      if (m_config.lookback_bars <= 0)
         { m_valid = false; m_error += "Invalid lookback bars; "; }
      if (m_config.min_confidence < 0.0 || m_config.min_confidence > 1.0)
         { m_valid = false; m_error += "Invalid min confidence; "; }
      if (m_config.ob_tolerance_pts <= 0.0)
         { m_valid = false; m_error += "Invalid OB tolerance; "; }
      if (ArraySize(m_config.allowed_symbols) == 0)
         { m_valid = false; m_error += "No allowed symbols; "; }
      if (m_config.max_lot_size <= 0.0)
         { m_valid = false; m_error += "Invalid max lot size; "; }
      if (m_config.base_risk_pct <= 0.0 || m_config.base_risk_pct > 1.0)
         { m_valid = false; m_error += "Invalid base risk pct; "; }
      if (m_config.max_consec_losses <= 0)
         { m_valid = false; m_error += "Invalid max consec losses; "; }
      if (m_config.max_dd_pct <= 0.0 || m_config.max_dd_pct > 100.0)
         { m_valid = false; m_error += "Invalid max DD pct; "; }
      if (m_config.sl_multiplier <= 0.0)
         { m_valid = false; m_error += "Invalid SL multiplier; "; }
      if (StringLen(m_error) > 0)
      {
         Print("ConfigManager validation failed: ", m_error);
      }
   }
public:
   ConfigManager(const ConfigManagerConfig &config)
   {
      m_config = config;
      ValidateConfig();
   }
   bool IsValid() const { return m_valid; }
   string GetError() const { return m_error; }
   ConfigStatus GetStatus() const
   {
      ConfigStatus status;
      status.valid = m_valid;
      status.message = m_valid ? "OK" : m_error;
      return status;
   }
   // Getters (read-only)
   string GetAlphaKey() const { return m_config.alpha_key; }
   string GetFredKey() const { return m_config.fred_key; }
   double GetMinConfidence() const { return m_config.min_confidence; }
   double GetDefaultRR() const { return m_config.default_rr; }
   int GetNyOpenHour() const { return m_config.ny_open_hour; }
   int GetNyOpenMin() const { return m_config.ny_open_min; }
   int GetNyCloseHour() const { return m_config.ny_close_hour; }
   int GetNyCloseMin() const { return m_config.ny_close_min; }
   int GetLookbackBars() const { return m_config.lookback_bars; }
   double GetMinZoneStrength() const { return m_config.min_zone_strength; }
   double GetAtrMultiplier() const { return m_config.atr_multiplier; }
   double GetMinFvgPoints() const { return m_config.min_fvg_points; }
   double GetHighSpreadThreshold() const { return m_config.high_spread_threshold; }
   int GetCacheTtl() const { return m_config.cache_ttl; }
   double GetMinRR() const { if(!m_valid) Print(m_error); return m_config.min_rr; }
   double GetMaxRR() const { if(!m_valid) Print(m_error); return m_config.max_rr; }
   ENUM_TIMEFRAMES GetPrimaryTF() const { if(!m_valid) Print(m_error); return m_config.primary_tf; }
   ENUM_TIMEFRAMES GetConfirmTF() const { if(!m_valid) Print(m_error); return m_config.confirm_tf; }
   double GetObTolerancePts() const { if(!m_valid) Print(m_error); return m_config.ob_tolerance_pts; }
   void GetAllowedSymbols(string &syms[]) const
   {
      if(!m_valid) Print(m_error);
      ArrayResize(syms, ArraySize(m_config.allowed_symbols));
      ArrayCopy(syms, m_config.allowed_symbols);
   }
   double GetMaxLotSize() const { if(!m_valid) Print(m_error); return m_config.max_lot_size; }
   double GetBaseRiskPct() const { if(!m_valid) Print(m_error); return m_config.base_risk_pct; }
   int GetMaxConsecLosses() const { if(!m_valid) Print(m_error); return m_config.max_consec_losses; }
   double GetMaxDdPct() const { if(!m_valid) Print(m_error); return m_config.max_dd_pct; }
   double GetSlMultiplier() const { if(!m_valid) Print(m_error); return m_config.sl_multiplier; }
   RiskLevel GetRiskLevel() const { if(!m_valid) Print(m_error); return m_config.risk_level; }
};
#endif // _CONFIG_MANAGER_MQH_