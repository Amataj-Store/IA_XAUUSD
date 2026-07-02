//+------------------------------------------------------------------+
//|                                        XAUUSD_M5_H1_Scalper.mq5  |
//|                                  Arquitecto Cuantitativo Senior  |
//+------------------------------------------------------------------+
#property copyright "Quant Architect"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Objetos globales
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

//--- ENUMS
enum ENUM_EA_STATE {
   STATE_IDLE,
   STATE_COOLDOWN,
   STATE_PAUSE,
   STATE_KILL
};

//--- INPUTS: Riesgo
input group "=== Gestión de Riesgo ==="
input double   Risk_Per_Trade       = 0.5;     // % de Equity arriesgado por trade
input double   Daily_Loss_Limit     = 2.0;     // Límite de pérdida diaria (%)
input double   Weekly_Loss_Limit    = 4.0;     // Límite de pérdida semanal (%)
input double   Max_DD_Absolute      = 10.0;    // Drawdown absoluto para KILL (%)
input int      Cooldown_Loss_Min    = 30;      // Minutos de cooldown tras pérdida

//--- INPUTS: Operativa
input group "=== Filtros Operativos ==="
input int      Max_Spread_Points    = 25;      // Spread máximo (points)
input int      Max_Slippage_Points  = 50;      // Slippage máximo (points)
input bool     Force_Close_End_Session = true; // Cerrar al final de la sesión NY
input int      News_Min_Before      = 15;      // Bloquear min antes de noticia
input int      News_Min_After       = 30;      // Bloquear min después de noticia

//--- INPUTS: Estrategia H1
input group "=== Sesgo H1 ==="
input int      SMA_H1_Period        = 21;      // Periodo SMA H1
input int      ADX_H1_Period        = 14;      // Periodo ADX H1
input double   ADX_H1_Threshold     = 23.0;    // Umbral mínimo ADX H1

//--- INPUTS: Estrategia M5
input group "=== Gatillo M5 ==="
input int      EMA_M5_Fast          = 9;       // Periodo EMA M5
input int      ROC_M5_Period        = 6;       // Periodo ROC M5
input double   ROC_M5_Threshold     = 0.05;    // Umbral ROC M5 (%)
input int      Fractal_Lookback     = 2;       // Velas izq/der para confirmar swing
input int      Signal_Expiry_Bars   = 6;       // Velas M5 máx para esperar retest
input int      Retest_Tolerance_Points = 20;   // Tolerancia de retest en points

//--- INPUTS: Gestión de Trade
input group "=== SL y TP ==="
input int      ATR_M5_Period_SL     = 14;      // Periodo ATR para SL
input double   ATR_Mult_Volatility  = 1.2;     // Multiplicador ATR para Volatility_SL
input double   ATR_Mult_Structure   = 0.2;     // Offset ATR para Structural_SL
input double   Min_RR               = 1.5;     // Reward-to-Risk mínimo

//--- VARIABLES GLOBALES
ENUM_EA_STATE  current_state = STATE_IDLE;
datetime       cooldown_end_time = 0;
datetime       last_bar_time_m5 = 0;

// Estado de Señales
int            pending_signal_dir = 0; // 1=Long, -1=Short, 0=None
double         pending_bos_level = 0.0;
int            signal_expiry_counter = 0;

// Indicadores Handles
int            handle_sma_h1, handle_adx_h1, handle_ema_m5, handle_atr_m5;

// Tracking de P&L
double         initial_equity = 0;
double         daily_start_equity = 0;
double         weekly_start_equity = 0;
datetime       last_daily_reset = 0;
datetime       last_weekly_reset = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(123456); // Magic Number fijo
   trade.SetDeviationInPoints(Max_Slippage_Points);
   
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   
   // Inicializar handles de indicadores
   handle_sma_h1 = iMA(_Symbol, PERIOD_H1, SMA_H1_Period, 0, MODE_SMA, PRICE_CLOSE);
   handle_adx_h1 = iADX(_Symbol, PERIOD_H1, ADX_H1_Period);
   handle_ema_m5 = iMA(_Symbol, PERIOD_M5, EMA_M5_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handle_atr_m5 = iATR(_Symbol, PERIOD_M5, ATR_M5_Period_SL);
   
   if(handle_sma_h1 == INVALID_HANDLE || handle_adx_h1 == INVALID_HANDLE || 
      handle_ema_m5 == INVALID_HANDLE || handle_atr_m5 == INVALID_HANDLE)
   {
      Print("Error al crear handles de indicadores.");
      return INIT_FAILED;
   }
   
   initial_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   daily_start_equity = initial_equity;
   weekly_start_equity = initial_equity;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handle_sma_h1);
   IndicatorRelease(handle_adx_h1);
   IndicatorRelease(handle_ema_m5);
   IndicatorRelease(handle_atr_m5);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Reset límites diarios/semanales
   CheckPeriodResets();
   
   // 1. Chequeos de Riesgo Global
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd_abs = ((initial_equity - current_equity) / initial_equity) * 100.0;
   if(dd_abs >= Max_DD_Absolute) {
      current_state = STATE_KILL;
      CloseAllPositions("KILL_SWITCH_DD");
      return;
   }
   
   double daily_loss = ((daily_start_equity - current_equity) / daily_start_equity) * 100.0;
   if(daily_loss >= Daily_Loss_Limit) current_state = STATE_PAUSE;
   
   double weekly_loss = ((weekly_start_equity - current_equity) / weekly_start_equity) * 100.0;
   if(weekly_loss >= Weekly_Loss_Limit) current_state = STATE_PAUSE;
   
   if(current_state == STATE_KILL || current_state == STATE_PAUSE) return;
   if(current_state == STATE_COOLDOWN && TimeCurrent() < cooldown_end_time) return;
   if(current_state == STATE_COOLDOWN && TimeCurrent() >= cooldown_end_time) current_state = STATE_IDLE;
   
   // 2. Gestión de posiciones abiertas
   if(PositionsTotal() > 0) {
      ManageOpenPositions();
      return; // Solo 1 posición simultánea (Scalper Puro)
   }
   
   // Ejecutar lógica solo en nueva vela M5
   if(!IsNewBar(PERIOD_M5)) return;
   
   // 3. Filtros Operativos
   if(!IsSessionActive()) return;
   if(IsNewsTime()) return;
   
   symInfo.Refresh();
   if(symInfo.Spread() > Max_Spread_Points) return;
   
   // 4. Análisis Macro H1
   int h1_trend = GetH1Trend();
   if(h1_trend == 0) {
      pending_signal_dir = 0; // Sin sesgo, resetear señales
      return;
   }
   
   // 5. Lógica de BOS y Retest en M5
   CheckM5Signals(h1_trend);
}

//+------------------------------------------------------------------+
//| Comprueba y gestiona señales de BOS y Retest en M5               |
//+------------------------------------------------------------------+
void CheckM5Signals(int h1_trend)
{
   double last_swing_high = GetLastFractal(true, Fractal_Lookback);
   double last_swing_low = GetLastFractal(false, Fractal_Lookback);
   
   // Evaluar nuevo BOS si no hay señal pendiente
   if(pending_signal_dir == 0)
   {
      if(h1_trend == 1 && IsBOS_Long(last_swing_high))
      {
         pending_signal_dir = 1;
         pending_bos_level = last_swing_high;
         signal_expiry_counter = 0;
      }
      else if(h1_trend == -1 && IsBOS_Short(last_swing_low))
      {
         pending_signal_dir = -1;
         pending_bos_level = last_swing_low;
         signal_expiry_counter = 0;
      }
   }
   
   // Evaluar Retest si hay señal pendiente
   if(pending_signal_dir != 0)
   {
      signal_expiry_counter++;
      if(signal_expiry_counter > Signal_Expiry_Bars)
      {
         pending_signal_dir = 0; // Expiró
         return;
      }
      
      double roc = GetROC(ROC_M5_Period);
      double ema9[];
      CopyBuffer(handle_ema_m5, 0, 1, 1, ema9);
      double close1 = iClose(_Symbol, PERIOD_M5, 1);
      
      if(pending_signal_dir == 1)
      {
         double tolerance = Retest_Tolerance_Points * _Point;
         double low1 = iLow(_Symbol, PERIOD_M5, 1);
         double open1 = iOpen(_Symbol, PERIOD_M5, 1);
         
         // Retest válido si el mínimo tocó la zona y cerró por encima con cuerpo dominante
         if(low1 <= (pending_bos_level + tolerance) && close1 > pending_bos_level && 
            MathAbs(close1 - open1) > 0.5 * (iHigh(_Symbol, PERIOD_M5, 1) - low1) &&
            roc > ROC_M5_Threshold && close1 > ema9[0])
         {
            ExecuteTrade(ORDER_TYPE_BUY);
            pending_signal_dir = 0;
         }
      }
      else if(pending_signal_dir == -1)
      {
         double tolerance = Retest_Tolerance_Points * _Point;
         double high1 = iHigh(_Symbol, PERIOD_M5, 1);
         double open1 = iOpen(_Symbol, PERIOD_M5, 1);
         
         if(high1 >= (pending_bos_level - tolerance) && close1 < pending_bos_level && 
            MathAbs(close1 - open1) > 0.5 * (high1 - iLow(_Symbol, PERIOD_M5, 1)) &&
            roc < -ROC_M5_Threshold && close1 < ema9[0])
         {
            ExecuteTrade(ORDER_TYPE_SELL);
            pending_signal_dir = 0;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Ejecuta el trade con SL y TP calculados                          |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type)
{
   double atr5[], atr14[];
   CopyBuffer(handle_atr_m5, 0, 1, 1, atr5); // ATR rápido para offset estructural (usaremos el mismo handle por simplicidad configurable)
   CopyBuffer(handle_atr_m5, 0, 1, 1, atr14); // ATR base para volatilidad
   
   double entry_price = (type == ORDER_TYPE_BUY) ? symInfo.Ask() : symInfo.Bid();
   double sl = 0.0, tp = 0.0;
   
   if(type == ORDER_TYPE_BUY)
   {
      double structural_sl = GetLastFractal(false, Fractal_Lookback) - (ATR_Mult_Structure * atr14[0]);
      double volatility_sl = entry_price - (ATR_Mult_Volatility * atr14[0]);
      // Long: El SL más conservador es el de menor valor numérico (más distancia)
      sl = MathMin(structural_sl, volatility_sl);
      tp = entry_price + Min_RR * (entry_price - sl);
   }
   else
   {
      double structural_sl = GetLastFractal(true, Fractal_Lookback) + (ATR_Mult_Structure * atr14[0]);
      double volatility_sl = entry_price + (ATR_Mult_Volatility * atr14[0]);
      // Short: El SL más conservador es el de mayor valor numérico (más distancia)
      sl = MathMax(structural_sl, volatility_sl);
      tp = entry_price - Min_RR * (sl - entry_price);
   }
   
   double lots = CalculateLotSize(entry_price, sl);
   if(lots <= 0) return;
   
   if(type == ORDER_TYPE_BUY) trade.Buy(lots, _Symbol, entry_price, sl, tp, "M5_Scalper_Long");
   if(type == ORDER_TYPE_SELL) trade.Sell(lots, _Symbol, entry_price, sl, tp, "M5_Scalper_Short");
}

//+------------------------------------------------------------------+
//| Gestiona posiciones abiertas (CHoCH, tiempo)                     |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() != _Symbol || posInfo.Magic() != 123456) continue;
         
         // Cierre por fin de sesión
         if(Force_Close_End_Session && TimeCurrent() >= D'1970.01.01 21:00')
         {
            trade.PositionClose(posInfo.Ticket());
            return;
         }
         
         // Cierre por CHoCH
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            double last_sw_low = GetLastFractal(false, Fractal_Lookback);
            if(iClose(_Symbol, PERIOD_M5, 1) < last_sw_low) // CHoCH Bajista
            {
               trade.PositionClose(posInfo.Ticket(), Max_Slippage_Points);
               return;
            }
         }
         else if(posInfo.PositionType() == POSITION_TYPE_SELL)
         {
            double last_sw_high = GetLastFractal(true, Fractal_Lookback);
            if(iClose(_Symbol, PERIOD_M5, 1) > last_sw_high) // CHoCH Alcista
            {
               trade.PositionClose(posInfo.Ticket(), Max_Slippage_Points);
               return;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Funciones Auxiliares de Indicadores y Estructura                 |
//+------------------------------------------------------------------+

bool IsNewBar(ENUM_TIMEFRAMES tf)
{
   datetime time = iTime(_Symbol, tf, 0);
   if(time != last_bar_time_m5)
   {
      last_bar_time_m5 = time;
      return true;
   }
   return false;
}

int GetH1Trend()
{
   double sma[];
   CopyBuffer(handle_sma_h1, 0, 1, 2, sma);
   double close_h1 = iClose(_Symbol, PERIOD_H1, 1);
   
   double adx[];
   CopyBuffer(handle_adx_h1, 0, 1, 1, adx);
   
   if(adx[0] < ADX_H1_Threshold) return 0;
   
   if(close_h1 > sma[0] && sma[0] > sma[1]) return 1;  // Alcista
   if(close_h1 < sma[0] && sma[0] < sma[1]) return -1; // Bajista
   
   return 0;
}

bool IsBOS_Long(double level)
{
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double open1 = iOpen(_Symbol, PERIOD_M5, 1);
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   
   return (close1 > level && MathAbs(close1 - open1) > 0.5 * (high1 - low1));
}

bool IsBOS_Short(double level)
{
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double open1 = iOpen(_Symbol, PERIOD_M5, 1);
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   
   return (close1 < level && MathAbs(close1 - open1) > 0.5 * (high1 - low1));
}

double GetLastFractal(bool isHigh, int lookback)
{
   // Iteramos desde la vela 3 hasta 50 para encontrar el último fractal relevante confirmado
   for(int i = 3; i <= 50; i++)
   {
      double val = iHigh(_Symbol, PERIOD_M5, i);
      if(!isHigh) val = iLow(_Symbol, PERIOD_M5, i);
      
      bool is_fractal = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(isHigh)
         {
            if(iHigh(_Symbol, PERIOD_M5, i+j) >= val || iHigh(_Symbol, PERIOD_M5, i-j) >= val)
            {
               is_fractal = false;
               break;
            }
         }
         else
         {
            if(iLow(_Symbol, PERIOD_M5, i+j) <= val || iLow(_Symbol, PERIOD_M5, i-j) <= val)
            {
               is_fractal = false;
               break;
            }
         }
      }
      
      if(is_fractal) return val;
   }
   return 0.0;
}

double GetROC(int period)
{
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double close_prev = iClose(_Symbol, PERIOD_M5, 1 + period);
   if(close_prev == 0) return 0;
   return ((close1 - close_prev) / close_prev) * 100.0;
}

//+------------------------------------------------------------------+
//| Funciones Auxiliares de Gestión de Riesgo                        |
//+------------------------------------------------------------------+

double CalculateLotSize(double entry, double sl)
{
   double risk_amount = AccountInfoDouble(ACCOUNT_EQUITY) * (Risk_Per_Trade / 100.0);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tick_size == 0 || tick_value == 0) return 0;
   
   double sl_distance = MathAbs(entry - sl);
   double ticks = sl_distance / tick_size;
   
   if(ticks == 0) return 0;
   
   double lots = risk_amount / (ticks * tick_value);
   
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lot_step) * lot_step;
   if(lots < min_lot) lots = min_lot;
   if(lots > max_lot) lots = max_lot;
   
   return lots;
}

void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == 123456)
         {
            trade.PositionClose(posInfo.Ticket(), Max_Slippage_Points);
         }
      }
   }
}

void CheckPeriodResets()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Reset Diario (cambio de día)
   if(dt.day != last_daily_reset) {
      daily_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      last_daily_reset = dt.day;
      if(current_state == STATE_PAUSE) current_state = STATE_IDLE; // Salir de pausa diaria
   }
   
   // Reset Semanal (Lunes)
   if(dt.day_of_week == 1 && dt.day != last_weekly_reset) {
      weekly_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      last_weekly_reset = dt.day;
      if(current_state == STATE_PAUSE) current_state = STATE_IDLE; // Salir de pausa semanal
   }
}

//+------------------------------------------------------------------+
//| Filtros Operativos (Sesión y Noticias)                           |
//+------------------------------------------------------------------+

bool IsSessionActive()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // Londres (07:00 - 16:00) o Nueva York (12:00 - 21:00) Server Time aprox.
   if((hour >= 7 && hour < 16) || (hour >= 12 && hour < 21)) return true;
   
   return false;
}

bool IsNewsTime()
{
   datetime now = TimeCurrent();
   datetime from = now - News_Min_After * 60;
   datetime to = now + News_Min_Before * 60;
   
   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, from, to, NULL, NULL);
   
   if(count > 0)
   {
      for(int i = 0; i < count; i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               // Filtrar solo USD (XAUUSD)
               MqlCalendarCountry country;
               if(CalendarCountryById(event.country_id, country))
               {
                  if(country.currency == "USD") return true;
               }
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Evento de Trade para activar Cooldown                            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong deal_ticket = trans.deal;
      if(HistoryDealSelect(deal_ticket))
      {
         if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) == _Symbol && 
            HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == 123456)
         {
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
            double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
            
            if(entry == DEAL_ENTRY_OUT && profit < 0)
            {
               current_state = STATE_COOLDOWN;
               cooldown_end_time = TimeCurrent() + Cooldown_Loss_Min * 60;
            }
         }
      }
   }
}