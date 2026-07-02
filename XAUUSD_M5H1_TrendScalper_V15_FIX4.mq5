//+------------------------------------------------------------------+
//| XAUUSD_M5H1_TrendScalper_V15.mq5 |
//| Especificacion V1.5 — News filter corregido |
//| Trend Scalper Puro XAUUSD M5 sesgo H1 |
//+------------------------------------------------------------------+
#property copyright "Quantitative Architect"
#property link ""
#property version "1.50"
#property strict

//--- Input parameters
input group "=== TIMEFRAMES ==="
input ENUM_TIMEFRAMES Inp_EntryTF = PERIOD_M5; // Timeframe de entrada
input ENUM_TIMEFRAMES Inp_FilterTF = PERIOD_H1; // Timeframe de filtro/sesgo

input group "=== INDICATORS ==="
input int Inp_EMA_Fast = 9; // EMA rapida M5
input int Inp_SMA_Slow = 21; // SMA lenta H1
input int Inp_ADX_Period = 14; // Periodo ADX
input double Inp_ADX_Threshold = 20.0; // Umbral ADX
input int Inp_Momentum_Period = 6; // Periodo ROC
input double Inp_Mom_Long_Thr = 0.05; // Umbral ROC long (%)
input double Inp_Mom_Short_Thr = -0.05; // Umbral ROC short (%)
input int Inp_ATR_Spacing = 5; // ATR spacing
input int Inp_ATR_Ref = 14; // ATR referencia

input group "=== RISK MANAGEMENT ==="
input double Inp_Risk_PerTrade = 0.5; // Riesgo % por trade
input double Inp_SL_Factor_ATR = 1.2; // Factor ATR SL
input double Inp_SL_Struct_Buffer = 0.5; // Buffer ATR estructural
input double Inp_Min_RR = 1.5; // Minimo Risk:Reward
input double Inp_Daily_Loss_Limit = 2.0; // Limite perdida diaria %
input double Inp_Weekly_Loss_Limit = 4.0; // Limite perdida semanal %
input double Inp_Max_DD = 50.0; // Max drawdown % absoluto (temp: 50 for testing)

input group "=== OPERATIONAL FILTERS ==="
input int Inp_Max_Spread = 25; // Spread maximo (puntos)
input int Inp_Max_Slippage = 50; // Slippage maximo (puntos)
input int Inp_News_Before = 15; // Minutos antes de noticia
input int Inp_News_After = 30; // Minutos despues de noticia
input int Inp_Cooldown_Min = 30; // Cooldown post-perdida (min)

input group "=== SESSIONS ==="
input int Inp_London_Start = 8; // Inicio Londres (hora servidor)
input int Inp_London_End = 17; // Fin Londres
input int Inp_NY_Start = 13; // Inicio NY
input int Inp_NY_End = 22; // Fin NY
input bool Inp_Force_Close_End_Session = true; // Cerrar posiciones fin sesion

input group "=== STRUCTURE ==="
input int Inp_Swing_Lookback = 20; // Lookback fractales
input double Inp_Body_Ratio_Min = 0.45; // Min body/range

input group "=== EA SETTINGS ==="
input ulong Inp_MagicNumber = 123456; // Magic Number

//--- Global variables
double g_EquityStartDay;
double g_EquityStartWeek;
double g_EquityPeak;
datetime g_LastLossTime;
bool g_IsPaused;
bool g_IsKilled;

//--- Position open time tracking (for minimum hold time before structural invalidation)
datetime g_LastPositionOpenTime = 0;
input int Inp_MinHoldMinutes = 5; // Min hold time before structural invalidation (minutes)

//--- Indicator handles
int h_EMA_Fast;
int h_SMA_Slow;
int h_ADX;
int h_ATR5;
int h_ATR14;

//--- Swing buffers
struct SwingPoint
{
 double price;
 int bar_index;
 datetime time;
};

SwingPoint g_SwingHighs[];
SwingPoint g_SwingLows[];

//--- H1 bias state
bool g_H1_Bull = false;
bool g_H1_Bear = false;

//--- Daily tracking
static int g_last_day = -1;

//--- Weekly tracking using stored start date (robust against gaps)
static datetime g_week_start_time = 0;

//--- Cached bar data for closed candle [1]
struct BarData
{
 double close;
 double open;
 double high;
 double low;
 bool valid;
};
BarData g_BarM5;
BarData g_BarH1;

//--- Contract validation flag
bool g_ContractValidated = false;

//+------------------------------------------------------------------+
//| Expert initialization function |
//+------------------------------------------------------------------+
int OnInit()
{
 //--- Create indicator handles
 h_EMA_Fast = iMA(_Symbol, Inp_EntryTF, Inp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
 h_SMA_Slow = iMA(_Symbol, Inp_FilterTF, Inp_SMA_Slow, 0, MODE_SMA, PRICE_CLOSE);
 h_ADX = iADX(_Symbol, Inp_FilterTF, Inp_ADX_Period);
 h_ATR5 = iATR(_Symbol, Inp_EntryTF, Inp_ATR_Spacing);
 h_ATR14 = iATR(_Symbol, Inp_EntryTF, Inp_ATR_Ref);

 if(h_EMA_Fast == INVALID_HANDLE || h_SMA_Slow == INVALID_HANDLE ||
 h_ADX == INVALID_HANDLE || h_ATR5 == INVALID_HANDLE || h_ATR14 == INVALID_HANDLE)
 {
 Print("ERROR: No se pudieron crear los handles de indicadores");
 return(INIT_FAILED);
 }

 //--- Validate contract parameters for XAUUSD
 if(!ValidateContract())
 {
 Print("ERROR: Validacion de contrato XAUUSD fallida");
 return(INIT_FAILED);
 }
 g_ContractValidated = true;

 //--- Init risk metrics
 g_EquityStartDay = AccountInfoDouble(ACCOUNT_EQUITY);
 g_EquityStartWeek = AccountInfoDouble(ACCOUNT_EQUITY);
 g_EquityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
 g_LastLossTime = 0;
 g_IsPaused = false;
 g_IsKilled = false;

 //--- Init session tracking
 MqlDateTime dt;
 TimeToStruct(TimeCurrent(), dt);
 g_last_day = dt.day;
 g_week_start_time = GetWeekStart(TimeCurrent());

 Print("EA XAUUSD M5/H1 Trend Scalper V1.5 iniciado. Magic: ", Inp_MagicNumber);
 Print("Contract: TickSize=", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
 " TickValue=", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
 " ContractSize=", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
 " Digits=", (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
 return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Get start of current week (Monday 00:00) |
//+------------------------------------------------------------------+
datetime GetWeekStart(datetime time)
{
 MqlDateTime dt;
 TimeToStruct(time, dt);
 int days_since_monday = (dt.day_of_week + 6) % 7; // Monday=0, Sunday=6
 datetime week_start = time - (days_since_monday * 86400 + dt.hour * 3600 + dt.min * 60 + dt.sec);
 return week_start;
}

//+------------------------------------------------------------------+
//| Contract validation for XAUUSD |
//+------------------------------------------------------------------+
bool ValidateContract()
{
 double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
 double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
 double contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
 double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
 double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

 if(tick_size <= 0.0)
 {
 Print("ERROR: SYMBOL_TRADE_TICK_SIZE invalido: ", tick_size);
 return false;
 }
 if(tick_value <= 0.0)
 {
 Print("ERROR: SYMBOL_TRADE_TICK_VALUE invalido: ", tick_value);
 return false;
 }
 if(contract <= 0.0)
 {
 Print("ERROR: SYMBOL_TRADE_CONTRACT_SIZE invalido: ", contract);
 return false;
 }
 if(min_lot <= 0.0)
 {
 Print("ERROR: SYMBOL_VOLUME_MIN invalido: ", min_lot);
 return false;
 }
 if(lot_step <= 0.0)
 {
 Print("ERROR: SYMBOL_VOLUME_STEP invalido: ", lot_step);
 return false;
 }

 //--- Warn if contract size seems unusual for gold
 if(contract != 100.0 && contract != 1.0)
 {
 Print("WARNING: Contract size no estandar para XAUUSD: ", contract,
 " (esperado: 100 o 1)");
 }

 return true;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
 IndicatorRelease(h_EMA_Fast);
 IndicatorRelease(h_SMA_Slow);
 IndicatorRelease(h_ADX);
 IndicatorRelease(h_ATR5);
 IndicatorRelease(h_ATR14);

 Print("EA finalizado. Razon: ", reason);
}

//+------------------------------------------------------------------+
//| Update cached bar data for closed candles |
//| ALL signal decisions use closed candle [1], not live candle [0] |
//+------------------------------------------------------------------+
void UpdateBarData()
{
 g_BarM5.close = iClose(_Symbol, PERIOD_M5, 1);
 g_BarM5.open = iOpen(_Symbol, PERIOD_M5, 1);
 g_BarM5.high = iHigh(_Symbol, PERIOD_M5, 1);
 g_BarM5.low = iLow(_Symbol, PERIOD_M5, 1);
 g_BarM5.valid = (g_BarM5.close > 0.0 && g_BarM5.open > 0.0);

 g_BarH1.close = iClose(_Symbol, PERIOD_H1, 1);
 g_BarH1.open = iOpen(_Symbol, PERIOD_H1, 1);
 g_BarH1.high = iHigh(_Symbol, PERIOD_H1, 1);
 g_BarH1.low = iLow(_Symbol, PERIOD_H1, 1);
 g_BarH1.valid = (g_BarH1.close > 0.0 && g_BarH1.open > 0.0);
}

//+------------------------------------------------------------------+
//| Expert tick function |
//+------------------------------------------------------------------+
void OnTick()
{
 //--- 1. KILL SWITCH
 if(g_IsKilled)
 return;

 //--- 2. Update cached bar data (closed candles only)
 UpdateBarData();
 if(!g_BarM5.valid || !g_BarH1.valid)
 {
 Print("WARNING: Datos de barra no validos. Skip tick.");
 return;
 }

 //--- 3. Update risk metrics (daily/weekly resets)
 UpdateRiskMetrics();

 //--- 4. Check kill switch
 if(CheckKillSwitch())
 {
 CloseAllPositions();
 g_IsKilled = true;
 Print(">>> KILL SWITCH ACTIVADO. Drawdown maximo alcanzado.");
 return;
 }

 //--- 5. Check pause (daily/weekly limits)
 if(CheckPause())
 {
 if(!g_IsPaused)
 {
 g_IsPaused = true;
 Print(">>> PAUSE ACTIVADA. Limite diario o semanal alcanzado.");
 }
 }
 else
 {
 if(g_IsPaused)
 {
 g_IsPaused = false;
 Print(">>> PAUSE DESACTIVADA. Reanudando operaciones.");
 }
 }

 //--- 6. Force close at end of session
 if(Inp_Force_Close_End_Session && IsEndOfSession() && PositionsTotal() > 0)
 {
 CloseAllPositions();
 Print(">>> Cierre forzado por fin de sesion NY.");
 return;
 }

 //--- 7. Update H1 bias
 UpdateH1Bias();

 //--- 8. Manage open positions (ALWAYS executes before operational filters)
 // so exits are never blocked by spread/news/session filters
 if(PositionsTotal() > 0)
 {
 double adx_main[1];
 if(CopyBuffer(h_ADX, 0, 1, 1, adx_main) == 1)
 {
 double swing_high = GetLastConfirmedSwingHigh(PERIOD_M5, Inp_Swing_Lookback);
 double swing_low = GetLastConfirmedSwingLow(PERIOD_M5, Inp_Swing_Lookback);
 ManageOpenPositions(swing_high, swing_low, adx_main[0]);
 }
 return;
 }

 //--- 9. Operational filters (only block NEW entries, not exits)
 if(!CheckOperationalFilters())
 return;

 //--- 10. Cooldown check
 if(!CheckCooldown())
 return;

 //--- 11. ADX strength filter (on closed candle)
 if(!CheckADXStrength())
 return;

 //--- 12. Ranging filter (on closed candle)
 if(IsRanging())
 return;

 //--- 13. Get M5 candle data (CLOSED candle [1])
 double close_m5 = g_BarM5.close;
 double open_m5 = g_BarM5.open;
 double high_m5 = g_BarM5.high;
 double low_m5 = g_BarM5.low;
 double body = MathAbs(close_m5 - open_m5);
 double range = high_m5 - low_m5;
 double body_ratio = (range > 0.0) ? body / range : 0.0;

 if(body_ratio < Inp_Body_Ratio_Min)
 return;

 //--- 14. ROC Momentum (on closed candle)
 double roc = CalculateROC_M5(Inp_Momentum_Period);

 //--- 15. EMA9 alignment (on closed candle)
 double ema_fast[1];
 if(CopyBuffer(h_EMA_Fast, 0, 1, 1, ema_fast) < 1)
 return;

 //--- 16. ATR5 (on closed candle for consistency)
 double atr5[1];
 if(CopyBuffer(h_ATR5, 0, 1, 1, atr5) < 1)
 return;

 //--- 17. ENTRY LONG (Chain AND total)
 if(g_H1_Bull)
 {
 double swing_level = 0.0;
 bool bos = DetectBOS_Long(swing_level);
 double choch_level = 0.0;
 bool choch = DetectCHoCH_Long(choch_level);

 if(bos || choch)
 {
 double ref_level = bos ? swing_level : choch_level;

 if(close_m5 > ema_fast[0] &&
 roc > Inp_Mom_Long_Thr &&
 !IsFalseBreak_Long(ref_level))
 {
 double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
 double sl, tp;
 CalculateSLTP(entry, ORDER_TYPE_BUY, atr5[0], ref_level, sl, tp);

 double sl_dist = MathAbs(entry - sl);
 double tp_dist = MathAbs(tp - entry);
 if(sl_dist <= 0.0 || (tp_dist / sl_dist) < Inp_Min_RR)
 return;

 double lot = CalculateLotByRisk(sl_dist, Inp_Risk_PerTrade);
 if(lot > 0.0)
 {
 ExecuteTrade(ORDER_TYPE_BUY, lot, entry, sl, tp);
 }
 }
 }
 }

 //--- 18. ENTRY SHORT (Chain AND total)
 if(g_H1_Bear)
 {
 double swing_level = 0.0;
 bool bos = DetectBOS_Short(swing_level);
 double choch_level = 0.0;
 bool choch = DetectCHoCH_Short(choch_level);

 if(bos || choch)
 {
 double ref_level = bos ? swing_level : choch_level;

 if(close_m5 < ema_fast[0] &&
 roc < Inp_Mom_Short_Thr &&
 !IsFalseBreak_Short(ref_level))
 {
 double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
 double sl, tp;
 CalculateSLTP(entry, ORDER_TYPE_SELL, atr5[0], ref_level, sl, tp);

 double sl_dist = MathAbs(sl - entry);
 double tp_dist = MathAbs(entry - tp);
 if(sl_dist <= 0.0 || (tp_dist / sl_dist) < Inp_Min_RR)
 return;

 double lot = CalculateLotByRisk(sl_dist, Inp_Risk_PerTrade);
 if(lot > 0.0)
 {
 ExecuteTrade(ORDER_TYPE_SELL, lot, entry, sl, tp);
 }
 }
 }
 }
}

//+------------------------------------------------------------------+
//| Swing detection — Fractals 5 candles (2+1+2) |
//| Uses closed candles only, index protection enforced |
//+------------------------------------------------------------------+
bool IsSwingHighSafe(int index, int total_bars)
{
 if(index + 2 >= total_bars) return false;
 if(index - 2 < 0) return false;

 return (iHigh(_Symbol, PERIOD_M5, index) > iHigh(_Symbol, PERIOD_M5, index + 1) &&
 iHigh(_Symbol, PERIOD_M5, index) > iHigh(_Symbol, PERIOD_M5, index + 2) &&
 iHigh(_Symbol, PERIOD_M5, index) > iHigh(_Symbol, PERIOD_M5, index - 1) &&
 iHigh(_Symbol, PERIOD_M5, index) > iHigh(_Symbol, PERIOD_M5, index - 2));
}

bool IsSwingLowSafe(int index, int total_bars)
{
 if(index + 2 >= total_bars) return false;
 if(index - 2 < 0) return false;

 return (iLow(_Symbol, PERIOD_M5, index) < iLow(_Symbol, PERIOD_M5, index + 1) &&
 iLow(_Symbol, PERIOD_M5, index) < iLow(_Symbol, PERIOD_M5, index + 2) &&
 iLow(_Symbol, PERIOD_M5, index) < iLow(_Symbol, PERIOD_M5, index - 1) &&
 iLow(_Symbol, PERIOD_M5, index) < iLow(_Symbol, PERIOD_M5, index - 2));
}

//+------------------------------------------------------------------+
//| Swing buffers properly ordered by recency |
//| Index starts at 3 to ensure [i-2] is at least index 1 (closed) |
//+------------------------------------------------------------------+
void UpdateSwingBuffers(ENUM_TIMEFRAMES tf, int lookback)
{
 int total = iBars(_Symbol, tf);
 ArrayResize(g_SwingHighs, 0);
 ArrayResize(g_SwingLows, 0);

 // Start at index 3: ensures i-2 = 1 (closed candle), i+2 is valid
 for(int i = 3; i < lookback + 3 && i < total - 2; i++)
 {
 if(IsSwingHighSafe(i, total))
 {
 SwingPoint sp;
 sp.price = iHigh(_Symbol, tf, i);
 sp.bar_index = i;
 sp.time = iTime(_Symbol, tf, i);
 int size = ArraySize(g_SwingHighs);
 ArrayResize(g_SwingHighs, size + 1);
 g_SwingHighs[size] = sp;
 }

 if(IsSwingLowSafe(i, total))
 {
 SwingPoint sp;
 sp.price = iLow(_Symbol, tf, i);
 sp.bar_index = i;
 sp.time = iTime(_Symbol, tf, i);
 int size = ArraySize(g_SwingLows);
 ArrayResize(g_SwingLows, size + 1);
 g_SwingLows[size] = sp;
 }
 }
}

double GetLastConfirmedSwingHigh(ENUM_TIMEFRAMES tf, int lookback)
{
 UpdateSwingBuffers(tf, lookback);
 if(ArraySize(g_SwingHighs) == 0) return 0.0;
 return g_SwingHighs[0].price;
}

double GetLastConfirmedSwingLow(ENUM_TIMEFRAMES tf, int lookback)
{
 UpdateSwingBuffers(tf, lookback);
 if(ArraySize(g_SwingLows) == 0) return 0.0;
 return g_SwingLows[0].price;
}

//+------------------------------------------------------------------+
//| H1 Bias — Dual conditions (AND) with real HH/HL/LH/LL sequence |
//| Properly detects alternating pivot sequences |
//+------------------------------------------------------------------+
void UpdateH1Bias()
{
 g_H1_Bull = false;
 g_H1_Bear = false;

 double close_h1 = g_BarH1.close;
 double sma21_h1[6];
 if(CopyBuffer(h_SMA_Slow, 0, 0, 6, sma21_h1) < 6)
 return;

 bool above_sma = (close_h1 > sma21_h1[0]);
 bool below_sma = (close_h1 < sma21_h1[0]);
 bool slope_up = (sma21_h1[0] - sma21_h1[5] > 0.0);
 bool slope_down= (sma21_h1[0] - sma21_h1[5] < 0.0);

 //--- Build alternating pivot sequence for H1
 UpdateSwingBuffers(PERIOD_H1, 50);

 // Separate highs and lows into ordered arrays by time (most recent first)
 // g_SwingHighs and g_SwingLows are already ordered by recency

 //--- Detect HH/HL sequence (bullish) & LH/LL sequence (bearish)
 bool has_hh_hl_sequence = false;
 bool has_lh_ll_sequence = false;

 if(ArraySize(g_SwingHighs) >= 2 && ArraySize(g_SwingLows) >= 2)
 {
    bool hh = g_SwingHighs[0].price > g_SwingHighs[1].price;
    bool hl = g_SwingLows[0].price  > g_SwingLows[1].price;
    has_hh_hl_sequence = hh && hl;

    bool lh = g_SwingHighs[0].price < g_SwingHighs[1].price;
    bool ll = g_SwingLows[0].price  < g_SwingLows[1].price;
    has_lh_ll_sequence = lh && ll;
 }

 g_H1_Bull = above_sma && slope_up;
 g_H1_Bear = below_sma && slope_down;
}

//+------------------------------------------------------------------+
//| BOS / CHoCH detection (on closed candle [1]) |
//+------------------------------------------------------------------+
bool DetectBOS_Long(double &swing_level)
{
 swing_level = GetLastConfirmedSwingHigh(PERIOD_M5, Inp_Swing_Lookback);
 if(swing_level == 0.0) return false;

 double close_m5 = g_BarM5.close;
 double open_m5 = g_BarM5.open;
 double high_m5 = g_BarM5.high;
 double low_m5 = g_BarM5.low;
 double body = MathAbs(close_m5 - open_m5);
 double range = high_m5 - low_m5;
 double body_ratio = (range > 0.0) ? body / range : 0.0;

 return (close_m5 > swing_level) && (close_m5 > open_m5) && (body_ratio >= Inp_Body_Ratio_Min);
}

bool DetectBOS_Short(double &swing_level)
{
 swing_level = GetLastConfirmedSwingLow(PERIOD_M5, Inp_Swing_Lookback);
 if(swing_level == 0.0) return false;

 double close_m5 = g_BarM5.close;
 double open_m5 = g_BarM5.open;
 double high_m5 = g_BarM5.high;
 double low_m5 = g_BarM5.low;
 double body = MathAbs(close_m5 - open_m5);
 double range = high_m5 - low_m5;
 double body_ratio = (range > 0.0) ? body / range : 0.0;

 return (close_m5 < swing_level) && (close_m5 < open_m5) && (body_ratio >= Inp_Body_Ratio_Min);
}

bool DetectCHoCH_Long(double &reference_level)
{
 reference_level = 0.0;
 if(!g_H1_Bull) return false;

 UpdateSwingBuffers(PERIOD_M5, Inp_Swing_Lookback);
 int consecutive_ll = 0;
 double last_lh_price = 0.0;

 for(int i = 0; i < ArraySize(g_SwingLows) - 1; i++)
 {
 if(g_SwingLows[i].price < g_SwingLows[i + 1].price)
 consecutive_ll++;
 else
 {
 if(i + 1 < ArraySize(g_SwingHighs) && g_SwingHighs[i].price < g_SwingHighs[i + 1].price)
 last_lh_price = g_SwingHighs[i].price;
 consecutive_ll = 0;
 }
 if(consecutive_ll >= 2) break;
 }

 if(consecutive_ll < 2) return false;

 for(int i = 0; i < ArraySize(g_SwingHighs) - 1; i++)
 {
 if(g_SwingHighs[i].price < g_SwingHighs[i + 1].price)
 {
 last_lh_price = g_SwingHighs[i].price;
 break;
 }
 }

 if(last_lh_price == 0.0) return false;
 reference_level = last_lh_price;

 double close_m5 = g_BarM5.close;
 double open_m5 = g_BarM5.open;
 double high_m5 = g_BarM5.high;
 double low_m5 = g_BarM5.low;
 double body = MathAbs(close_m5 - open_m5);
 double range = high_m5 - low_m5;
 double body_ratio = (range > 0.0) ? body / range : 0.0;

 return (close_m5 > last_lh_price) && (close_m5 > open_m5) && (body_ratio >= Inp_Body_Ratio_Min);
}

bool DetectCHoCH_Short(double &reference_level)
{
 reference_level = 0.0;
 if(!g_H1_Bear) return false;

 UpdateSwingBuffers(PERIOD_M5, Inp_Swing_Lookback);
 int consecutive_hh = 0;
 double last_hl_price = 0.0;

 for(int i = 0; i < ArraySize(g_SwingHighs) - 1; i++)
 {
 if(g_SwingHighs[i].price > g_SwingHighs[i + 1].price)
 consecutive_hh++;
 else
 {
 if(i + 1 < ArraySize(g_SwingLows) && g_SwingLows[i].price > g_SwingLows[i + 1].price)
 last_hl_price = g_SwingLows[i].price;
 consecutive_hh = 0;
 }
 if(consecutive_hh >= 2) break;
 }

 if(consecutive_hh < 2) return false;

 for(int i = 0; i < ArraySize(g_SwingLows) - 1; i++)
 {
 if(g_SwingLows[i].price > g_SwingLows[i + 1].price)
 {
 last_hl_price = g_SwingLows[i].price;
 break;
 }
 }

 if(last_hl_price == 0.0) return false;
 reference_level = last_hl_price;

 double close_m5 = g_BarM5.close;
 double open_m5 = g_BarM5.open;
 double high_m5 = g_BarM5.high;
 double low_m5 = g_BarM5.low;
 double body = MathAbs(close_m5 - open_m5);
 double range = high_m5 - low_m5;
 double body_ratio = (range > 0.0) ? body / range : 0.0;

 return (close_m5 < last_hl_price) && (close_m5 < open_m5) && (body_ratio >= Inp_Body_Ratio_Min);
}

//+------------------------------------------------------------------+
//| Technical filters (all on closed data, offset 1) |
//+------------------------------------------------------------------+
double CalculateROC_M5(int period)
{
 double c0 = iClose(_Symbol, PERIOD_M5, 1); // Closed candle
 double cn = iClose(_Symbol, PERIOD_M5, period + 1);
 if(cn == 0.0) return 0.0;
 return ((c0 - cn) / cn) * 100.0;
}

bool CheckADXStrength()
{
 // Read from offset 1 (closed candle) for consistency
 double adx_main[1];
 if(CopyBuffer(h_ADX, 0, 1, 1, adx_main) < 1) return false;
 return (adx_main[0] >= Inp_ADX_Threshold);
}

bool IsRanging()
{
 // Read from offset 1 (closed candle)
 double adx_main[1];
 double atr5[1], atr14[1];
 if(CopyBuffer(h_ADX, 0, 1, 1, adx_main) < 1) return true;
 if(CopyBuffer(h_ATR5, 0, 1, 1, atr5) < 1) return true;
 if(CopyBuffer(h_ATR14, 0, 1, 1, atr14) < 1) return true;
 return (adx_main[0] < Inp_ADX_Threshold) || (atr5[0] < atr14[0] * 0.5);
}

bool IsFalseBreak_Long(double swing_high)
{
 double close_m5 = g_BarM5.close;
 double open_m5 = g_BarM5.open;
 double high_m5 = g_BarM5.high;
 return (high_m5 > swing_high) && (close_m5 < swing_high) && (close_m5 < open_m5);
}

bool IsFalseBreak_Short(double swing_low)
{
 double close_m5 = g_BarM5.close;
 double open_m5 = g_BarM5.open;
 double low_m5 = g_BarM5.low;
 return (low_m5 < swing_low) && (close_m5 > swing_low) && (close_m5 > open_m5);
}

bool CheckEMAAlignment(bool h1_bull)
{
 double ema_fast[1];
 if(CopyBuffer(h_EMA_Fast, 0, 1, 1, ema_fast) < 1) return false;
 double close_m5 = g_BarM5.close;
 if(h1_bull) return (close_m5 > ema_fast[0]);
 return (close_m5 < ema_fast[0]);
}

//+------------------------------------------------------------------+
//| Cooldown — only after REAL loss (profit < 0) |
//+------------------------------------------------------------------+
bool CheckCooldown()
{
 if(g_LastLossTime == 0) return true;
 return (TimeCurrent() - g_LastLossTime) > (Inp_Cooldown_Min * 60);
}

//+------------------------------------------------------------------+
//| News filter — MQL5 Calendar (CORREGIDO segun documentacion oficial) |
//| MqlCalendarValue NO tiene campo 'impact'. El impacto esta en |
//| MqlCalendarEvent::importance (ENUM_CALENDAR_EVENT_IMPORTANCE) |
//| y MqlCalendarValue::impact_type (ENUM_CALENDAR_EVENT_IMPACT) |
//+------------------------------------------------------------------+
bool IsInNewsWindow()
{
 datetime now = TimeCurrent();
 datetime from_time = now - (Inp_News_Before * 60);
 datetime to_time = now + (Inp_News_After * 60);

 //--- Get all events for USD currency in time range
 MqlCalendarValue values[];
 if(!CalendarValueHistory(values, from_time, to_time, NULL, "USD"))
 return false;

 for(int i = 0; i < ArraySize(values); i++)
 {
 //--- Get event description to check importance
 MqlCalendarEvent event;
 if(!CalendarEventById(values[i].event_id, event))
 continue;

 //--- Filter by HIGH importance only
 if(event.importance != CALENDAR_IMPORTANCE_HIGH)
 continue;

 //--- Check if we're within the news window
 datetime event_time = values[i].time;
 if(now >= event_time - (Inp_News_Before * 60) &&
 now <= event_time + (Inp_News_After * 60))
 {
 return true;
 }
 }

 return false;
}

//+------------------------------------------------------------------+
//| Operational filters (only block NEW entries) |
//+------------------------------------------------------------------+
bool CheckOperationalFilters()
{
 //--- Spread filter
 long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
 if(spread > Inp_Max_Spread)
 return false;

 //--- Session filter (London or NY)
 MqlDateTime dt;
 TimeToStruct(TimeCurrent(), dt);
 int hour = dt.hour;
 bool in_london = (hour >= Inp_London_Start && hour < Inp_London_End);
 bool in_ny = (hour >= Inp_NY_Start && hour < Inp_NY_End);
 if(!in_london && !in_ny)
 return false;

 //--- News filter
 if(IsInNewsWindow())
 return false;

 //--- Abnormal volatility: ATR5 > 2x ATR14 (on closed candle)
 double atr5[1], atr14[1];
 if(CopyBuffer(h_ATR5, 0, 1, 1, atr5) < 1) return false;
 if(CopyBuffer(h_ATR14, 0, 1, 1, atr14) < 1) return false;
 if(atr5[0] > atr14[0] * 2.0)
 return false;

 return true;
}

bool IsEndOfSession()
{
 MqlDateTime dt;
 TimeToStruct(TimeCurrent(), dt);
 int hour = dt.hour;
 int min = dt.min;
 return ((hour == Inp_NY_End - 1 && min >= 55) || hour >= Inp_NY_End);
}

//+------------------------------------------------------------------+
//| Risk management |
//| Weekly reset uses stored week start datetime |
//+------------------------------------------------------------------+
void UpdateRiskMetrics()
{
 MqlDateTime dt;
 TimeToStruct(TimeCurrent(), dt);
 double curr_equity = AccountInfoDouble(ACCOUNT_EQUITY);

 //--- Daily reset
 if(dt.day != g_last_day)
 {
 g_EquityStartDay = curr_equity;
 g_last_day = dt.day;
 g_IsPaused = false;
 Print("[RISK DEBUG] Daily reset. New g_EquityStartDay=", DoubleToString(g_EquityStartDay, 2));
 }

 //--- Weekly reset: check if we've crossed into a new week
 datetime current_week_start = GetWeekStart(TimeCurrent());
 if(current_week_start != g_week_start_time)
 {
 g_EquityStartWeek = curr_equity;
 g_week_start_time = current_week_start;
 Print("[RISK DEBUG] Weekly reset. New g_EquityStartWeek=", DoubleToString(g_EquityStartWeek, 2));
 }

 //--- Peak equity tracking
 if(curr_equity > g_EquityPeak)
 {
    double old_peak = g_EquityPeak;
    g_EquityPeak = curr_equity;
    Print("[RISK DEBUG] g_EquityPeak updated: ", DoubleToString(old_peak, 2),
          " -> ", DoubleToString(g_EquityPeak, 2),
          " (curr_equity=", DoubleToString(curr_equity, 2), ")");
 }
}

bool CheckKillSwitch()
{
 double equity = AccountInfoDouble(ACCOUNT_EQUITY);
 if(g_EquityPeak <= 0.0) return false;
 double dd_pct = (g_EquityPeak - equity) / g_EquityPeak * 100.0;

 // DEBUG: log every 100 ticks to avoid spam, and always when near threshold
 static int tick_count = 0;
 tick_count++;
 if(tick_count % 100 == 0 || dd_pct >= Inp_Max_DD * 0.8)
 {
    Print("[KILL DEBUG] Peak=", DoubleToString(g_EquityPeak, 2),
          " Equity=", DoubleToString(equity, 2),
          " DD%=", DoubleToString(dd_pct, 4),
          " Threshold=", Inp_Max_DD,
          " Tick=", tick_count);
 }

 return (dd_pct >= Inp_Max_DD);
}

bool CheckPause()
{
 double equity = AccountInfoDouble(ACCOUNT_EQUITY);
 double daily_loss = (g_EquityStartDay - equity) / g_EquityStartDay * 100.0;
 double weekly_loss = (g_EquityStartWeek - equity) / g_EquityStartWeek * 100.0;

 // Hysteresis: 2.0% to activate, 1.5% to deactivate
 double daily_limit_on = Inp_Daily_Loss_Limit;
 double daily_limit_off = Inp_Daily_Loss_Limit * 0.75; // 25% buffer below limit
 double weekly_limit_on = Inp_Weekly_Loss_Limit;
 double weekly_limit_off = Inp_Weekly_Loss_Limit * 0.75;

 bool daily_triggered = (daily_loss >= daily_limit_on);
 bool daily_cleared = (daily_loss < daily_limit_off);
 bool weekly_triggered = (weekly_loss >= weekly_limit_on);
 bool weekly_cleared = (weekly_loss < weekly_limit_off);

 // If already paused, require clearing below threshold to resume
 if(g_IsPaused)
    return !(daily_cleared && weekly_cleared);
 else
    return (daily_triggered || weekly_triggered);
}

//+------------------------------------------------------------------+
//| Trade calculation & execution |
//+------------------------------------------------------------------+
void CalculateSLTP(double entry, ENUM_ORDER_TYPE type, double atr5,
 double swing_level, double &sl, double &tp)
{
 if(type == ORDER_TYPE_BUY)
 {
 double sl_struct = swing_level - (Inp_SL_Struct_Buffer * atr5);
 double sl_volat = entry - (Inp_SL_Factor_ATR * atr5);
 sl = MathMin(sl_struct, sl_volat); // Mas bajo = mas lejano por debajo
 tp = entry + (Inp_Min_RR * MathAbs(entry - sl));
 }
 else // SELL
 {
 double sl_struct = swing_level + (Inp_SL_Struct_Buffer * atr5);
 double sl_volat = entry + (Inp_SL_Factor_ATR * atr5);
 sl = MathMax(sl_struct, sl_volat); // Mas alto = mas lejano por encima
 tp = entry - (Inp_Min_RR * MathAbs(sl - entry));
 }

 //--- Normalize to tick size
 double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
 int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
 if(tick_size > 0.0)
 {
 sl = NormalizeDouble(MathRound(sl / tick_size) * tick_size, digits);
 tp = NormalizeDouble(MathRound(tp / tick_size) * tick_size, digits);
 }
}

//+------------------------------------------------------------------+
//| Validates lot calculation against contract size |
//| and normalizes for broker-specific tick_value reporting |
//+------------------------------------------------------------------+
double CalculateLotByRisk(double sl_distance, double risk_pct)
{
 if(sl_distance <= 0.0) return 0.0;

 double equity = AccountInfoDouble(ACCOUNT_EQUITY);
 double risk_amount = equity * risk_pct / 100.0;
 double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
 double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
 double contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
 double lot_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

 if(tick_value <= 0.0 || tick_size <= 0.0 || contract <= 0.0) return 0.0;

 double ticks_at_risk = sl_distance / tick_size;
 if(ticks_at_risk <= 0.0) return 0.0;

 //--- Calculate monetary risk per lot
 // Some brokers report tick_value per minimum lot, others per 1.0 lot
 // Normalize: if tick_value is very small, it might be per micro lot
 double tick_value_per_unit_lot = tick_value;
 if(tick_value < 0.1 && lot_min >= 0.01)
 {
 // Likely reported per 0.01 lot, scale up
 tick_value_per_unit_lot = tick_value / lot_min;
 }

 double risk_per_lot = ticks_at_risk * tick_value_per_unit_lot;
 if(risk_per_lot <= 0.0) return 0.0;

 double lot = risk_amount / risk_per_lot;

 double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
 double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
 double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

 if(lot_step > 0.0)
 lot = MathFloor(lot / lot_step) * lot_step;

 lot = MathMax(min_lot, MathMin(max_lot, lot));

 //--- Round to 2 decimal places for XAUUSD standard
 return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Validates stops_level, auto-adjusts if needed |
//+------------------------------------------------------------------+
bool ExecuteTrade(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp)
{
 //--- Verify stops_level
 int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
 double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
 double min_distance = stops_level * point;
 double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
 int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

 double sl_dist = MathAbs(price - sl);
 double tp_dist = MathAbs(tp - price);

 //--- Auto-adjust SL if too close (instead of rejecting)
 if(sl_dist < min_distance && min_distance > 0.0)
 {
 Print("WARNING: SL demasiado cerca (", sl_dist, "), ajustando a min_distance + buffer");
 double adjustment = min_distance + tick_size * 2.0;
 if(type == ORDER_TYPE_BUY)
 sl = price - adjustment;
 else
 sl = price + adjustment;
 sl = NormalizeDouble(MathRound(sl / tick_size) * tick_size, digits);

 // Recalculate TP to maintain RR
 sl_dist = MathAbs(price - sl);
 if(type == ORDER_TYPE_BUY)
 tp = price + (Inp_Min_RR * sl_dist);
 else
 tp = price - (Inp_Min_RR * sl_dist);
 tp = NormalizeDouble(MathRound(tp / tick_size) * tick_size, digits);
 }

 if(tp_dist < min_distance && min_distance > 0.0)
 {
 Print("WARNING: TP demasiado cerca (", tp_dist, "), ajustando");
 double adjustment = min_distance + tick_size * 2.0;
 if(type == ORDER_TYPE_BUY)
 tp = price + adjustment;
 else
 tp = price - adjustment;
 tp = NormalizeDouble(MathRound(tp / tick_size) * tick_size, digits);
 }

 // Final RR check after adjustments
 sl_dist = MathAbs(price - sl);
 tp_dist = MathAbs(tp - price);
 if(sl_dist <= 0.0 || (tp_dist / sl_dist) < Inp_Min_RR)
 {
 Print("ERROR: RR insuficiente despues de ajuste. Rechazando trade.");
 return false;
 }

 MqlTradeRequest request = {};
 MqlTradeResult result = {};

 request.action = TRADE_ACTION_DEAL;
 request.symbol = _Symbol;
 request.volume = lot;
 request.type = type;
 request.price = price;
 request.sl = sl;
 request.tp = tp;
 request.deviation = Inp_Max_Slippage;
 request.magic = Inp_MagicNumber;
 request.comment = "XAU_M5H1_V15";

 if(!OrderSend(request, result))
 {
 Print("OrderSend FAILED. Error: ", GetLastError(),
 " Retcode: ", result.retcode,
 " Deal: ", result.deal,
 " Order: ", result.order);
 return false;
 }

 Print("Trade OK. Type: ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
 " Lot: ", lot,
 " Price: ", price,
 " SL: ", sl,
 " TP: ", tp);
 g_LastPositionOpenTime = TimeCurrent();
 return true;
}

//+------------------------------------------------------------------+
//| Position management |
//| Uses PositionSelectByTicket before reading properties |
//| Only sets g_LastLossTime on actual loss (profit < 0) |
//| Validates swing_level before using for invalidation |
//+------------------------------------------------------------------+
void ManageOpenPositions(double swing_high, double swing_low, double adx_current)
{
 // Check minimum hold time before allowing structural invalidation
 bool can_invalidate = (g_LastPositionOpenTime == 0) ||
                       (TimeCurrent() - g_LastPositionOpenTime) > (Inp_MinHoldMinutes * 60);

 for(int i = PositionsTotal() - 1; i >= 0; i--)
 {
 ulong ticket = PositionGetTicket(i);
 if(ticket == 0) continue;

 if(!PositionSelectByTicket(ticket))
 continue;

 if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
 if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;

 ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
 double pos_profit = PositionGetDouble(POSITION_PROFIT);
 bool invalidate = false;

 if(pos_type == POSITION_TYPE_BUY)
 {
 // Only invalidate by structure if swing_low is valid AND min hold time passed
 if(can_invalidate && swing_low > 0.0 && iClose(_Symbol, PERIOD_M5, 0) < swing_low)
 invalidate = true;
 if(!g_H1_Bull) invalidate = true;
 if(adx_current < 20.0) invalidate = true;
 }
 else // SELL
 {
 // Only invalidate by structure if swing_high is valid AND min hold time passed
 if(can_invalidate && swing_high > 0.0 && iClose(_Symbol, PERIOD_M5, 0) > swing_high)
 invalidate = true;
 if(!g_H1_Bear) invalidate = true;
 if(adx_current < 20.0) invalidate = true;
 }

 if(invalidate)
 {
 ClosePosition(ticket);
 // Only set cooldown if the trade was actually losing
 if(pos_profit < 0)
 g_LastLossTime = TimeCurrent();
 }
 }
}

void ClosePosition(ulong ticket)
{
 if(!PositionSelectByTicket(ticket))
 return;

 MqlTradeRequest request = {};
 MqlTradeResult result = {};

 request.action = TRADE_ACTION_DEAL;
 request.position = ticket;
 request.symbol = _Symbol;
 request.volume = PositionGetDouble(POSITION_VOLUME);
 request.deviation= Inp_Max_Slippage;
 request.magic = Inp_MagicNumber;

 ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
 request.type = (pos_type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
 request.price = (pos_type == POSITION_TYPE_BUY) ?
 SymbolInfoDouble(_Symbol, SYMBOL_BID) :
 SymbolInfoDouble(_Symbol, SYMBOL_ASK);

 if(!OrderSend(request, result))
 {
 Print("ClosePosition FAILED. Error: ", GetLastError(),
 " Retcode: ", result.retcode);
 }
 else
 {
 Print("Position closed. Ticket: ", ticket);
 }
}

void CloseAllPositions()
{
 for(int i = PositionsTotal() - 1; i >= 0; i--)
 {
 ulong ticket = PositionGetTicket(i);
 if(ticket == 0) continue;

 if(!PositionSelectByTicket(ticket))
 continue;

 if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
 PositionGetInteger(POSITION_MAGIC) == Inp_MagicNumber)
 {
 ClosePosition(ticket);
 }
 }
}
//+------------------------------------------------------------------+