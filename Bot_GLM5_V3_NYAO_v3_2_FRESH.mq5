//+------------------------------------------------------------------+
//|                                             Bot GLM5_V3_NYAO.mq5 |
//|                        GLM5 V3 + NYAO Integration v3.2           |
//|                        HedgeRequireSignal + PartialClose + NewsFilter |
//+------------------------------------------------------------------+
#property copyright "GLM5_V3 + NYAO Integration"
#property link      ""
#property version   "3.2"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+

//====== GENERAL SETTINGS ======
input group "====== GENERAL SETTINGS ======"
input ulong  InpMagicNumber       = 301;      // Magic Number (Main Buy)
input ulong  InpMagicSell         = 302;      // Magic Number (Main Sell)
input ulong  InpMagicHedgeBuy     = 303;      // Magic Number (Hedge Buy)
input ulong  InpMagicHedgeSell    = 304;      // Magic Number (Hedge Sell)
input double InpLotSize           = 0.02;     // Lot Size
input int    InpSlippage          = 30;       // Slippage (points)
input int    InpMaxSpreadPoints   = 50;       // Max Spread (points)

//====== SIGNAL ENGINE ======
input group "====== SIGNAL ENGINE ======"
input int    InpFastEMA           = 8;        // Fast EMA Period
input int    InpSlowEMA           = 21;       // Slow EMA Period
input int    InpRSIPeriod         = 14;       // RSI Period
input int    InpRSIOverbought     = 70;       // RSI Overbought Level
input int    InpRSIOversold       = 30;       // RSI Oversold Level
input int    InpADXPeriod         = 14;       // ADX Period
input double InpADXThreshold      = 25.0;     // ADX Threshold
input int    InpATRPeriod         = 14;       // ATR Period
input double InpMinBuyScore       = 6.5;      // Minimum Buy Signal Score
input double InpMinSellScore      = 6.5;      // Minimum Sell Signal Score

//====== TRAILING STOP ======
input group "====== TRAILING STOP ======"
input bool   InpUseTrailing       = true;     // Enable Trailing Stop
input int    InpTrailingMode      = 0;        // Trailing Mode (0=Retracement, 1=ATR)
input double InpTrailStartUSD     = 1.0;      // Trail Start (USD profit)
input double InpTrailStepUSD      = 0.5;      // Trail Step (USD)
input double InpTrailRetracePct   = 50.0;     // Retracement % to trigger
input double InpATRMultiplier     = 1.5;      // ATR Multiplier

//====== PROFIT LOCK ======
input group "====== PROFIT LOCK ======"
input bool   InpUseProfitLock     = true;     // Enable Profit Lock
input double InpProfitLock1       = 1.0;      // Lock Level 1 (USD)
input double InpLockSL1           = 0.3;      // SL at Level 1 (USD)
input double InpProfitLock2       = 2.0;      // Lock Level 2 (USD)
input double InpLockSL2           = 1.0;      // SL at Level 2 (USD)
input double InpProfitLock3       = 3.0;      // Lock Level 3 (USD)
input double InpLockSL3           = 2.0;      // SL at Level 3 (USD)

//====== BASKET RECOVERY ======
input group "====== BASKET RECOVERY ======"
input bool   InpUseBasketRecovery = true;     // Enable Basket Recovery
input double InpHedgeTriggerUSD   = -2.0;     // Hedge Trigger (USD loss)
input double InpHedgeLotMult      = 1.5;      // Hedge Lot Multiplier
input double InpGridLotMult       = 1.0;      // Grid Lot Multiplier
input double InpMaxBasketLossUSD  = -10.0;    // Max Basket Loss (USD)
input double InpBasketTPUSD       = 1.0;      // Basket Take Profit (USD)

//====== HEALTH EXIT ======
input group "====== HEALTH EXIT ======"
input bool   InpUseHealthExit     = true;     // Enable Health Exit
input int    InpHealthBars        = 5;        // Health Check Bars
input double InpHealthMaxDD       = -1.5;     // Max Drawdown for Health Exit

//====== TIME FILTER ======
input group "====== TIME FILTER ======"
input bool   InpUseTimeFilter     = false;    // Enable Time Filter
input int    InpTradeStartHour    = 8;        // Trade Start Hour (Server)
input int    InpTradeEndHour      = 20;       // Trade End Hour (Server)

//====== LOGGING ======
input group "====== LOGGING ======"
input bool   InpEnableLogging     = true;     // Enable Logging
input int    InpLogLevel          = 2;        // Log Level (1=Errors, 2=Info, 3=Debug)

//====== NYAO: HEDGE SIGNAL FILTER ======
input group "====== NYAO: HEDGE SIGNAL FILTER ======"
input bool   InpHedgeRequireSignal  = true;   // Only hedge if opposite signal confirms
input double InpHedgeMinSignalScore = 4.5;    // Min opposite signal score for hedge

//====== NYAO: PARTIAL CLOSE ======
input group "====== NYAO: PARTIAL CLOSE ======"
input bool   InpEnablePartialClose    = true;  // Enable partial close by signal decay
input double InpPartialCloseL1Signal  = 0.75;  // Close 25% when signal drops to 75%
input double InpPartialCloseL2Signal  = 0.50;  // Close 50% when signal drops to 50%
input double InpPartialCloseL3Signal  = 0.25;  // Close all when signal drops to 25%

//====== NYAO: NEWS FILTER ======
input group "====== NYAO: NEWS FILTER ======"
input bool   InpEnableNewsFilter   = true;   // Pause trading on high-impact news
input int    InpNewsMinutesBefore  = 30;     // Minutes before news
input int    InpNewsMinutesAfter   = 30;     // Minutes after news

//+------------------------------------------------------------------+
//| STRUCTURES                                                       |
//+------------------------------------------------------------------+

struct SignalStrength
{
   double emaScore;
   double rsiScore;
   double adxScore;
   double atrScore;
   double finalScore;
   string verdict;
};

struct ScalperSide
{
   bool      hasPosition;
   ulong     ticket;
   ulong     magic;
   double    openPrice;
   double    lots;
   double    sl;
   double    tp;
   datetime  openTime;
   bool      isHedge;
   double    highestProfit;
   double    initialScore;      // NYAO: score when position opened
   int       partialCloseLevel; // NYAO: 0=none, 1=L1, 2=L2, 3=closed
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+

CTrade      Trade;
CPositionInfo PositionInfo;

ScalperSide g_buy;
ScalperSide g_sell;

bool        g_basketActive = false;
double      g_basketOpenProfit = 0;
datetime    g_lastBarTime = 0;

// NYAO: News Filter globals
bool        g_isNewsTime = false;
datetime    g_lastNewsCheck = 0;

int         g_handleFastEMA = INVALID_HANDLE;
int         g_handleSlowEMA = INVALID_HANDLE;
int         g_handleRSI = INVALID_HANDLE;
int         g_handleADX = INVALID_HANDLE;
int         g_handleATR = INVALID_HANDLE;

// Signal cache
datetime    g_lastSignalTick = 0;
SignalStrength g_cachedBuySignal;
SignalStrength g_cachedSellSignal;

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(InpMagicNumber);
   Trade.SetDeviationInPoints(InpSlippage);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.SetAsyncMode(false);

   g_handleFastEMA = iMA(_Symbol, PERIOD_CURRENT, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_handleSlowEMA = iMA(_Symbol, PERIOD_CURRENT, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_handleRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   g_handleADX = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   g_handleATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);

   if(g_handleFastEMA == INVALID_HANDLE || g_handleSlowEMA == INVALID_HANDLE ||
      g_handleRSI == INVALID_HANDLE || g_handleADX == INVALID_HANDLE ||
      g_handleATR == INVALID_HANDLE)
   {
      LogMessage(1, "[INIT FAILED] Error creating indicator handles");
      return(INIT_FAILED);
   }

   ResetSide(g_buy, InpMagicNumber);
   ResetSide(g_sell, InpMagicSell);
   g_basketActive = false;
   g_basketOpenProfit = 0;
   g_isNewsTime = false;
   g_lastNewsCheck = 0;

   LogMessage(2, StringFormat("[INIT OK] GLM5_V3_NYAO v3.2 | Symbol=%s | Lot=%.2f | HedgeSignal=%s | PartialClose=%s | NewsFilter=%s",
               _Symbol, InpLotSize,
               InpHedgeRequireSignal ? "ON" : "OFF",
               InpEnablePartialClose ? "ON" : "OFF",
               InpEnableNewsFilter ? "ON" : "OFF"));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(g_handleFastEMA);
   IndicatorRelease(g_handleSlowEMA);
   IndicatorRelease(g_handleRSI);
   IndicatorRelease(g_handleADX);
   IndicatorRelease(g_handleATR);
   LogMessage(2, "[DEINIT] Bot stopped");
}

//+------------------------------------------------------------------+
//| EXPERT TICK                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsTradeAllowed()) return;

   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool newBar = (currentBarTime != g_lastBarTime);
   if(newBar) g_lastBarTime = currentBarTime;

   // Scan positions
   ScanPositions();

   // Manage existing positions (trailing, health, profit lock)
   ManagePositions();

   // NYAO: Check partial close (before trailing updates)
   CheckPartialClose();

   // NYAO: Check high impact news (throttled internally)
   CheckHighImpactNews();

   // Manage basket recovery
   if(InpUseBasketRecovery)
      ManageBasketRecovery();

   // Manage new entries
   if(newBar)
      ManageEntries();
}

//+------------------------------------------------------------------+
//| SCAN POSITIONS                                                   |
//+------------------------------------------------------------------+
void ScanPositions()
{
   ResetSide(g_buy, InpMagicNumber);
   ResetSide(g_sell, InpMagicSell);

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      ulong magic = PositionGetInteger(POSITION_MAGIC);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY)
      {
         if(magic == InpMagicNumber)
            FillSide(g_buy, ticket, false);
         else if(magic == InpMagicHedgeBuy)
            FillSide(g_buy, ticket, true);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(magic == InpMagicSell)
            FillSide(g_sell, ticket, false);
         else if(magic == InpMagicHedgeSell)
            FillSide(g_sell, ticket, true);
      }
   }

   // Detect basket state
   g_basketActive = (g_buy.hasPosition && g_buy.isHedge) || (g_sell.hasPosition && g_sell.isHedge);
}

//+------------------------------------------------------------------+
//| RESET SIDE                                                       |
//+------------------------------------------------------------------+
void ResetSide(ScalperSide &side, ulong magic)
{
   side.hasPosition = false;
   side.ticket = 0;
   side.magic = magic;
   side.openPrice = 0;
   side.lots = 0;
   side.sl = 0;
   side.tp = 0;
   side.openTime = 0;
   side.isHedge = false;
   side.highestProfit = 0;
   // NOTE: initialScore and partialCloseLevel are NOT reset here
   // They are preserved by FillSide() to survive across ticks
}

//+------------------------------------------------------------------+
//| FILL SIDE — BUG #1 FIX: Preserve initialScore and partialCloseLevel |
//+------------------------------------------------------------------+
void FillSide(ScalperSide &side, ulong ticket, bool isHedge)
{
   // BUG #1 FIX: Save these BEFORE ResetSide() clears them
   double savedScore = side.initialScore;
   int    savedLevel = side.partialCloseLevel;

   side.hasPosition = true;
   side.ticket      = ticket;
   side.openPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
   side.lots        = PositionGetDouble(POSITION_VOLUME);
   side.sl          = PositionGetDouble(POSITION_SL);
   side.tp          = PositionGetDouble(POSITION_TP);
   side.openTime    = (datetime)PositionGetInteger(POSITION_TIME);
   side.isHedge     = isHedge;

   double currentProfit = PositionGetDouble(POSITION_PROFIT)
                        + PositionGetDouble(POSITION_SWAP);
   if(currentProfit > side.highestProfit)
      side.highestProfit = currentProfit;

   // BUG #1 FIX: Restore the preserved values
   side.initialScore      = savedScore;
   side.partialCloseLevel = savedLevel;
}

//+------------------------------------------------------------------+
//| MANAGE POSITIONS                                                 |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(g_buy.hasPosition && !g_buy.isHedge)
   {
      CheckProfitLock(g_buy);
      if(InpUseTrailing)
         UpdateTrailing(g_buy, POSITION_TYPE_BUY);
      if(InpUseHealthExit)
         CheckPositionHealth(g_buy, POSITION_TYPE_BUY);
   }

   if(g_sell.hasPosition && !g_sell.isHedge)
   {
      CheckProfitLock(g_sell);
      if(InpUseTrailing)
         UpdateTrailing(g_sell, POSITION_TYPE_SELL);
      if(InpUseHealthExit)
         CheckPositionHealth(g_sell, POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| CHECK PROFIT LOCK — BUG #4 FIX: Directional for BUY and SELL    |
//+------------------------------------------------------------------+
void CheckProfitLock(ScalperSide &side)
{
   if(!InpUseProfitLock) return;
   if(!side.hasPosition) return;

   double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   double newSL = 0;

   // BUG #4 FIX: Detect position type for correct SL direction
   // BUY: SL = openPrice + lockLevel (above open)
   // SELL: SL = openPrice - lockLevel (below open)
   bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   if(profit >= InpProfitLock3)
      newSL = isBuy ? side.openPrice + InpLockSL3
                    : side.openPrice - InpLockSL3;
   else if(profit >= InpProfitLock2)
      newSL = isBuy ? side.openPrice + InpLockSL2
                    : side.openPrice - InpLockSL2;
   else if(profit >= InpProfitLock1)
      newSL = isBuy ? side.openPrice + InpLockSL1
                    : side.openPrice - InpLockSL1;

   if(newSL > 0)
   {
      bool slImproves = (isBuy  && newSL > side.sl) ||
                        (!isBuy && (newSL < side.sl || side.sl == 0));
      if(slImproves && newSL != side.sl)
      {
         Trade.PositionModify(side.ticket, newSL, side.tp);
         LogMessage(3, StringFormat("[PROFIT LOCK] Ticket %d | SL moved to %.2f | Profit: %.2f | Type: %s",
                     side.ticket, newSL, profit, isBuy ? "BUY" : "SELL"));
      }
   }
}

//+------------------------------------------------------------------+
//| UPDATE TRAILING                                                  |
//+------------------------------------------------------------------+
void UpdateTrailing(ScalperSide &side, ENUM_POSITION_TYPE posType)
{
   if(!side.hasPosition) return;

   double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   if(profit < InpTrailStartUSD) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double newSL = side.sl;

   if(InpTrailingMode == 0) // Retracement mode
   {
      double peakProfit = side.highestProfit;
      double retraceThreshold = peakProfit * (InpTrailRetracePct / 100.0);
      double triggerSL = peakProfit - retraceThreshold;

      if(profit <= triggerSL && profit > InpTrailStepUSD)
      {
         if(posType == POSITION_TYPE_BUY)
            newSL = NormalizeDouble(bid - InpTrailStepUSD / side.lots, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
         else
            newSL = NormalizeDouble(ask + InpTrailStepUSD / side.lots, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      }
   }
   else // ATR mode
   {
      double atr[];
      if(CopyBuffer(g_handleATR, 0, 0, 1, atr) > 0)
      {
         double atrSL = atr[0] * InpATRMultiplier;
         if(posType == POSITION_TYPE_BUY)
            newSL = NormalizeDouble(bid - atrSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
         else
            newSL = NormalizeDouble(ask + atrSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      }
   }

   // Only move SL in favorable direction
   if(posType == POSITION_TYPE_BUY && newSL > side.sl && newSL > side.openPrice)
   {
      Trade.PositionModify(side.ticket, newSL, side.tp);
      LogMessage(3, StringFormat("[TRAILING BUY] Ticket %d | SL: %.2f -> %.2f",
                  side.ticket, side.sl, newSL));
   }
   else if(posType == POSITION_TYPE_SELL && (newSL < side.sl || side.sl == 0) && newSL < side.openPrice && newSL > 0)
   {
      Trade.PositionModify(side.ticket, newSL, side.tp);
      LogMessage(3, StringFormat("[TRAILING SELL] Ticket %d | SL: %.2f -> %.2f",
                  side.ticket, side.sl, newSL));
   }
}

//+------------------------------------------------------------------+
//| CHECK POSITION HEALTH                                            |
//+------------------------------------------------------------------+
void CheckPositionHealth(ScalperSide &side, ENUM_POSITION_TYPE posType)
{
   if(!InpUseHealthExit) return;
   if(!side.hasPosition) return;

   double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

   // Check if profit has been declining for N bars
   double highest = side.highestProfit;
   if(highest > 0 && profit < highest - MathAbs(InpHealthMaxDD))
   {
      // Check bars since open
      int barsSinceOpen = iBarShift(_Symbol, PERIOD_CURRENT, side.openTime);
      if(barsSinceOpen >= InpHealthBars)
      {
         ClosePosition(side.ticket, "HEALTH_EXIT_DECLINE");
         LogMessage(2, StringFormat("[HEALTH EXIT] Ticket %d | Profit dropped from %.2f to %.2f",
                     side.ticket, highest, profit));
      }
   }
}

//+------------------------------------------------------------------+
//| MANAGE ENTRIES                                                   |
//+------------------------------------------------------------------+
void ManageEntries()
{
   // NYAO: Block new entries during high-impact news
   if(g_isNewsTime)
   {
      if(InpEnableLogging && InpLogLevel >= 2)
         LogMessage(2, "[NEWS] Entradas bloqueadas por evento de alto impacto");
      return;
   }

   // Time filter
   if(InpUseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      if(dt.hour < InpTradeStartHour || dt.hour >= InpTradeEndHour)
         return;
   }

   // Spread filter
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
   {
      LogMessage(3, StringFormat("[SPREAD FILTER] Spread=%d > Max=%d", spread, InpMaxSpreadPoints));
      return;
   }

   // Get signals
   SignalStrength buySignal = GetSignalStrength(ORDER_TYPE_BUY);
   SignalStrength sellSignal = GetSignalStrength(ORDER_TYPE_SELL);

   // Open BUY
   if(!g_buy.hasPosition && buySignal.finalScore >= InpMinBuyScore)
   {
      OpenOrder(ORDER_TYPE_BUY, buySignal);
   }

   // Open SELL
   if(!g_sell.hasPosition && sellSignal.finalScore >= InpMinSellScore)
   {
      OpenOrder(ORDER_TYPE_SELL, sellSignal);
   }
}

//+------------------------------------------------------------------+
//| OPEN ORDER                                                       |
//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE orderType, SignalStrength &signal)
{
   double price = (orderType == ORDER_TYPE_BUY) ?
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double lots = NormalizeVolume(InpLotSize);
   ulong magic = (orderType == ORDER_TYPE_BUY) ? InpMagicNumber : InpMagicSell;

   string comment = StringFormat("GLM5|Score=%.1f", signal.finalScore);

   if(orderType == ORDER_TYPE_BUY)
   {
      if(Trade.Buy(lots, _Symbol, price, 0, 0, comment))
      {
         g_buy.initialScore = signal.finalScore;
         g_buy.partialCloseLevel = 0;
         LogMessage(2, StringFormat("[OPEN BUY] Lots=%.2f | Price=%.2f | Score=%.1f",
                     lots, price, signal.finalScore));
      }
   }
   else
   {
      if(Trade.Sell(lots, _Symbol, price, 0, 0, comment))
      {
         g_sell.initialScore = signal.finalScore;
         g_sell.partialCloseLevel = 0;
         LogMessage(2, StringFormat("[OPEN SELL] Lots=%.2f | Price=%.2f | Score=%.1f",
                     lots, price, signal.finalScore));
      }
   }
}

//+------------------------------------------------------------------+
//| MANAGE BASKET RECOVERY                                           |
//+------------------------------------------------------------------+
void ManageBasketRecovery()
{
   if(!g_basketActive)
   {
      // Check if we need to activate basket
      CheckBasketTrigger();
   }
   else
   {
      // Manage active basket
      ManageActiveBasket();
   }
}

//+------------------------------------------------------------------+
//| CHECK BASKET TRIGGER                                             |
//+------------------------------------------------------------------+
void CheckBasketTrigger()
{
   // Check BUY side for hedge trigger
   if(g_buy.hasPosition && !g_buy.isHedge)
   {
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(profit <= InpHedgeTriggerUSD)
      {
         // NYAO: HedgeRequireSignal - verify opposite signal before opening hedge
         if(InpHedgeRequireSignal)
         {
            SignalStrength hedgeStrength = GetSignalStrength(ORDER_TYPE_SELL);
            if(hedgeStrength.finalScore < InpHedgeMinSignalScore)
            {
               LogMessage(2, StringFormat("[HEDGE BLOCKED] Signal %.1f < %.1f | Spike/noticia detectada | Ticket %d",
                           hedgeStrength.finalScore, InpHedgeMinSignalScore, g_buy.ticket));
               return;
            }
            LogMessage(2, StringFormat("[HEDGE OK] Signal %.1f >= %.1f | Hedge confirmado | Ticket %d",
                        hedgeStrength.finalScore, InpHedgeMinSignalScore, g_buy.ticket));
         }

         OpenHedge(POSITION_TYPE_BUY, profit);
      }
   }

   // Check SELL side for hedge trigger
   if(g_sell.hasPosition && !g_sell.isHedge)
   {
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(profit <= InpHedgeTriggerUSD)
      {
         // NYAO: HedgeRequireSignal - verify opposite signal before opening hedge
         if(InpHedgeRequireSignal)
         {
            SignalStrength hedgeStrength = GetSignalStrength(ORDER_TYPE_BUY);
            if(hedgeStrength.finalScore < InpHedgeMinSignalScore)
            {
               LogMessage(2, StringFormat("[HEDGE BLOCKED] Signal %.1f < %.1f | Spike/noticia detectada | Ticket %d",
                           hedgeStrength.finalScore, InpHedgeMinSignalScore, g_sell.ticket));
               return;
            }
            LogMessage(2, StringFormat("[HEDGE OK] Signal %.1f >= %.1f | Hedge confirmado | Ticket %d",
                        hedgeStrength.finalScore, InpHedgeMinSignalScore, g_sell.ticket));
         }

         OpenHedge(POSITION_TYPE_SELL, profit);
      }
   }
}

//+------------------------------------------------------------------+
//| OPEN HEDGE — BUG #2 FIX: Set correct magic number                |
//+------------------------------------------------------------------+
void OpenHedge(ENUM_POSITION_TYPE origType, double origPnL)
{
   double lots = NormalizeVolume(InpLotSize * InpHedgeLotMult);
   double price;
   string comment;

   if(origType == POSITION_TYPE_BUY)
   {
      // Original BUY losing → open hedge SELL (magic 304)
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      comment = StringFormat("BASKET|HEDGE SELL|OrigTicket=%d", g_buy.ticket);

      // BUG #2 FIX: Set hedge magic before opening, restore after
      Trade.SetExpertMagicNumber(InpMagicHedgeSell);
      Trade.Sell(lots, _Symbol, price, 0, 0, comment);
      Trade.SetExpertMagicNumber(InpMagicNumber);

      g_basketActive = true;
      g_basketOpenProfit = origPnL;
      LogMessage(2, StringFormat("[HEDGE OPEN] SELL | Lots=%.2f | Price=%.2f | OrigProfit=%.2f | Magic=%d",
                  lots, price, origPnL, InpMagicHedgeSell));
   }
   else
   {
      // Original SELL losing → open hedge BUY (magic 303)
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      comment = StringFormat("BASKET|HEDGE BUY|OrigTicket=%d", g_sell.ticket);

      // BUG #2 FIX: Set hedge magic before opening, restore after
      Trade.SetExpertMagicNumber(InpMagicHedgeBuy);
      Trade.Buy(lots, _Symbol, price, 0, 0, comment);
      Trade.SetExpertMagicNumber(InpMagicSell);

      g_basketActive = true;
      g_basketOpenProfit = origPnL;
      LogMessage(2, StringFormat("[HEDGE OPEN] BUY | Lots=%.2f | Price=%.2f | OrigProfit=%.2f | Magic=%d",
                  lots, price, origPnL, InpMagicHedgeBuy));
   }
}

//+------------------------------------------------------------------+
//| MANAGE ACTIVE BASKET                                             |
//+------------------------------------------------------------------+
void ManageActiveBasket()
{
   double totalProfit = 0;
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      ulong magic = PositionGetInteger(POSITION_MAGIC);
      if(magic == InpMagicNumber || magic == InpMagicSell ||
         magic == InpMagicHedgeBuy || magic == InpMagicHedgeSell)
      {
         totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }

   // Check max loss
   if(totalProfit <= InpMaxBasketLossUSD)
   {
      CloseAllPositions("BASKET_MAX_LOSS");
      LogMessage(1, StringFormat("[BASKET STOP] TotalLoss=%.2f <= Max=%.2f", totalProfit, InpMaxBasketLossUSD));
      return;
   }

   // Check take profit
   if(totalProfit >= InpBasketTPUSD)
   {
      CloseAllPositions("BASKET_TAKE_PROFIT");
      LogMessage(2, StringFormat("[BASKET TP] TotalProfit=%.2f >= Target=%.2f", totalProfit, InpBasketTPUSD));
      return;
   }
}

//+------------------------------------------------------------------+
//| CLOSE POSITION                                                   |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
   if(ticket == 0) return;

   Trade.PositionClose(ticket);
   LogMessage(2, StringFormat("[CLOSE] Ticket %d | Reason: %s", ticket, reason));

   // Reset partial close state when position closes
   if(ticket == g_buy.ticket)
   {
      g_buy.initialScore = 0;
      g_buy.partialCloseLevel = 0;
   }
   else if(ticket == g_sell.ticket)
   {
      g_sell.initialScore = 0;
      g_sell.partialCloseLevel = 0;
   }
}

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS                                              |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      ulong magic = PositionGetInteger(POSITION_MAGIC);
      if(magic == InpMagicNumber || magic == InpMagicSell ||
         magic == InpMagicHedgeBuy || magic == InpMagicHedgeSell)
      {
         Trade.PositionClose(ticket);
      }
   }

   // Reset all partial close states
   g_buy.initialScore = 0;
   g_buy.partialCloseLevel = 0;
   g_sell.initialScore = 0;
   g_sell.partialCloseLevel = 0;

   g_basketActive = false;
   g_basketOpenProfit = 0;

   LogMessage(2, StringFormat("[CLOSE ALL] Reason: %s", reason));
}

//+------------------------------------------------------------------+
//| GET SIGNAL STRENGTH                                              |
//+------------------------------------------------------------------+
SignalStrength GetSignalStrength(ENUM_ORDER_TYPE orderType)
{
   SignalStrength result;
   result.emaScore = 0;
   result.rsiScore = 0;
   result.adxScore = 0;
   result.atrScore = 0;
   result.finalScore = 0;
   result.verdict = "NONE";

   double fastEMA[], slowEMA[], rsi[], adxMain[], adxPlus[], adxMinus[], atr[];

   if(CopyBuffer(g_handleFastEMA, 0, 0, 3, fastEMA) <= 0) return result;
   if(CopyBuffer(g_handleSlowEMA, 0, 0, 3, slowEMA) <= 0) return result;
   if(CopyBuffer(g_handleRSI, 0, 0, 3, rsi) <= 0) return result;
   if(CopyBuffer(g_handleADX, 0, 0, 3, adxMain) <= 0) return result;
   if(CopyBuffer(g_handleADX, 1, 0, 3, adxPlus) <= 0) return result;
   if(CopyBuffer(g_handleADX, 2, 0, 3, adxMinus) <= 0) return result;
   if(CopyBuffer(g_handleATR, 0, 0, 3, atr) <= 0) return result;

   double close[], high[], low[];
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 5, close) <= 0) return result;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, 5, high) <= 0) return result;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, 5, low) <= 0) return result;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // EMA Score
   bool emaBullish = fastEMA[0] > slowEMA[0];
   bool emaBearish = fastEMA[0] < slowEMA[0];
   double emaDistance = MathAbs(fastEMA[0] - slowEMA[0]) / point;

   // RSI Score
   double rsiValue = rsi[0];

   // ADX Score
   double adxValue = adxMain[0];
   bool adxStrong = adxValue >= InpADXThreshold;
   bool diPlusAbove = adxPlus[0] > adxMinus[0];
   bool diMinusAbove = adxMinus[0] > adxPlus[0];

   // ATR Score (volatility)
   double atrValue = atr[0];
   double atrInPips = atrValue / (point * 10);

   // Compute scores
   if(orderType == ORDER_TYPE_BUY)
   {
      // EMA: bullish alignment
      if(emaBullish)
      {
         result.emaScore = MathMin(3.0, 1.5 + emaDistance / 50.0);
         if(fastEMA[1] > slowEMA[1] && fastEMA[2] <= slowEMA[2])
            result.emaScore += 1.0; // Fresh cross
      }
      else if(emaBearish)
      {
         result.emaScore = MathMax(0, 1.0 - emaDistance / 100.0);
      }
      else
      {
         result.emaScore = 1.0;
      }

      // RSI: not overbought, preferably oversold or neutral rising
      if(rsiValue < InpRSIOversold)
         result.rsiScore = 3.0;
      else if(rsiValue < 50)
         result.rsiScore = 2.5;
      else if(rsiValue < InpRSIOverbought)
         result.rsiScore = 2.0;
      else
         result.rsiScore = 0.5;

      // ADX: trend strength
      if(adxStrong && diPlusAbove)
         result.adxScore = 2.5;
      else if(adxStrong)
         result.adxScore = 2.0;
      else if(diPlusAbove)
         result.adxScore = 1.5;
      else
         result.adxScore = 0.5;

      // ATR: moderate volatility is good
      if(atrInPips >= 3.0 && atrInPips <= 15.0)
         result.atrScore = 2.0;
      else if(atrInPips > 15.0)
         result.atrScore = 1.0;
      else
         result.atrScore = 0.5;

      result.finalScore = result.emaScore + result.rsiScore + result.adxScore + result.atrScore;
      result.verdict = (result.finalScore >= InpMinBuyScore) ? "STRONG_BUY" : "WEAK_BUY";
   }
   else // SELL
   {
      // EMA: bearish alignment
      if(emaBearish)
      {
         result.emaScore = MathMin(3.0, 1.5 + emaDistance / 50.0);
         if(fastEMA[1] < slowEMA[1] && fastEMA[2] >= slowEMA[2])
            result.emaScore += 1.0; // Fresh cross
      }
      else if(emaBullish)
      {
         result.emaScore = MathMax(0, 1.0 - emaDistance / 100.0);
      }
      else
      {
         result.emaScore = 1.0;
      }

      // RSI: not oversold, preferably overbought or neutral falling
      if(rsiValue > InpRSIOverbought)
         result.rsiScore = 3.0;
      else if(rsiValue > 50)
         result.rsiScore = 2.5;
      else if(rsiValue > InpRSIOversold)
         result.rsiScore = 2.0;
      else
         result.rsiScore = 0.5;

      // ADX: trend strength
      if(adxStrong && diMinusAbove)
         result.adxScore = 2.5;
      else if(adxStrong)
         result.adxScore = 2.0;
      else if(diMinusAbove)
         result.adxScore = 1.5;
      else
         result.adxScore = 0.5;

      // ATR: moderate volatility is good
      if(atrInPips >= 3.0 && atrInPips <= 15.0)
         result.atrScore = 2.0;
      else if(atrInPips > 15.0)
         result.atrScore = 1.0;
      else
         result.atrScore = 0.5;

      result.finalScore = result.emaScore + result.rsiScore + result.adxScore + result.atrScore;
      result.verdict = (result.finalScore >= InpMinSellScore) ? "STRONG_SELL" : "WEAK_SELL";
   }

   // BUG #3 FIX: Only cache the requested signal type
   // Do NOT copy BUY result into SELL cache or vice versa
   g_lastSignalTick = TimeCurrent();
   if(orderType == ORDER_TYPE_BUY)
      g_cachedBuySignal = result;
   else
      g_cachedSellSignal = result;

   return result;
}

//+------------------------------------------------------------------+
//| COMPUTE RAW SCORE                                                |
//+------------------------------------------------------------------+
double ComputeRawScore(ENUM_ORDER_TYPE orderType)
{
   SignalStrength ss = GetSignalStrength(orderType);
   return ss.finalScore;
}

//+------------------------------------------------------------------+
//| NORMALIZE VOLUME                                                 |
//+------------------------------------------------------------------+
double NormalizeVolume(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots / lotStep) * lotStep;

   return NormalizeDouble(lots, (int)MathLog10(1.0 / lotStep));
}

//+------------------------------------------------------------------+
//| IS TRADE ALLOWED                                                 |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL) return false;
   return true;
}

//+------------------------------------------------------------------+
//| LOG MESSAGE                                                      |
//+------------------------------------------------------------------+
void LogMessage(int level, string msg)
{
   if(!InpEnableLogging) return;
   if(level > InpLogLevel) return;

   string prefix = (level == 1) ? "[ERR]" : (level == 2) ? "[INF]" : "[DBG]";
   Print(prefix, " ", msg);
}

//+------------------------------------------------------------------+
//| POSITION SELECT BY TICKET (native MQL5)                          |
//+------------------------------------------------------------------+
// Note: PositionSelectByTicket is a built-in MQL5 function.
// Do NOT define it here to avoid ambiguous overload errors.

//+------------------------------------------------------------------+
//| NYAO: CHECK HIGH IMPACT NEWS                                     |
//+------------------------------------------------------------------+
void CheckHighImpactNews()
{
   if(!InpEnableNewsFilter)
   {
      g_isNewsTime = false;
      return;
   }

   // Throttle: check max once per minute
   datetime now = TimeTradeServer();
   if(now - g_lastNewsCheck < 60) return;
   g_lastNewsCheck = now;

   g_isNewsTime = false;

   // Get relevant currencies for the symbol
   string quoteCurr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT); // "USD" for XAUUSD

   MqlCalendarValue values[];
   datetime from = now - (InpNewsMinutesBefore + 5) * 60;
   datetime to = now + (InpNewsMinutesAfter + 5) * 60;

   if(CalendarValueHistory(values, from, to, NULL, NULL) <= 0) return;

   for(int i = 0; i < ArraySize(values); i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;
      if(event.importance != CALENDAR_IMPORTANCE_HIGH) continue;

      // Filter by relevant currency (USD for XAUUSD)
      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country)) continue;

      bool relevant = (country.currency == quoteCurr);
      if(!relevant) continue;

      datetime eventTime = values[i].time;
      int diffSeconds = (int)MathAbs((double)(now - eventTime));
      int windowSeconds = (eventTime > now)
                           ? InpNewsMinutesBefore * 60
                           : InpNewsMinutesAfter * 60;

      if(diffSeconds <= windowSeconds)
      {
         g_isNewsTime = true;
         LogMessage(2, StringFormat("[NEWS FILTER] %s | %s | %s | %d min %s",
                     country.currency, event.name,
                     TimeToString(eventTime),
                     diffSeconds / 60,
                     (eventTime > now) ? "until" : "ago"));
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| NYAO: CHECK PARTIAL CLOSE                                        |
//+------------------------------------------------------------------+
void CheckPartialClose()
{
   if(!InpEnablePartialClose) return;
   if(g_basketActive) return; // Don't interfere with active hedge

   // Process BUY side
   if(g_buy.hasPosition && !g_buy.isHedge && g_buy.ticket > 0 &&
      g_buy.initialScore > 0 && g_buy.partialCloseLevel < 3)
   {
      CheckPartialCloseSide(g_buy, ORDER_TYPE_BUY, POSITION_TYPE_BUY);
   }

   // Process SELL side
   if(g_sell.hasPosition && !g_sell.isHedge && g_sell.ticket > 0 &&
      g_sell.initialScore > 0 && g_sell.partialCloseLevel < 3)
   {
      CheckPartialCloseSide(g_sell, ORDER_TYPE_SELL, POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| NYAO: CHECK PARTIAL CLOSE SIDE                                   |
//+------------------------------------------------------------------+
void CheckPartialCloseSide(ScalperSide &side, ENUM_ORDER_TYPE orderType, ENUM_POSITION_TYPE posType)
{
   if(!PositionSelectByTicket(side.ticket))
   {
      side.ticket = 0;
      return;
   }

   double currentVol = PositionGetDouble(POSITION_VOLUME);
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double currentSL = PositionGetDouble(POSITION_SL);

   // FLOOR: Don't close if profit lock has positive SL
   bool hasPositiveSL = (posType == POSITION_TYPE_BUY && currentSL > side.openPrice && currentSL > 0) ||
                        (posType == POSITION_TYPE_SELL && currentSL < side.openPrice && currentSL > 0);

   SignalStrength st = GetSignalStrength(orderType);
   double ratio = (side.initialScore > 0) ? st.finalScore / side.initialScore : 1.0;

   // Level 1: Signal dropped to 75% -> close 25%
   if(side.partialCloseLevel == 0 && ratio <= InpPartialCloseL1Signal)
   {
      double closeVol = NormalizeDouble(currentVol * 0.25, (int)MathLog10(1.0 / minVol));
      closeVol = MathMax(closeVol, minVol);
      double remaining = currentVol - closeVol;

      if(remaining >= minVol && closeVol >= minVol)
      {
         Trade.PositionClosePartial(side.ticket, closeVol);
         side.partialCloseLevel = 1;
         LogMessage(2, StringFormat("[PARTIAL L1 %s] Ticket %d | Closed %.3f lots (25%%) | Signal %.1f/%.1f (ratio=%.2f)",
                     (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), side.ticket,
                     closeVol, st.finalScore, side.initialScore, ratio));
      }
   }
   // Level 2: Signal dropped to 50% -> close 50% of remaining
   else if(side.partialCloseLevel == 1 && ratio <= InpPartialCloseL2Signal)
   {
      if(!PositionSelectByTicket(side.ticket)) return;
      currentVol = PositionGetDouble(POSITION_VOLUME);
      double closeVol = NormalizeDouble(currentVol * 0.50, (int)MathLog10(1.0 / minVol));
      closeVol = MathMax(closeVol, minVol);
      double remaining = currentVol - closeVol;

      if(remaining >= minVol && closeVol >= minVol)
      {
         Trade.PositionClosePartial(side.ticket, closeVol);
         side.partialCloseLevel = 2;
         LogMessage(2, StringFormat("[PARTIAL L2 %s] Ticket %d | Closed %.3f lots (50%% of remaining) | Signal %.1f/%.1f (ratio=%.2f)",
                     (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), side.ticket,
                     closeVol, st.finalScore, side.initialScore, ratio));
      }
   }
   // Level 3: Signal dropped to 25% -> close all remaining
   else if(side.partialCloseLevel == 2 && ratio <= InpPartialCloseL3Signal)
   {
      // Respect profit lock: if SL is already positive, don't close
      if(hasPositiveSL)
      {
         LogMessage(2, StringFormat("[PARTIAL L3 BLOCKED %s] Ticket %d | Profit lock active (SL=%.2f vs Open=%.2f) | Let trailing manage exit",
                     (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), side.ticket, currentSL, side.openPrice));
         side.partialCloseLevel = 3; // Mark as resolved
         return;
      }

      ClosePosition(side.ticket, "PARTIAL_L3_SIGNAL_DECAY");
      side.partialCloseLevel = 3;
      LogMessage(2, StringFormat("[PARTIAL L3 %s] Ticket %d | Full close | Signal %.1f/%.1f (ratio=%.2f)",
                  (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), side.ticket,
                  st.finalScore, side.initialScore, ratio));
   }
}
//+------------------------------------------------------------------+
