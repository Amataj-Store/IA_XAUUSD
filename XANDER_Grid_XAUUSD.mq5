//+------------------------------------------------------------------+
//| XANDER Grid XAUUSD                                               |
//| Version: 1.0          | Date: 2026-04-09                        |
//| Platform: MT5                                                    |
//| Company: XANDER Systems                                         |
//+------------------------------------------------------------------+
// CHANGELOG:
// v1.0 - 2026-04-09 - Initial release
//                     Bidirectional grid with candle direction filter
//                     Average TP and Partial Close modes
//                     Daily Profit Target
//                     Max Floating Drawdown protection
//                     Auto clean chart on load (grid, volume, trade history, levels)
//+------------------------------------------------------------------+
// Join our trading community:
// Telegram : https://t.me/botmetatrader5
//
// Freelance & development requests — MQL5 profile only:
// MQL5     : https://www.mql5.com/en/users/09151993a
//+------------------------------------------------------------------+
#property copyright   "© XANDER Systems"
#property link        "https://www.mql5.com/en/users/09151993a"
#property version     "1.00"
#property description "XANDER Grid XAUUSD — Bidirectional Grid EA for Gold"
#property description "Community: t.me/botmetatrader5"
#property description "Freelance & dev requests: mql5.com/en/users/09151993a"

#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>

CPositionInfo m_position;
CTrade        trade;

//--- Close strategy enum
enum ENUM_CLOSE_TYPE
  {
   AVERAGE_TP   = 0,  // Average TP — set shared TP on best + worst position
   PARTIAL_CLOSE = 1  // Partial Close — close worst position partially
  };

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input string sep0             = "★ XANDER Grid XAUUSD";               // ══ XANDER Systems ══
input string sep1             = "══════ GRID SETTINGS ══════";   // ─────────────────────
input int    xs_TakeProfit    = 300;   // Take Profit per position (pips)
input int    xs_GridStep      = 390;   // Distance between grid levels (pips)
input int    xs_MinProfit     = 120;   // Minimum grid profit to close (pips)

input string sep2             = "══════ LOT SETTINGS ══════";    // ─────────────────────
input double xs_StartLots     = 0.01;  // Starting lot size
input double xs_MaxLots       = 0.04;  // Maximum lot size allowed

input string sep3             = "══════ CLOSE STRATEGY ══════";  // ─────────────────────
input ENUM_CLOSE_TYPE xs_CloseType = AVERAGE_TP; // Close method

input string sep4             = "══════ RISK PROTECTION ══════"; // ─────────────────────
input bool   xs_UseDailyTarget  = false; // Enable Daily Profit Target
input double xs_DailyTarget     = 10.0;  // Daily Profit Target ($) — closes all when reached
input bool   xs_UseMaxDrawdown  = false; // Enable Max Floating Drawdown
input double xs_MaxDrawdown     = 50.0;  // Max Floating Drawdown ($) — pauses new entries

input string sep5             = "══════ EXPERT SETTINGS ══════"; // ─────────────────────
input int    xs_Magic         = 2001;  // Magic Number
input int    xs_Slippage      = 30;    // Slippage (pips)

input string sep_last         = "══════ CONTACT ══════";       // ─────────────────────
input string xs_community   = "https://t.me/botmetatrader5";   // 🌐 Join our trading community
input string xs_freelance    = "mql5.com/en/users/09151993a";    // 💼 Freelance & dev requests — MQL5 only

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
datetime g_DayStart = 0;
double   g_DayProfit = 0.0;
bool     g_DailyTargetHit = false;

//--- Chart state saved on load (restored on remove)
bool g_prev_Grid;
bool g_prev_Volume;
bool g_prev_TradeHistory;
bool g_prev_TradeLevels;
bool g_prev_BidLine;
bool g_prev_AskLine;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   Comment("");
   trade.LogLevel(LOG_LEVEL_ERRORS);
   trade.SetExpertMagicNumber(xs_Magic);
   trade.SetDeviationInPoints(xs_Slippage);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(Symbol());

   g_DayStart    = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   g_DayProfit   = 0.0;
   g_DailyTargetHit = false;

   //--- Save current chart settings before changing them
   g_prev_Grid         = (bool)ChartGetInteger(0, CHART_SHOW_GRID);
   g_prev_Volume       = (bool)ChartGetInteger(0, CHART_SHOW_VOLUMES);
   g_prev_TradeHistory = (bool)ChartGetInteger(0, CHART_SHOW_TRADE_HISTORY);
   g_prev_TradeLevels  = (bool)ChartGetInteger(0, CHART_SHOW_TRADE_LEVELS);
   g_prev_BidLine      = (bool)ChartGetInteger(0, CHART_SHOW_BID_LINE);
   g_prev_AskLine      = (bool)ChartGetInteger(0, CHART_SHOW_ASK_LINE);

   //--- Clean chart: hide grid, volume, trade history, SL/TP levels, bid/ask lines
   ChartSetInteger(0, CHART_SHOW_GRID,          false);
   ChartSetInteger(0, CHART_SHOW_VOLUMES,        false);
   ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY,  false);
   ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS,   false);
   ChartSetInteger(0, CHART_SHOW_BID_LINE,       false);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE,       false);
   ChartRedraw(0);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
   //--- Restore chart settings to what they were before the EA loaded
   ChartSetInteger(0, CHART_SHOW_GRID,          g_prev_Grid);
   ChartSetInteger(0, CHART_SHOW_VOLUMES,        g_prev_Volume);
   ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY,  g_prev_TradeHistory);
   ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS,   g_prev_TradeLevels);
   ChartSetInteger(0, CHART_SHOW_BID_LINE,       g_prev_BidLine);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE,       g_prev_AskLine);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| ResetDayIfNeeded — resets daily tracking at start of new day    |
//+------------------------------------------------------------------+
void ResetDayIfNeeded()
  {
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today > g_DayStart)
     {
      g_DayStart        = today;
      g_DayProfit       = 0.0;
      g_DailyTargetHit  = false;
     }
  }

//+------------------------------------------------------------------+
//| GetFloatingProfit — sum of all open positions for this EA       |
//+------------------------------------------------------------------+
double GetFloatingProfit()
  {
   double total = 0.0;
   int count = PositionsTotal();
   for(int i = count - 1; i >= 0; i--)
      if(m_position.SelectByIndex(i))
         if(m_position.Symbol() == Symbol() && m_position.Magic() == xs_Magic)
            total += m_position.Profit() + m_position.Swap() + m_position.Commission();
   return total;
  }

//+------------------------------------------------------------------+
//| CloseAllPositions — used by Daily Target                        |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   int count = PositionsTotal();
   for(int i = count - 1; i >= 0; i--)
      if(m_position.SelectByIndex(i))
         if(m_position.Symbol() == Symbol() && m_position.Magic() == xs_Magic)
            trade.PositionClose(m_position.Ticket(), xs_Slippage);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- daily reset
   ResetDayIfNeeded();

   //--- floating profit/drawdown
   double floatingProfit = GetFloatingProfit();

   //--- Daily Profit Target: close all and stop for the day
   if(xs_UseDailyTarget && !g_DailyTargetHit)
     {
      g_DayProfit = floatingProfit; // simplified: current floating as daily proxy
      if(g_DayProfit >= xs_DailyTarget)
        {
         CloseAllPositions();
         g_DailyTargetHit = true;
         Print("[XANDER Grid XAUUSD] Daily target reached: $", DoubleToString(g_DayProfit, 2), " — trading paused for today.");
         return;
        }
     }

   //--- If daily target already hit today, do nothing
   if(g_DailyTargetHit)
      return;

   //--- Max floating drawdown: pause new entries (do NOT close, just skip)
   bool drawdownPaused = false;
   if(xs_UseMaxDrawdown && floatingProfit < -xs_MaxDrawdown)
     {
      drawdownPaused = true;
      Print("[XANDER Grid XAUUSD] Drawdown limit reached: $", DoubleToString(floatingProfit, 2), " — new entries paused.");
     }

   //--- Scan positions
   double BuyPriceMax=0, BuyPriceMin=0, BuyPriceMaxLot=0, BuyPriceMinLot=0;
   double SelPriceMin=0, SelPriceMax=0, SelPriceMinLot=0, SelPriceMaxLot=0;
   ulong  BuyPriceMaxTic=0, BuyPriceMinTic=0, SelPriceMaxTic=0, SelPriceMinTic=0;
   double op=0, lt=0, tp=0;
   ulong  tk=0;
   int    b=0, s=0;

   int total = PositionsTotal();
   for(int k = total - 1; k >= 0; k--)
      if(m_position.SelectByIndex(k))
         if(m_position.Symbol() == Symbol())
            if(m_position.Magic() == xs_Magic)
               if(m_position.PositionType() == POSITION_TYPE_BUY ||
                  m_position.PositionType() == POSITION_TYPE_SELL)
                 {
                  op = NormalizeDouble(m_position.PriceOpen(), Digits());
                  lt = NormalizeDouble(m_position.Volume(), 2);
                  tk = m_position.Ticket();

                  if(m_position.PositionType() == POSITION_TYPE_BUY)
                    {
                     b++;
                     if(op > BuyPriceMax || BuyPriceMax == 0) { BuyPriceMax = op; BuyPriceMaxLot = lt; BuyPriceMaxTic = tk; }
                     if(op < BuyPriceMin || BuyPriceMin == 0) { BuyPriceMin = op; BuyPriceMinLot = lt; BuyPriceMinTic = tk; }
                    }
                  if(m_position.PositionType() == POSITION_TYPE_SELL)
                    {
                     s++;
                     if(op > SelPriceMax || SelPriceMax == 0) { SelPriceMax = op; SelPriceMaxLot = lt; SelPriceMaxTic = tk; }
                     if(op < SelPriceMin || SelPriceMin == 0) { SelPriceMin = op; SelPriceMinLot = lt; SelPriceMinTic = tk; }
                    }
                 }

   //--- Average / breakeven prices
   double AverageBuyPrice = 0, AverageSelPrice = 0;

   if(xs_CloseType == AVERAGE_TP)
     {
      if(b >= 2)
         AverageBuyPrice = NormalizeDouble(
            (BuyPriceMax * BuyPriceMaxLot + BuyPriceMin * BuyPriceMinLot) /
            (BuyPriceMaxLot + BuyPriceMinLot) + xs_MinProfit * Point(), Digits());
      if(s >= 2)
         AverageSelPrice = NormalizeDouble(
            (SelPriceMax * SelPriceMaxLot + SelPriceMin * SelPriceMinLot) /
            (SelPriceMaxLot + SelPriceMinLot) - xs_MinProfit * Point(), Digits());
     }
   if(xs_CloseType == PARTIAL_CLOSE)
     {
      if(b >= 2)
         AverageBuyPrice = NormalizeDouble(
            (BuyPriceMax * xs_StartLots + BuyPriceMin * BuyPriceMinLot) /
            (xs_StartLots + BuyPriceMinLot) + xs_MinProfit * Point(), Digits());
      if(s >= 2)
         AverageSelPrice = NormalizeDouble(
            (SelPriceMax * SelPriceMaxLot + SelPriceMin * xs_StartLots) /
            (SelPriceMaxLot + xs_StartLots) - xs_MinProfit * Point(), Digits());
     }

   //--- Next lot sizes (double the last)
   double BuyLot = (BuyPriceMinLot == 0) ? xs_StartLots : BuyPriceMinLot * 2;
   double SelLot = (SelPriceMaxLot == 0) ? xs_StartLots : SelPriceMaxLot * 2;

   if(xs_MaxLots > 0)
     {
      if(BuyLot > xs_MaxLots) BuyLot = xs_MaxLots;
      if(SelLot > xs_MaxLots) SelLot = xs_MaxLots;
     }

   if(!CheckVolumeValue(BuyLot) || !CheckVolumeValue(SelLot))
      return;

   //--- Price data
   MqlRates rates[];
   CopyRates(Symbol(), PERIOD_CURRENT, 0, 2, rates);

   MqlTick tick;
   if(!SymbolInfoTick(Symbol(), tick))
      Print("[XANDER Grid XAUUSD] SymbolInfoTick failed, error=", GetLastError());

   //--- Open new grid levels (skip if drawdown paused)
   if(!drawdownPaused)
     {
      if(rates[1].close > rates[1].open)
         if((b == 0) || (b > 0 && (BuyPriceMin - tick.ask) > (xs_GridStep * Point())))
            if(!trade.Buy(NormalizeDouble(BuyLot, 2)))
               Print("[XANDER Grid XAUUSD] Buy error #", GetLastError());

      if(rates[1].close < rates[1].open)
         if((s == 0) || (s > 0 && (tick.bid - SelPriceMax) > (xs_GridStep * Point())))
            if(!trade.Sell(NormalizeDouble(SelLot, 2)))
               Print("[XANDER Grid XAUUSD] Sell error #", GetLastError());
     }

   //--- Manage TP for single positions and average TP for grid
   total = PositionsTotal();
   for(int k = total - 1; k >= 0; k--)
      if(m_position.SelectByIndex(k))
         if(m_position.Symbol() == Symbol())
            if(m_position.Magic() == xs_Magic)
               if(m_position.PositionType() == POSITION_TYPE_BUY ||
                  m_position.PositionType() == POSITION_TYPE_SELL)
                 {
                  op = NormalizeDouble(m_position.PriceOpen(), Digits());
                  tp = NormalizeDouble(m_position.TakeProfit(), Digits());
                  lt = NormalizeDouble(m_position.Volume(), 2);
                  tk = m_position.Ticket();

                  //--- Single position TP
                  if(m_position.PositionType() == POSITION_TYPE_BUY && b == 1 && tp == 0)
                     if(!trade.PositionModify(tk, m_position.StopLoss(),
                        NormalizeDouble(tick.ask + xs_TakeProfit * Point(), Digits())))
                        Print("[XANDER Grid XAUUSD] Modify error #", GetLastError());

                  if(m_position.PositionType() == POSITION_TYPE_SELL && s == 1 && tp == 0)
                     if(!trade.PositionModify(tk, m_position.StopLoss(),
                        NormalizeDouble(tick.bid - xs_TakeProfit * Point(), Digits())))
                        Print("[XANDER Grid XAUUSD] Modify error #", GetLastError());

                  //--- Average TP mode
                  if(xs_CloseType == AVERAGE_TP)
                    {
                     if(m_position.PositionType() == POSITION_TYPE_BUY && b >= 2)
                       {
                        if(tk == BuyPriceMaxTic || tk == BuyPriceMinTic)
                           if(tick.bid < AverageBuyPrice && tp != AverageBuyPrice)
                              if(!trade.PositionModify(tk, m_position.StopLoss(), AverageBuyPrice))
                                 Print("[XANDER Grid XAUUSD] Modify error #", GetLastError());

                        if(tk != BuyPriceMaxTic && tk != BuyPriceMinTic && tp != 0)
                           if(!trade.PositionModify(tk, 0, 0))
                              Print("[XANDER Grid XAUUSD] Modify error #", GetLastError());
                       }

                     if(m_position.PositionType() == POSITION_TYPE_SELL && s >= 2)
                       {
                        if(tk == SelPriceMaxTic || tk == SelPriceMinTic)
                           if(tick.ask > AverageSelPrice && tp != AverageSelPrice)
                              if(!trade.PositionModify(tk, m_position.StopLoss(), AverageSelPrice))
                                 Print("[XANDER Grid XAUUSD] Modify error #", GetLastError());

                        if(tk != SelPriceMaxTic && tk != SelPriceMinTic && tp != 0)
                           if(!trade.PositionModify(tk, 0, 0))
                              Print("[XANDER Grid XAUUSD] Modify error #", GetLastError());
                       }
                    }
                 }

   //--- Partial Close mode
   if(xs_CloseType == PARTIAL_CLOSE)
     {
      if(b >= 2)
         if(AverageBuyPrice > 0 && tick.bid >= AverageBuyPrice)
           {
            if(!trade.PositionClosePartial(BuyPriceMaxTic, xs_StartLots, xs_Slippage))
               Print("[XANDER Grid XAUUSD] PartialClose error #", GetLastError());
            if(!trade.PositionClose(BuyPriceMinTic, xs_Slippage))
               Print("[XANDER Grid XAUUSD] Close error #", GetLastError());
           }
      if(s >= 2)
         if(AverageSelPrice > 0 && tick.ask <= AverageSelPrice)
           {
            if(!trade.PositionClosePartial(SelPriceMinTic, xs_StartLots, xs_Slippage))
               Print("[XANDER Grid XAUUSD] PartialClose error #", GetLastError());
            if(!trade.PositionClose(SelPriceMaxTic, xs_Slippage))
               Print("[XANDER Grid XAUUSD] Close error #", GetLastError());
           }
     }
  }

//+------------------------------------------------------------------+
//| CheckVolumeValue — validates lot size against broker limits     |
//+------------------------------------------------------------------+
bool CheckVolumeValue(double volume)
  {
   double min_volume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   if(volume < min_volume)
      return false;

   double max_volume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   if(volume > max_volume)
      return false;

   double volume_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   int ratio = (int)MathRound(volume / volume_step);
   if(MathAbs(ratio * volume_step - volume) > 0.0000001)
      return false;

   return true;
  }
//+------------------------------------------------------------------+
