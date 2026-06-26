//+---------------------------------------------------------------------+
//| EN HONOR A ABBA QUE HA DADO LA SABIDURIA POR SU AMADO ESPIRITU SANTO|
//| EN EL NOMBRE DE JESUS.                                               |
//|                                                                      |
//|           Bot_Claude_V1.mq5                                          |
//|  SCALPER XAUUSD M5 - Shepherd Engine (Basket TP Fixed Lot)           |
//|  Pastor-Recuperador: Nunca cerrar en negativo.                        |
//|                                                                      |
//|  v4.4 OPTIMIZACIONES CUANTITATIVAS:                                  |
//|  OPT 1: Panel responsive y adaptativo a resolucion de pantalla      |
//|  OPT 2: Panel ultra-ligero (update cada N segundos configurable)    |
//|  OPT 3: SL inteligente basado en ATR (proteccion real contra gaps)  |
//|  OPT 4: Score minimo 6.5 (filtro anti-chop cuantitativo)             |
//|  OPT 5: Filtro de momentum + volatilidad (no estructural pesado)  |
//|  OPT 6: FIX 2 original preservado (Smart Exit A matematicamente OK)|
//|  OPT 7: Quick Capture dinamico (respeta Lock2Trigger input)         |
//|  OPT 8: Mosquito BE siempre cuando uC=true (FIX 1 preservado)       |
//+---------------------------------------------------------------------+
#property copyright "Bot_Claude_V1 - Shepherd Gold v4.4 Optimized"
#property version   "4.401"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade        Trade;
CPositionInfo PosInfo;
CSymbolInfo   SymInfo;

enum ENUM_TRAILING_MODE { TRAILING_RETRACEMENT = 0, TRAILING_ATR = 1 };
enum ENUM_LOG_LEVEL     { LOG_ERROR = 0, LOG_WARN = 1, LOG_INFO = 2, LOG_TRADE = 3 };

input group "====== MOTOR NYAO (SEÑALES RAPIDAS) ======"
input int    InpFastEMA               = 5;
input int    InpSlowEMA               = 12;
input int    InpRSIPeriod             = 8;
input int    InpATRPeriod             = 8;
input int    InpATRAvgLookback        = 10;
input int    InpSlopeLookback         = 3;
input int    InpImpulseLookback       = 3;
input double InpImpulseBoostWeight    = 1.0;
input int    InpSignalSmoothingCandles= 1;
input double InpCurrentCandleBlend    = 1.0;
input double InpVelocityWindow        = 2.0;
input int    InpRSIOverbought         = 80;
input int    InpRSIOversold           = 20;
input int    InpRSIMomentumBuy        = 60;
input int    InpRSIMomentumSell       = 40;
input double InpMinVolRatioToTrade    = 0.6;
input double InpMinBuyScore           = 6.5;
input double InpMinSellScore          = 6.5;

input group "====== PESOS DE SCORE ======"
input double InpTrendWeight           = 1.5;
input double InpSlopeWeight           = 1.5;
input double InpMomentumBaseWeight    = 1.0;
input double InpMomentumTriggerWeight = 0.5;
input double InpBodyMomentumWeight    = 1.5;
input double InpChopScoreHigh         = 2.0;
input double InpChopScoreMed          = 1.0;
input double InpChopScoreLow          = 0.0;
input double InpVolatilityScoreHigh   = 1.0;
input double InpVolatilityScoreLow    = 0.0;
input double InpPeakScoreWeight       = 1.0;
input double InpWickRejectionWeight   = 1.0;
input double InpMinBodyRatio          = 1.5;

input group "====== DAMPENING (PERMISIVO) ======"
input bool   InpEnableSignalDampening         = false;
input int    InpMaxLosingPositionsSameDir      = 5;
input double InpLosingPosScorePenalty          = 0.5;
input double InpDrawdownThresholdPct           = 10.0;
input double InpDrawdownScoreBoost             = 1.0;
input int    InpConsecutiveLossesBeforeCooldown= 5;
input int    InpConsecutiveLossCooldownBars    = 3;
input int    InpMaxConsecutiveCandleBoosts     = 3;
input double InpConsecutiveCandleThresholdBoost= 0.5;
input double InpZonePoints                     = 200;
input double InpDuplicateMultiplier            = 1.0;

input group "====== LOTAJE ======"
input double InpLotSize           = 0.01;
input double InpMaxLotPerPosition = 0.05;

input group "====== SL / TP INTELIGENTE (OPT 3) ======"
input double InpTPPips = 0;
input double InpSLPips = 0;
input double InpSL_ATR_Multiplier = 1.5;
input double InpTP_SL_Ratio = 1.5;

input group "====== TRAILING STOP ======"
input ENUM_TRAILING_MODE InpTrailingMode        = TRAILING_ATR;
input double InpTrailActivatePips               = 5.0;
input double InpTrailRetracementPct             = 25.0;
input int    InpTrailATRPeriod                  = 10;
input double InpTrailATRMultiplier              = 0.40;
input double InpTrailATRMinProfitPct            = 10.0;
input double InpTrailMinProfitUsd               = 1.50;

input group "====== PROFIT LOCK (Escalones de Seguridad) ======"
input double InpLock1Trigger = 3.0;
input double InpLock1Secure  = 0.50;
input double InpLock2Trigger = 5.0;
input double InpLock2Secure  = 2.00;
input double InpLock3Trigger = 8.0;
input double InpLock3Secure  = 4.00;

input group "====== BASKET RECOVERY (Hedge sin Martingala) ======"
input bool   InpEnableBasketHedge = true;
input double InpHedgeTriggerUSD   = 2.0;
input int    InpHedgeGridStepPips = 20;
input int    InpMaxHedgeLevels    = 4;
input double InpBasketTargetUSD   = 1.0;

input group "====== BASKET TRAILING / LOCK / TIME ======"
input double InpBasketTrailActivate    = 3.0;
input double InpBasketTrailRetracement = 40.0;
input double InpBasketLockTrigger      = 5.0;
input double InpBasketLockSecure       = 2.0;
input int    InpBasketMaxMinutes       = 60;

input group "====== CONTROL DE SALUD ======"
input bool   InpUseHealthExit          = true;
input double InpMinHealthScore         = 0.30;
input int    InpHealthGraceBars        = 5;
input double InpHealthTrendWeight      = 0.40;
input double InpHealthRSIWeight        = 0.25;
input double InpHealthATRWeight        = 0.25;
input double InpHealthSwingWeight      = 0.10;
input double InpHealthRSIBuyMin        = 40.0;
input double InpHealthRSISellMax       = 60.0;
input int    InpHealthSwingLookback    = 20;
input double InpMaxAdverseATR          = 1.5;
input bool   InpCriticalHealthCutLoss  = false;
input double InpCriticalHealthThreshold= 0.15;

input group "====== TIME STOP ======"
input int InpMaxTradeMinutes = 30;

input group "====== BLOQUEO ANTI-LOOP ======"
input bool InpUseSignalLock     = true;
input int  InpPostCloseCooldown = 15;

input group "====== FILTRO DE SESION ======"
input bool InpUseSessionFilter  = false;
input int  InpSessionStartHour  = 12;
input int  InpSessionEndHour    = 19;

input group "====== SINCRONIZACION HORARIA ======"
input bool InpUseLocalTimeSync      = false;
input int  InpManualTimeOffsetHours = 0;
input bool InpUseNoTradeWindow      = false;
input int  InpNoTradeStartHour      = 22;
input int  InpNoTradeEndHour        = 2;

input group "====== LIMITES DIARIOS ======"
input int    InpMaxTradesPerDay = 0;
input double InpDailyTarget     = 0;
input double InpDailyFloor      = 0;

input group "====== EMERGENCY BRAKE ======"
input double InpEmergencyEquityDropPct = 15.0;

input group "====== LOGGING Y AUDITORIA ======"
input bool           InpEnableLogging = true;
input ENUM_LOG_LEVEL InpLogLevel      = LOG_WARN;

input group "====== PANEL RESPONSIVE (OPT 1-2) ======"
input int    InpPanelScalePercent     = 100;
input int    InpPanelUpdateSeconds    = 3;
input bool   InpPanelCornerRight      = false;

input group "====== MAGIC / IDENTIFICACION ======"
input int InpMagicBuy      = 301;
input int InpMagicSell     = 302;
input int InpMagicHedgeBuy = 303;
input int InpMagicHedgeSell= 304;

//---------------------------------------------------------------
struct ScalperSide
{
   bool     enabled;
   ulong    magic;
   double   openPrice;
   datetime openTime;
   ulong    ticket;
   bool     hasPosition;
   double   peakProfit;
   bool     trailingActive;
   double   initialScore;
   bool     breakEvenLocked;
   double   originalSL;
   double   currentVolume;
   bool     isHedge;
   int      hedgeLevel;
};

struct SignalStrength
{
   double scoreVal, finalScore, trendScore, momentumScore, chopScore;
   double peakScore, volatilityScore, impulseStrength;
   double velocity, normalizedVelocity;
   double avgBody, bodySignal, upperWick, lowerWick;
   double rejection, penaltyWick;
   string reasoning;
};

//---------------------------------------------------------------
ScalperSide   g_buy;
ScalperSide   g_sell;
int      g_handleFast     = INVALID_HANDLE;
int      g_handleSlow     = INVALID_HANDLE;
int      g_handleRSI      = INVALID_HANDLE;
int      g_handleATR      = INVALID_HANDLE;
int      g_handleTrailATR = INVALID_HANDLE;

datetime g_lastBarTime        = 0;
datetime g_dayStart           = 0;
double   g_initialBalance     = 0;
int      g_tradesToday        = 0;
double   g_dailyProfit        = 0;
bool     g_dailyTargetHit     = false;
bool     g_dailyFloorHit      = false;
bool     g_panelCreated       = false;
bool     g_orderOpenedThisTick= false;
datetime g_lastCloseTime      = 0;
datetime g_lastSignalBarTime  = 0;
double   g_lastBuyScore       = 0;
double   g_lastBuyScorePrev   = 0;
double   g_lastSellScore      = 0;
double   g_lastSellScorePrev  = 0;
int      g_consecutiveLossCount   = 0;
datetime g_cooldownUntilBarTime   = 0;
int      g_consecutiveBuyCandles  = 0;
int      g_consecutiveSellCandles = 0;
bool     g_buyScoreValid      = false;
bool     g_sellScoreValid     = false;
SignalStrength g_cachedBuyScore;
SignalStrength g_cachedSellScore;
int      g_logHandle          = INVALID_HANDLE;
string   g_logFileName;
datetime g_lastLogDay         = 0;
bool     g_emergencyStop      = false;
datetime g_lastPanelUpdate    = 0;
bool     g_basketActive       = false;

double   g_peakEquity       = 0;
int      g_basketBuyCount   = 0;
int      g_basketSellCount  = 0;
double   g_basketBuyVolume  = 0;
double   g_basketSellVolume = 0;
double   g_basketTotalPnL   = 0;

string g_pBuyScore="",g_pSellScore="",g_pBuyVel="",g_pSellVel="";
string g_pStatus="",g_pPos="",g_pProfit="",g_pHealth="";
string g_pTrail="",g_pTime="",g_pFloat="",g_pDaily="";
string g_pTrades="",g_pLoss="",g_pCool="",g_pSpread="";
string g_pHedge="",g_pBasket="";
double g_pHealthVal=-1, g_pProfitVal=999999;
int    g_pMins=-1;
double g_pDailyPct=0;
int    g_pSpreadPts=-1;
double g_pBuyBarPct=0, g_pSellBarPct=0;

double g_basketPeakProfit  = 0;
double g_basketLockLevel   = 0;
bool   g_basketTrailActive = false;

int      g_panelW=295, g_panelH=400;
int      g_scale=100;
int      g_panelX=10, g_panelY=30;
int      g_padL=0, g_padR=0, g_colV=0;
int      g_S=16, g_SB=13, g_rowH=18, g_secH=20;
string   PanelObjects[120];
int      PanelObjectCount = 0;

//---------------------------------------------------------------
#define CLR_BG       C'18,18,24'
#define CLR_BORDER   C'45,45,60'
#define CLR_GOLD     C'255,215,0'
#define CLR_GOLD_DIM C'180,150,0'
#define CLR_GREEN    C'0,230,118'
#define CLR_RED      C'255,82,82'
#define CLR_BLUE     C'66,165,245'
#define CLR_ORANGE   C'255,171,64'
#define CLR_WHITE    C'240,240,240'
#define CLR_GRAY     C'150,150,160'
#define CLR_BUY      C'0,200,150'
#define CLR_SELL     C'255,100,100'
#define CLR_NEUTRAL  C'120,120,130'
#define CLR_HEDGE    C'255,140,0'
#define CLR_BAR_BG   C'30,30,42'

//+------------------------------------------------------------------+
void InitLogging()
{
   if(!InpEnableLogging) return;
   MqlDateTime mdt;
   TimeToStruct(TimeLocal(), mdt);
   g_logFileName = StringFormat("SGS_v4_401_%04d%02d%02d_%02d%02d%02d.txt",
      mdt.year,mdt.mon,mdt.day,mdt.hour,mdt.min,mdt.sec);
   g_logHandle = FileOpen(g_logFileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(g_logHandle != INVALID_HANDLE)
   {
      FileWriteString(g_logHandle,"=== Bot Claude V1 - Shepherd Gold v4.401 ===\n");
      FileFlush(g_logHandle);
   }
}

void LogMessage(int level, string msg)
{
   if(!InpEnableLogging || g_logHandle == INVALID_HANDLE) return;
   if(level > (int)InpLogLevel) return;
   string pfx = TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS) + " ";
   switch(level)
   {
      case 0: pfx+="[ERROR] "; break;
      case 1: pfx+="[WARN]  "; break;
      case 2: pfx+="[INFO]  "; break;
      case 3: pfx+="[TRADE] "; break;
   }
   FileWriteString(g_logHandle, pfx+msg+"\n");
   FileFlush(g_logHandle);
}

void CloseLogging()
{
   if(g_logHandle != INVALID_HANDLE)
   {
      FileWriteString(g_logHandle,"=== Log Closed ===\n");
      FileClose(g_logHandle);
      g_logHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
bool   ConnectionOK() { return (bool)TerminalInfoInteger(TERMINAL_CONNECTED); }
double GetPointSize() { return SymbolInfoDouble(_Symbol,SYMBOL_POINT); }

double GetPipSize()
{
   if(StringFind(_Symbol,"XAU")>=0 || StringFind(_Symbol,"GOLD")>=0)
      return 10.0*GetPointSize();
   int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(d==3||d==5) return 0.001;
   if(d==2)       return 0.01;
   if(d==1)       return 0.1;
   return GetPointSize();
}

double PipsToPrice(double p) { return p*GetPipSize(); }
double PriceToPips(double p) { return p/GetPipSize(); }

double NormalizeVolume(double vol)
{
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(st<=0) st=0.01;
   vol=MathMax(vol,mn);
   vol=MathMin(vol,mx);
   vol=MathFloor(vol/st)*st;
   return vol;
}

bool IsNewDay()
{
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(),mdt);
   datetime today=StringToTime(StringFormat("%04d.%02d.%02d 00:00",mdt.year,mdt.mon,mdt.day));
   if(today!=g_dayStart)
   {
      g_dayStart=today;
      g_initialBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      return true;
   }
   return false;
}

double GetCurrentATR()
{
   double buf[];
   ArraySetAsSeries(buf,true);
   if(CopyBuffer(g_handleATR,0,1,1,buf)<1) return 0;
   return buf[0];
}

bool SpreadOK()
{
   int sp=(int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   int mx=80;
   if(StringFind(_Symbol,"XAU")<0 && StringFind(_Symbol,"GOLD")<0)
   {
      double a=GetCurrentATR();
      mx=(a>0)?(int)(a*0.30/GetPointSize()):50;
   }
   return sp<=mx;
}

bool IsSLValid(ENUM_POSITION_TYPE pt, double sl)
{
   if(sl<=0) return false;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double minD=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*GetPointSize();
   if(pt==POSITION_TYPE_BUY  && sl>=bid-minD) return false;
   if(pt==POSITION_TYPE_SELL && sl<=ask+minD) return false;
   return true;
}

int GetEffectiveHour()
{
   datetime t=InpUseLocalTimeSync?TimeLocal():TimeCurrent();
   if(!InpUseLocalTimeSync && InpManualTimeOffsetHours!=0) t+=InpManualTimeOffsetHours*3600;
   MqlDateTime mdt; TimeToStruct(t,mdt);
   return mdt.hour;
}

string GetEffectiveTimeStr()
{
   datetime t=InpUseLocalTimeSync?TimeLocal():TimeCurrent();
   if(!InpUseLocalTimeSync && InpManualTimeOffsetHours!=0) t+=InpManualTimeOffsetHours*3600;
   MqlDateTime mdt; TimeToStruct(t,mdt);
   return StringFormat("%02d:%02d",mdt.hour,mdt.min);
}

bool IsSessionActive()
{
   if(!InpUseSessionFilter) return true;
   int h=GetEffectiveHour();
   if(InpSessionStartHour<InpSessionEndHour)
      return (h>=InpSessionStartHour && h<InpSessionEndHour);
   return (h>=InpSessionStartHour || h<InpSessionEndHour);
}

bool IsNoTradeWindow()
{
   if(!InpUseNoTradeWindow) return false;
   int h=GetEffectiveHour();
   if(InpNoTradeStartHour<InpNoTradeEndHour)
      return (h>=InpNoTradeStartHour && h<InpNoTradeEndHour);
   return (h>=InpNoTradeStartHour || h<InpNoTradeEndHour);
}

//+------------------------------------------------------------------+
void CheckEmergencyBrake()
{
   if(InpEmergencyEquityDropPct<=0) return;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal<=0) return;
   double drop=((bal-eq)/bal)*100.0;
   if(drop>=InpEmergencyEquityDropPct && !g_emergencyStop)
   {
      g_emergencyStop=true;
      LogMessage(0,"EMERGENCY BRAKE! Drop:"+DoubleToString(drop,1)+"%");
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tkt=PositionGetTicket(i);
         if(tkt==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         Trade.PositionClose(tkt);
      }
   }
   if(drop<InpEmergencyEquityDropPct*0.5) g_emergencyStop=false;
}

//+------------------------------------------------------------------+
double ComputeRawScore(ENUM_ORDER_TYPE dir, int idx, SignalStrength &comp, bool fill)
{
   bool isBuy=(dir==ORDER_TYPE_BUY);
   double fEMA[],sEMA[],rsi[],atr[];
   ArraySetAsSeries(fEMA,true); ArraySetAsSeries(sEMA,true);
   ArraySetAsSeries(rsi,true);  ArraySetAsSeries(atr,true);

   int sb    =MathMax(1,InpSlopeLookback);
   int efCopy=MathMax(3,sb+1);
   int need  =MathMax(InpImpulseLookback,MathMax(10,InpATRAvgLookback))+5;

   if(CopyBuffer(g_handleFast,0,idx,efCopy,fEMA)<efCopy) return 0;
   if(CopyBuffer(g_handleSlow,0,idx,3,sEMA)     <3)      return 0;
   if(CopyBuffer(g_handleRSI, 0,idx,3,rsi)      <3)      return 0;
   if(CopyBuffer(g_handleATR, 0,idx,need,atr)   <need)   return 0;

   MqlRates rates[]; ArraySetAsSeries(rates,true);
   if(CopyRates(_Symbol,PERIOD_CURRENT,idx,need,rates)<need) return 0;

   double emaF=fEMA[0], emaS=sEMA[0], emaFP=fEMA[sb];
   double trendScore=0;
   if(isBuy?(emaF>emaS):(emaF<emaS))   trendScore+=InpTrendWeight;
   if(isBuy?(emaF>emaFP):(emaF<emaFP)) trendScore+=InpSlopeWeight;
   if(trendScore>3.0) trendScore=3.0;

   double curBody=MathAbs(rates[0].close-rates[0].open);
   double sumBody=0; int vc=0;
   for(int i=1;i<=6&&i<need;i++){sumBody+=MathAbs(rates[i].close-rates[i].open);vc++;}
   double avgBody=(vc>0)?sumBody/vc:curBody;

   double r=rsi[0], baseM=0;
   if(isBuy){
      if(r>50&&r<InpRSIOverbought) baseM+=InpMomentumBaseWeight;
      if(r>InpRSIMomentumBuy)      baseM+=InpMomentumTriggerWeight;
      if(curBody>avgBody)          baseM+=InpBodyMomentumWeight;
   } else {
      if(r<50&&r>InpRSIOversold)   baseM+=InpMomentumBaseWeight;
      if(r<InpRSIMomentumSell)     baseM+=InpMomentumTriggerWeight;
      if(curBody>avgBody)          baseM+=InpBodyMomentumWeight;
   }

   double bAcc=(avgBody>0)?MathMin(3.0,curBody/avgBody):0;
   double curRng=rates[0].high-rates[0].low, sumRng=0;
   for(int i=1;i<=6&&i<need;i++) sumRng+=(rates[i].high-rates[i].low);
   double avgRng=(vc>0)?sumRng/vc:curRng;
   double rAcc=(avgRng>0)?MathMin(3.0,curRng/avgRng):0;

   int sdc=0;
   for(int i=0;i<InpImpulseLookback&&i<need;i++){
      bool bull=(rates[i].close>rates[i].open);
      bool bear=(rates[i].close<rates[i].open);
      if(isBuy&&bull) sdc++; else if(!isBuy&&bear) sdc++; else break;
   }
   double cont=MathMin(1.0,(double)sdc/InpImpulseLookback);
   double imp =MathMax(0.0,MathMin(1.0,(0.5*bAcc+0.3*rAcc+0.2*cont)/2.0));
   double momScore=MathMin(3.0,baseM*(1.0+InpImpulseBoostWeight*imp));

   double curATR=atr[0], avgATR=0;
   if(need>=InpATRAvgLookback){
      double sa=0; for(int i=0;i<InpATRAvgLookback&&i<need;i++) sa+=atr[i];
      avgATR=sa/InpATRAvgLookback;
   } else avgATR=curATR;

   double vr=(avgATR>0)?curATR/avgATR:0;
   if(InpMinVolRatioToTrade>0&&vr>0&&vr<InpMinVolRatioToTrade) return 0;

   double chopScore=(vr>1.0)?InpChopScoreHigh:(vr>0.8)?InpChopScoreMed:InpChopScoreLow;
   if(chopScore>2.0) chopScore=2.0;
   double volScore=(vr>1.2)?InpVolatilityScoreHigh:InpVolatilityScoreLow;

   double loc=isBuy?rates[1].high:rates[1].low;
   for(int i=2;i<=5&&i<need;i++)
      loc=isBuy?MathMax(loc,rates[i].high):MathMin(loc,rates[i].low);
   double peakScore=0;
   if(isBuy&&rates[0].close>loc) peakScore=InpPeakScoreWeight;
   if(!isBuy&&rates[0].close<loc) peakScore=InpPeakScoreWeight;

   double mxOC=MathMax(rates[0].open,rates[0].close);
   double mnOC=MathMin(rates[0].open,rates[0].close);
   double uW=rates[0].high-mxOC, lW=mnOC-rates[0].low;
   double sB=MathMax(curBody,avgBody*InpMinBodyRatio);
   double rej=0, penW=0;
   if(sB>0){ rej=isBuy?(uW/sB):(lW/sB); penW=rej*InpWickRejectionWeight; }

   double raw=trendScore+momScore+chopScore+peakScore+volScore-penW;
   raw=MathMax(0.0,MathMin(10.0,raw));

   if(fill){
      comp.trendScore=trendScore; comp.momentumScore=momScore;
      comp.chopScore=chopScore;   comp.peakScore=peakScore;
      comp.volatilityScore=volScore; comp.impulseStrength=imp;
      comp.avgBody=avgBody; comp.bodySignal=curBody;
      comp.upperWick=uW; comp.lowerWick=lW;
      comp.rejection=rej; comp.penaltyWick=penW;
   }
   return raw;
}

SignalStrength GetSignalStrength(ENUM_ORDER_TYPE dir)
{
   if(dir==ORDER_TYPE_BUY  && g_buyScoreValid)  return g_cachedBuyScore;
   if(dir==ORDER_TYPE_SELL && g_sellScoreValid) return g_cachedSellScore;

   SignalStrength st; ZeroMemory(st); st.reasoning="";
   bool isBuy=(dir==ORDER_TYPE_BUY);

   int    N    =MathMax(1,MathMin(10,InpSignalSmoothingCandles));
   double blend=MathMax(0.0,MathMin(1.0,InpCurrentCandleBlend));
   double ws=0,wt=0;
   for(int i=1;i<=N;i++){
      double sc=(i==1)?ComputeRawScore(dir,i,st,true):ComputeRawScore(dir,i,st,false);
      double w=(double)(N-i+1); ws+=sc*w; wt+=w;
   }
   double base=(wt>0)?ws/wt:0;
   double cur =ComputeRawScore(dir,0,st,false);

   double scoreVal=MathMax(0.0,MathMin(10.0,base*(1.0-blend)+cur*blend));

   st.scoreVal=scoreVal;
   st.finalScore=scoreVal;
   double prev=isBuy?g_lastBuyScorePrev:g_lastSellScorePrev;
   st.velocity=scoreVal-prev;
   st.normalizedVelocity=MathMax(0.0,MathMin(1.0,
      (st.velocity+InpVelocityWindow)/(2.0*InpVelocityWindow)));
   st.reasoning=StringFormat("T:%.1f M:%.1f C:%.1f P:%.1f V:%.1f Vel:%.2f",
      st.trendScore,st.momentumScore,st.chopScore,st.peakScore,
      st.volatilityScore,st.normalizedVelocity);

   if(dir==ORDER_TYPE_BUY){g_cachedBuyScore=st;g_buyScoreValid=true;}
   else {g_cachedSellScore=st;g_sellScoreValid=true;}
   return st;
}

//+------------------------------------------------------------------+
int CountLosingPositions(ENUM_POSITION_TYPE dir)
{
   int cnt=0;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tkt=PositionGetTicket(i); if(tkt==0) continue;
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      ulong mag=PositionGetInteger(POSITION_MAGIC);
      if((dir==POSITION_TYPE_BUY&&mag!=g_buy.magic)||
         (dir==POSITION_TYPE_SELL&&mag!=g_sell.magic)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=dir) continue;
      double p=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(p<0) cnt++;
   }
   return cnt;
}

bool GetLastPositionInfo(ENUM_POSITION_TYPE dir,double &lp,datetime &lt)
{
   lp=0; lt=0;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tkt=PositionGetTicket(i); if(tkt==0) continue;
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      ulong mag=PositionGetInteger(POSITION_MAGIC);
      if((dir==POSITION_TYPE_BUY&&mag!=g_buy.magic)||
         (dir==POSITION_TYPE_SELL&&mag!=g_sell.magic)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=dir) continue;
      datetime pt=(datetime)PositionGetInteger(POSITION_TIME);
      if(pt>lt){lt=pt;lp=PositionGetDouble(POSITION_PRICE_OPEN);}
   }
   return (lt>0);
}

double ApplyDampening(double raw,ENUM_POSITION_TYPE dir,double &thr)
{
   double adj=raw;
   thr=(dir==POSITION_TYPE_BUY)?InpMinBuyScore:InpMinSellScore;
   int boostCnt=(dir==POSITION_TYPE_BUY)?g_consecutiveBuyCandles:g_consecutiveSellCandles;
   if(boostCnt>0&&InpConsecutiveCandleThresholdBoost>0){
      int bc=boostCnt;
      if(InpMaxConsecutiveCandleBoosts>0&&bc>InpMaxConsecutiveCandleBoosts) bc=InpMaxConsecutiveCandleBoosts;
      thr+=bc*InpConsecutiveCandleThresholdBoost;
   }
   if(InpEnableSignalDampening){
      int lc=CountLosingPositions(dir);
      if(lc>0) adj-=lc*InpLosingPosScorePenalty;
      if(g_peakEquity>0){
         double dd=((g_peakEquity-AccountInfoDouble(ACCOUNT_EQUITY))/g_peakEquity)*100.0;
         if(dd>=InpDrawdownThresholdPct) thr+=InpDrawdownScoreBoost;
      }
   }
   return adj;
}

bool CheckEntryConditions(ENUM_POSITION_TYPE dir,double price)
{
   if(InpEnableSignalDampening&&g_cooldownUntilBarTime>0){
      datetime cb=iTime(_Symbol,PERIOD_CURRENT,0);
      if(cb<g_cooldownUntilBarTime) return false;
      else g_cooldownUntilBarTime=0;
   }
   if(InpEnableSignalDampening&&CountLosingPositions(dir)>=InpMaxLosingPositionsSameDir)
      return false;
   double lp; datetime lt;
   if(GetLastPositionInfo(dir,lp,lt)){
      if(MathAbs(price-lp)<InpZonePoints*GetPointSize()*InpDuplicateMultiplier)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool IsMomentumVolatilityFilter(ENUM_ORDER_TYPE dir)
{
   double fEMA[]; ArraySetAsSeries(fEMA, true);
   if(CopyBuffer(g_handleFast, 0, 0, 5, fEMA) < 5) return true;

   double atr = GetCurrentATR();
   double minATR = 3.0 * GetPipSize();
   bool isBuy = (dir == ORDER_TYPE_BUY);

   int emaSlope = 0;
   for(int i=0; i<4; i++){
      if(isBuy  && fEMA[i] > fEMA[i+1]) emaSlope++;
      if(!isBuy && fEMA[i] < fEMA[i+1]) emaSlope++;
   }
   bool emaOK = (emaSlope >= 3);
   bool atrOK = (atr >= minATR);

   SignalStrength st = GetSignalStrength(dir);
   bool velocityOK = (st.normalizedVelocity > 0.3);

   return (emaOK && atrOK && velocityOK);
}

//+------------------------------------------------------------------+
double EvaluatePositionHealth(ENUM_POSITION_TYPE pt,double ep,datetime ot)
{
   if(iBarShift(_Symbol,PERIOD_CURRENT,ot,false)<InpHealthGraceBars) return 1.0;
   double fE[],sE[],ri[],at[];
   ArraySetAsSeries(fE,true);ArraySetAsSeries(sE,true);
   ArraySetAsSeries(ri,true);ArraySetAsSeries(at,true);
   if(CopyBuffer(g_handleFast,0,0,3,fE)<3) return 1.0;
   if(CopyBuffer(g_handleSlow,0,0,3,sE)<3) return 1.0;
   if(CopyBuffer(g_handleRSI, 0,0,3,ri)<3) return 1.0;
   if(CopyBuffer(g_handleATR, 0,0,3,at)<3) return 1.0;

   bool isBuy=(pt==POSITION_TYPE_BUY);
   double h=0;
   double ts=0;
   if(isBuy&&fE[1]>sE[1]) ts=1.0;
   if(!isBuy&&fE[1]<sE[1]) ts=1.0;
   if(ts>0){
      if(isBuy&&fE[1]<=fE[2]) ts=0.7;
      if(!isBuy&&fE[1]>=fE[2]) ts=0.7;
   }
   h+=ts*InpHealthTrendWeight;

   double rs=0,rv=ri[1];
   if(isBuy){
      double fl=InpHealthRSIBuyMin-15.0;
      if(rv>=InpHealthRSIBuyMin) rs=1.0;
      else if(rv>fl) rs=(rv-fl)/(InpHealthRSIBuyMin-fl);
   } else {
      double ce=InpHealthRSISellMax+15.0;
      if(rv<=InpHealthRSISellMax) rs=1.0;
      else if(rv<ce) rs=(ce-rv)/(ce-InpHealthRSISellMax);
   }
   h+=rs*InpHealthRSIWeight;

   double cp=isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double adv=isBuy?(ep-cp):(cp-ep);
   double as=1.0;
   if(at[1]>0&&adv>0) as=MathMax(0.0,1.0-(adv/at[1]/InpMaxAdverseATR));
   h+=as*InpHealthATRWeight;

   double sw=1.0;
   int sl=MathMax(5,InpHealthSwingLookback);
   MqlRates ra[]; ArraySetAsSeries(ra,true);
   int cp2=CopyRates(_Symbol,PERIOD_CURRENT,2,sl,ra);
   if(cp2>0){
      if(isBuy){
         double lo=ra[0].low; for(int j=1;j<cp2;j++) lo=MathMin(lo,ra[j].low);
         if(cp<lo) sw=0;
      } else {
         double hi=ra[0].high; for(int j=1;j<cp2;j++) hi=MathMax(hi,ra[j].high);
         if(cp>hi) sw=0;
      }
   }
   h+=sw*InpHealthSwingWeight;
   return h;
}

//+------------------------------------------------------------------+
void ScanPositions()
{
   g_buy.hasPosition=false;  g_buy.ticket=0;
   g_sell.hasPosition=false; g_sell.ticket=0;
   g_basketBuyCount=0;  g_basketSellCount=0;
   g_basketBuyVolume=0; g_basketSellVolume=0;
   g_basketTotalPnL=0;

   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tkt=PositionGetTicket(i); if(tkt==0) continue;
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      ulong mag=PositionGetInteger(POSITION_MAGIC);
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      double vol=PositionGetDouble(POSITION_VOLUME);
      bool ibm=(mag==g_buy.magic||mag==InpMagicHedgeBuy);
      bool ism=(mag==g_sell.magic||mag==InpMagicHedgeSell);
      if(!ibm&&!ism) continue;
      g_basketTotalPnL+=pnl;
      if(ibm&&type==POSITION_TYPE_BUY){
         g_basketBuyCount++; g_basketBuyVolume+=vol;
         if(!g_buy.hasPosition){
            g_buy.hasPosition=true; g_buy.ticket=tkt;
            g_buy.openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
            g_buy.openTime=(datetime)PositionGetInteger(POSITION_TIME);
            g_buy.currentVolume=vol;
            if(g_buy.originalSL==0) g_buy.originalSL=PositionGetDouble(POSITION_SL);
            g_buy.isHedge=(mag==InpMagicHedgeBuy);
         }
      } else if(ism&&type==POSITION_TYPE_SELL){
         g_basketSellCount++; g_basketSellVolume+=vol;
         if(!g_sell.hasPosition){
            g_sell.hasPosition=true; g_sell.ticket=tkt;
            g_sell.openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
            g_sell.openTime=(datetime)PositionGetInteger(POSITION_TIME);
            g_sell.currentVolume=vol;
            if(g_sell.originalSL==0) g_sell.originalSL=PositionGetDouble(POSITION_SL);
            g_sell.isHedge=(mag==InpMagicHedgeSell);
         }
      }
   }
   g_basketActive=(g_basketBuyCount+g_basketSellCount>1);
}

double GetPositionProfit(ulong tkt)
{
   if(!PositionSelectByTicket(tkt)) return 0;
   return PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
}

void TrackConsecutiveLosses(double cp)
{
   if(g_basketActive) return;
   if(cp<0){
      g_consecutiveLossCount++;
      LogMessage(2,"LossTrack:"+IntegerToString(g_consecutiveLossCount));
      if(InpConsecutiveLossesBeforeCooldown>0&&
         g_consecutiveLossCount>=InpConsecutiveLossesBeforeCooldown){
         datetime cb=iTime(_Symbol,PERIOD_CURRENT,0);
         g_cooldownUntilBarTime=cb+InpConsecutiveLossCooldownBars*PeriodSeconds(PERIOD_CURRENT);
         LogMessage(1,"Cooldown until:"+TimeToString(g_cooldownUntilBarTime));
      }
   } else {
      if(g_consecutiveLossCount>0)
         LogMessage(2,"LossTrack reset after "+IntegerToString(g_consecutiveLossCount));
      g_consecutiveLossCount=0;
   }
}

bool ClosePosition(ulong tkt,string reason="")
{
   double p=GetPositionProfit(tkt);
   for(int i=0;i<3;i++){
      if(!ConnectionOK()){Sleep(50);continue;}
      if(Trade.PositionClose(tkt)){
         Sleep(50);
         if(!PositionSelectByTicket(tkt)){
            if(reason!=""){
               Print("[Bot Claude V1] CERRADO (",reason,") $",DoubleToString(p,2));
               LogMessage(3,"CLOSED "+reason+" | $"+DoubleToString(p,2));
            }
            g_lastCloseTime=TimeCurrent();
            return true;
         }
      }
      Sleep(50);
   }
   LogMessage(0,"ClosePosition failed: "+IntegerToString(tkt));
   return false;
}

void CloseAllBasketPositions(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tkt=PositionGetTicket(i); if(tkt==0) continue;
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      ulong mag=PositionGetInteger(POSITION_MAGIC);
      if(mag==g_buy.magic||mag==g_sell.magic||
         mag==InpMagicHedgeBuy||mag==InpMagicHedgeSell)
         Trade.PositionClose(tkt);
   }
   Sleep(150);
   g_basketPeakProfit=0;
   g_basketLockLevel=0;
   g_basketTrailActive=false;
   g_lastCloseTime=TimeCurrent();
   LogMessage(3,"BASKET CLOSED: "+reason);
}

//+------------------------------------------------------------------+
void UpdateTrailing()
{
   if(g_basketActive) return;

   double qcTrigger = (InpLock2Trigger > 0) ? InpLock2Trigger : 3.0;
   double qcRetain  = 0.60;

   if(g_buy.hasPosition)
   {
      double p = GetPositionProfit(g_buy.ticket);
      if(p > g_buy.peakProfit) g_buy.peakProfit = p;

      if(g_buy.peakProfit >= qcTrigger && p > 0 && p <= g_buy.peakProfit * qcRetain)
         { ClosePosition(g_buy.ticket, "QUICK CAPTURE BUY"); return; }

      if(InpTrailingMode == TRAILING_RETRACEMENT)
      {
         if(!g_buy.trailingActive){
            if(SymbolInfoDouble(_Symbol,SYMBOL_BID) >=
               g_buy.openPrice + PipsToPrice(InpTrailActivatePips)){
               g_buy.trailingActive = true;
               LogMessage(3,"Trail RETRACEMENT BUY on @ $"+DoubleToString(p,2));
            }
         } else {
            if(g_buy.peakProfit > 0){
               double ret=(g_buy.peakProfit-p)/g_buy.peakProfit*100.0;
               if(ret >= InpTrailRetracementPct && p > 0)
                  ClosePosition(g_buy.ticket,"TRAILING RETRACEMENT BUY");
            }
         }
      }
      else if(InpTrailingMode == TRAILING_ATR)
      {
         double ab[]; ArraySetAsSeries(ab,true);
         if(CopyBuffer(g_handleTrailATR,0,1,1,ab)<1) return;
         double a=ab[0]; if(a<=0) return;
         double td  = a * InpTrailATRMultiplier;
         double mpd = td * (InpTrailATRMinProfitPct / 100.0);
         double cp  = SymbolInfoDouble(_Symbol,SYMBOL_BID);

         if(!g_buy.trailingActive)
         {
            bool aC = (p > 0 && (cp - g_buy.openPrice) >= mpd);
            bool uC = (InpTrailMinProfitUsd > 0 && p >= InpTrailMinProfitUsd);

            if(aC || uC)
            {
               g_buy.trailingActive = true;
               if(uC)
               {
                  double bsl = NormalizeDouble(g_buy.openPrice, _Digits);
                  double csl = PositionGetDouble(POSITION_SL);
                  double tp2 = PositionGetDouble(POSITION_TP);
                  if((csl == 0.0 || csl < bsl) && IsSLValid(POSITION_TYPE_BUY, bsl))
                  {
                     if(Trade.PositionModify(g_buy.ticket, bsl, tp2))
                        LogMessage(3,"Mosquito BUY SL=BE $"+DoubleToString(p,2));
                  }
               }
               if(aC) LogMessage(3,"Trail ATR BUY on $"+DoubleToString(p,2));
            }
         }
         else
         {
            double ns = NormalizeDouble(cp - td, _Digits);
            double cs = PositionGetDouble(POSITION_SL);
            if(ns > cs && ns > g_buy.openPrice && IsSLValid(POSITION_TYPE_BUY, ns))
            {
               double tp2 = PositionGetDouble(POSITION_TP);
               if(Trade.PositionModify(g_buy.ticket, ns, tp2))
                  LogMessage(3,"Trail ATR BUY SL:"+DoubleToString(cs,2)+
                               "->"+DoubleToString(ns,2));
            }
         }
      }
   }
   else { g_buy.peakProfit=0; g_buy.trailingActive=false; }

   if(g_sell.hasPosition)
   {
      double p = GetPositionProfit(g_sell.ticket);
      if(p > g_sell.peakProfit) g_sell.peakProfit = p;

      if(g_sell.peakProfit >= qcTrigger && p > 0 && p <= g_sell.peakProfit * qcRetain)
         { ClosePosition(g_sell.ticket,"QUICK CAPTURE SELL"); return; }

      if(InpTrailingMode == TRAILING_RETRACEMENT)
      {
         if(!g_sell.trailingActive){
            if(SymbolInfoDouble(_Symbol,SYMBOL_ASK) <=
               g_sell.openPrice - PipsToPrice(InpTrailActivatePips)){
               g_sell.trailingActive = true;
               LogMessage(3,"Trail RETRACEMENT SELL on @ $"+DoubleToString(p,2));
            }
         } else {
            if(g_sell.peakProfit > 0){
               double ret=(g_sell.peakProfit-p)/g_sell.peakProfit*100.0;
               if(ret >= InpTrailRetracementPct && p > 0)
                  ClosePosition(g_sell.ticket,"TRAILING RETRACEMENT SELL");
            }
         }
      }
      else if(InpTrailingMode == TRAILING_ATR)
      {
         double ab[]; ArraySetAsSeries(ab,true);
         if(CopyBuffer(g_handleTrailATR,0,1,1,ab)<1) return;
         double a=ab[0]; if(a<=0) return;
         double td  = a * InpTrailATRMultiplier;
         double mpd = td * (InpTrailATRMinProfitPct / 100.0);
         double cp  = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

         if(!g_sell.trailingActive)
         {
            bool aC = (p > 0 && (g_sell.openPrice - cp) >= mpd);
            bool uC = (InpTrailMinProfitUsd > 0 && p >= InpTrailMinProfitUsd);

            if(aC || uC)
            {
               g_sell.trailingActive = true;
               if(uC)
               {
                  double bsl = NormalizeDouble(g_sell.openPrice, _Digits);
                  double csl = PositionGetDouble(POSITION_SL);
                  double tp2 = PositionGetDouble(POSITION_TP);
                  if((csl == 0.0 || csl > bsl) && IsSLValid(POSITION_TYPE_SELL, bsl))
                  {
                     if(Trade.PositionModify(g_sell.ticket, bsl, tp2))
                        LogMessage(3,"Mosquito SELL SL=BE $"+DoubleToString(p,2));
                  }
               }
               if(aC) LogMessage(3,"Trail ATR SELL on $"+DoubleToString(p,2));
            }
         }
         else
         {
            double ns = NormalizeDouble(cp + td, _Digits);
            double cs = PositionGetDouble(POSITION_SL);
            if(ns < cs && ns < g_sell.openPrice && IsSLValid(POSITION_TYPE_SELL, ns))
            {
               double tp2 = PositionGetDouble(POSITION_TP);
               if(Trade.PositionModify(g_sell.ticket, ns, tp2))
                  LogMessage(3,"Trail ATR SELL SL:"+DoubleToString(cs,2)+
                               "->"+DoubleToString(ns,2));
            }
         }
      }
   }
   else { g_sell.peakProfit=0; g_sell.trailingActive=false; }
}

//+------------------------------------------------------------------+
void ApplyProfitLock(ScalperSide &side,ENUM_POSITION_TYPE pt,double tv,double ts)
{
   if(g_basketActive) return;
   if(!side.hasPosition||side.isHedge) return;
   if(!PositionSelectByTicket(side.ticket)) return;
   double p=GetPositionProfit(side.ticket);
   double vol=side.currentVolume; if(vol<=0) return;
   double best=0;
   if(InpLock1Trigger>0&&p>=InpLock1Trigger) best=MathMax(best,InpLock1Secure);
   if(InpLock2Trigger>0&&p>=InpLock2Trigger) best=MathMax(best,InpLock2Secure);
   if(InpLock3Trigger>0&&p>=InpLock3Trigger) best=MathMax(best,InpLock3Secure);
   if(best<=0) return;
   double ppd=(1.0/(tv*vol))*ts;
   double spd=best*ppd;
   double tsl=(pt==POSITION_TYPE_BUY)
              ?NormalizeDouble(side.openPrice+spd,_Digits)
              :NormalizeDouble(side.openPrice-spd,_Digits);
   double csl=PositionGetDouble(POSITION_SL);
   bool nm=(pt==POSITION_TYPE_BUY)?(csl==0||tsl>csl):(csl==0||tsl<csl);
   if(nm&&IsSLValid(pt,tsl)){
      double tp2=PositionGetDouble(POSITION_TP);
      if(Trade.PositionModify(side.ticket,tsl,tp2))
         LogMessage(3,"LOCK $"+DoubleToString(p,2)+"->$"+DoubleToString(best,2)+
                      " @"+DoubleToString(tsl,_Digits));
   }
}

void CheckProfitLock()
{
   if(g_basketActive) return;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0||ts<=0) return;
   ApplyProfitLock(g_buy, POSITION_TYPE_BUY,  tv,ts);
   ApplyProfitLock(g_sell,POSITION_TYPE_SELL, tv,ts);
}

//+------------------------------------------------------------------+
void CheckPositionHealth()
{
   if(g_basketActive||!InpUseHealthExit) return;
   if(g_buy.hasPosition&&!g_buy.isHedge){
      double h=EvaluatePositionHealth(POSITION_TYPE_BUY,g_buy.openPrice,g_buy.openTime);
      double p=GetPositionProfit(g_buy.ticket);
      if(h<InpMinHealthScore&&p>0)
         ClosePosition(g_buy.ticket,"HEALTH DECAY BUY");
      else if(h<InpMinHealthScore&&p<=0&&InpCriticalHealthCutLoss&&h<InpCriticalHealthThreshold)
         ClosePosition(g_buy.ticket,"CRITICAL HEALTH CUT BUY");
   }
   if(g_sell.hasPosition&&!g_sell.isHedge){
      double h=EvaluatePositionHealth(POSITION_TYPE_SELL,g_sell.openPrice,g_sell.openTime);
      double p=GetPositionProfit(g_sell.ticket);
      if(h<InpMinHealthScore&&p>0)
         ClosePosition(g_sell.ticket,"HEALTH DECAY SELL");
      else if(h<InpMinHealthScore&&p<=0&&InpCriticalHealthCutLoss&&h<InpCriticalHealthThreshold)
         ClosePosition(g_sell.ticket,"CRITICAL HEALTH CUT SELL");
   }
}

//+------------------------------------------------------------------+
void CheckTimeStop()
{
   if(g_basketActive||InpMaxTradeMinutes<=0) return;
   datetime now=TimeCurrent();
   if(g_buy.hasPosition&&!g_buy.trailingActive&&!g_buy.isHedge){
      int m=(int)((now-g_buy.openTime)/60);
      if(m>=InpMaxTradeMinutes&&GetPositionProfit(g_buy.ticket)>0)
         ClosePosition(g_buy.ticket,"TIME STOP BUY");
   }
   if(g_sell.hasPosition&&!g_sell.trailingActive&&!g_sell.isHedge){
      int m=(int)((now-g_sell.openTime)/60);
      if(m>=InpMaxTradeMinutes&&GetPositionProfit(g_sell.ticket)>0)
         ClosePosition(g_sell.ticket,"TIME STOP SELL");
   }
}

//+------------------------------------------------------------------+
void ManageBasketRecovery()
{
   if(!InpEnableBasketHedge) return;

   double   tbp=0;
   int      bc=0,buc=0,sec=0;
   double   lbp=0,lsp=0;
   datetime lbt=0,lst=0,obt=0;

   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tkt=PositionGetTicket(i); if(tkt==0) continue;
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      ulong mag=PositionGetInteger(POSITION_MAGIC);
      if(mag!=g_buy.magic&&mag!=g_sell.magic&&
         mag!=InpMagicHedgeBuy&&mag!=InpMagicHedgeSell) continue;
      double pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      ENUM_POSITION_TYPE tp=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
      double   op=PositionGetDouble(POSITION_PRICE_OPEN);
      tbp+=pnl; bc++;
      if(obt==0||ot<obt) obt=ot;
      if(tp==POSITION_TYPE_BUY){buc++;if(ot>lbt){lbt=ot;lbp=op;}}
      else {sec++;if(ot>lst){lst=ot;lsp=op;}}
   }
   if(bc==0) return;

   if(g_basketActive)
   {
      if(tbp>g_basketPeakProfit) g_basketPeakProfit=tbp;

      if(InpBasketLockTrigger>0&&tbp>=InpBasketLockTrigger)
         g_basketLockLevel=MathMax(g_basketLockLevel,InpBasketLockSecure);

      if(g_basketLockLevel>0&&tbp>0&&tbp<=g_basketLockLevel)
         { CloseAllBasketPositions("BASKET LOCK EXIT"); return; }

      if(!g_basketTrailActive&&tbp>=InpBasketTrailActivate)
         { g_basketTrailActive=true; LogMessage(3,"BASKET TRAIL ON @$"+DoubleToString(tbp,2)); }

      if(g_basketTrailActive&&g_basketPeakProfit>0){
         double ret=(g_basketPeakProfit-tbp)/g_basketPeakProfit*100.0;
         if(ret>=InpBasketTrailRetracement&&tbp>0)
            { CloseAllBasketPositions("BASKET TRAILING"); return; }
      }

      if(InpBasketMaxMinutes>0&&obt>0){
         int mins=(int)((TimeCurrent()-obt)/60);
         if(mins>=InpBasketMaxMinutes&&tbp>0)
            { CloseAllBasketPositions("BASKET TIME STOP"); return; }
      }
   }

   if(g_basketActive&&tbp>=InpBasketTargetUSD)
      { CloseAllBasketPositions("BASKET TP: $"+DoubleToString(tbp,2)); return; }

   if(bc==1&&tbp<=-InpHedgeTriggerUSD)
   {
      ENUM_POSITION_TYPE ot2=g_buy.hasPosition?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
      ENUM_ORDER_TYPE    hd =(ot2==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      ulong hm=(hd==ORDER_TYPE_BUY)?InpMagicHedgeBuy:InpMagicHedgeSell;
      double hp=(hd==ORDER_TYPE_SELL)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      g_basketPeakProfit=0; g_basketLockLevel=0; g_basketTrailActive=false;
      Trade.SetExpertMagicNumber(hm);
      if(Trade.PositionOpen(_Symbol,hd,NormalizeVolume(InpLotSize),hp,0,0,"BASKET|HEDGE 1"))
         { LogMessage(3,"HEDGE "+(hd==ORDER_TYPE_BUY?"BUY":"SELL")+" loss:$"+DoubleToString(tbp,2)); Sleep(100); }
      return;
   }

   if(bc==2&&buc==1&&sec==1)
   {
      ulong htkt=0, otkt=0;
      double hpnl=0, opnl=0;

      for(int k=PositionsTotal()-1;k>=0;k--){
         ulong t=PositionGetTicket(k);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         ulong m=PositionGetInteger(POSITION_MAGIC);
         double pn=PositionGetDouble(POSITION_PROFIT)+
                   PositionGetDouble(POSITION_SWAP);
         if(m==InpMagicHedgeSell||m==InpMagicHedgeBuy)
            { htkt=t; hpnl=pn; }
         else if(m==g_buy.magic||m==g_sell.magic)
            { otkt=t; opnl=pn; }
      }

      if(hpnl>0 && opnl<0 && hpnl>=MathAbs(opnl)*0.5 && otkt>0)
      {
         LogMessage(3,"SMART EXIT A -> cierra ORIGINAL "+
                      "o="+DoubleToString(opnl,2)+
                      " h=+"+DoubleToString(hpnl,2));
         Trade.PositionClose(otkt);
         Sleep(100);
         g_basketPeakProfit  = 0;
         g_basketLockLevel   = 0;
         g_basketTrailActive = false;
         g_lastCloseTime     = TimeCurrent();
         return;
      }

      if(opnl>0 && hpnl<0 && MathAbs(hpnl)<opnl*0.5 && htkt>0)
      {
         LogMessage(3,"SMART EXIT B -> cierra HEDGE "+
                      "o=+"+DoubleToString(opnl,2)+
                      " h="+DoubleToString(hpnl,2));
         Trade.PositionClose(htkt);
         Sleep(100);
         g_basketPeakProfit  = 0;
         g_basketLockLevel   = 0;
         g_basketTrailActive = false;
         g_lastCloseTime     = TimeCurrent();
         return;
      }
   }

   if(bc>=2&&bc<InpMaxHedgeLevels)
   {
      double bpnl=0,spnl=0;
      for(int k=PositionsTotal()-1;k>=0;k--){
         ulong t=PositionGetTicket(k); if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         ulong m=PositionGetInteger(POSITION_MAGIC);
         if(m!=g_buy.magic&&m!=g_sell.magic&&m!=InpMagicHedgeBuy&&m!=InpMagicHedgeSell) continue;
         double pn=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) bpnl+=pn;
         else spnl+=pn;
      }
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double gl=NormalizeVolume(InpLotSize);

      if(spnl>bpnl&&lsp>0&&(lsp-bid)/GetPipSize()>=InpHedgeGridStepPips){
         double mr=0;
         if(!OrderCalcMargin(ORDER_TYPE_SELL,_Symbol,gl,bid,mr)){
            double cs=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
            double lv=(double)AccountInfoInteger(ACCOUNT_LEVERAGE);
            if(cs>0&&lv>0) mr=gl*cs*bid/lv;
         }
         if(mr>0&&AccountInfoDouble(ACCOUNT_MARGIN_FREE)>=mr*1.5){
            Trade.SetExpertMagicNumber(InpMagicHedgeSell);
            if(Trade.PositionOpen(_Symbol,ORDER_TYPE_SELL,gl,bid,0,0,"BASKET|GRID SELL"))
               { LogMessage(3,"GRID SELL b:$"+DoubleToString(bpnl,2)+" s:$"+DoubleToString(spnl,2)); Sleep(100); }
         } else LogMessage(1,"GRID SELL BLOCKED free:$"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2));
      }
      else if(bpnl>spnl&&lbp>0&&(ask-lbp)/GetPipSize()>=InpHedgeGridStepPips){
         double mr=0;
         if(!OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,gl,ask,mr)){
            double cs=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
            double lv=(double)AccountInfoInteger(ACCOUNT_LEVERAGE);
            if(cs>0&&lv>0) mr=gl*cs*ask/lv;
         }
         if(mr>0&&AccountInfoDouble(ACCOUNT_MARGIN_FREE)>=mr*1.5){
            Trade.SetExpertMagicNumber(InpMagicHedgeBuy);
            if(Trade.PositionOpen(_Symbol,ORDER_TYPE_BUY,gl,ask,0,0,"BASKET|GRID BUY"))
               { LogMessage(3,"GRID BUY b:$"+DoubleToString(bpnl,2)+" s:$"+DoubleToString(spnl,2)); Sleep(100); }
         } else LogMessage(1,"GRID BUY BLOCKED free:$"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2));
      }
   }
}

//+------------------------------------------------------------------+
bool OpenOrder(ENUM_ORDER_TYPE dir,double score)
{
   if(!SymInfo.RefreshRates()) return false;
   double price=(dir==ORDER_TYPE_BUY)?SymInfo.Ask():SymInfo.Bid();
   double lot=NormalizeVolume(InpLotSize);
   if(InpMaxLotPerPosition>0&&lot>InpMaxLotPerPosition) lot=InpMaxLotPerPosition;
   double mr=0;
   if(!OrderCalcMargin(dir,_Symbol,lot,price,mr))
      { LogMessage(0,"MARGIN CALC FAILED"); return false; }
   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE)<mr*1.5)
      { LogMessage(1,"MARGIN BLOCKED"); return false; }

   double atrVal = GetCurrentATR();
   double sl=0, tp=0;

   double sld=0;
   if(InpSLPips>0)
      sld = PipsToPrice(InpSLPips);
   else if(atrVal>0)
      sld = atrVal * InpSL_ATR_Multiplier;
   else
      sld = PipsToPrice(30.0);

   double tpd=0;
   if(InpTPPips>0)
      tpd = PipsToPrice(InpTPPips);
   else if(sld>0)
      tpd = sld * InpTP_SL_Ratio;

   Trade.SetExpertMagicNumber((dir==ORDER_TYPE_BUY)?g_buy.magic:g_sell.magic);

   if(dir==ORDER_TYPE_BUY){
      if(sld>0) sl=NormalizeDouble(price-sld,_Digits);
      if(tpd>0) tp=NormalizeDouble(price+tpd,_Digits);
   } else {
      if(sld>0) sl=NormalizeDouble(price+sld,_Digits);
      if(tpd>0) tp=NormalizeDouble(price-tpd,_Digits);
   }

   ENUM_POSITION_TYPE pt = (dir==ORDER_TYPE_BUY)?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
   if(sl>0 && !IsSLValid(pt,sl))
      sl=0;

   if(!Trade.PositionOpen(_Symbol,dir,lot,price,sl,tp,"SGSv4.401"))
      { LogMessage(0,"ERROR open: "+IntegerToString(GetLastError())); return false; }

   LogMessage(3,(dir==ORDER_TYPE_BUY?"BUY":"SELL")+" @"+DoubleToString(price,_Digits)+
              " SL:"+DoubleToString(sl,_Digits)+
              " TP:"+DoubleToString(tp,_Digits)+
              " sc:"+DoubleToString(score,1)+" lot:"+DoubleToString(lot,2));
   Sleep(100);
   g_orderOpenedThisTick=true;
   g_tradesToday++;
   return true;
}

//+------------------------------------------------------------------+
void ManageEntries()
{
   if(g_orderOpenedThisTick) return;
   if(InpPostCloseCooldown>0&&g_lastCloseTime>0&&
      TimeCurrent()-g_lastCloseTime<InpPostCloseCooldown) return;
   if(!SpreadOK()||!ConnectionOK()||!IsSessionActive()) return;
   if(g_dailyTargetHit||g_dailyFloorHit) return;
   if(InpMaxTradesPerDay>0&&g_tradesToday>=InpMaxTradesPerDay) return;
   if(IsNoTradeWindow()||g_emergencyStop) return;

   int ap=0;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tkt=PositionGetTicket(i);
      if(PositionSelectByTicket(tkt)){
         ulong m=PositionGetInteger(POSITION_MAGIC);
         if(PositionGetString(POSITION_SYMBOL)==_Symbol&&
            (m==g_buy.magic||m==g_sell.magic||m==InpMagicHedgeBuy||m==InpMagicHedgeSell)) ap++;
      }
   }
   if(ap>0) return;

   if(InpUseSignalLock){
      datetime cb=iTime(_Symbol,PERIOD_CURRENT,1);
      if(cb==g_lastSignalBarTime) return;
   }

   SignalStrength bs=GetSignalStrength(ORDER_TYPE_BUY);
   SignalStrength ss=GetSignalStrength(ORDER_TYPE_SELL);
   double bsc=bs.finalScore, ssc=ss.finalScore;
   double bth=InpMinBuyScore, sth=InpMinSellScore;

   if(InpEnableSignalDampening){
      bsc=ApplyDampening(bsc,POSITION_TYPE_BUY, bth);
      ssc=ApplyDampening(ssc,POSITION_TYPE_SELL,sth);
   }

   if(bsc>=bth&&ssc<sth){
      double p=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(!CheckEntryConditions(POSITION_TYPE_BUY,p)) return;
      if(!IsMomentumVolatilityFilter(ORDER_TYPE_BUY)) return;
      if(OpenOrder(ORDER_TYPE_BUY,bs.finalScore)&&InpUseSignalLock)
         g_lastSignalBarTime=iTime(_Symbol,PERIOD_CURRENT,1);
   } else if(ssc>=sth&&bsc<bth){
      double p=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(!CheckEntryConditions(POSITION_TYPE_SELL,p)) return;
      if(!IsMomentumVolatilityFilter(ORDER_TYPE_SELL)) return;
      if(OpenOrder(ORDER_TYPE_SELL,ss.finalScore)&&InpUseSignalLock)
         g_lastSignalBarTime=iTime(_Symbol,PERIOD_CURRENT,1);
   }
}

//+------------------------------------------------------------------+
void CheckDailyLimits()
{
   g_dailyProfit=AccountInfoDouble(ACCOUNT_BALANCE)-g_initialBalance;
   if(InpDailyTarget>0&&!g_dailyTargetHit&&g_dailyProfit>=InpDailyTarget)
      { g_dailyTargetHit=true; LogMessage(3,"DAILY TARGET +$"+DoubleToString(g_dailyProfit,2)); }
   if(InpDailyFloor>0&&!g_dailyFloorHit&&g_dailyProfit<=-InpDailyFloor){
      g_dailyFloorHit=true;
      LogMessage(3,"DAILY FLOOR -$"+DoubleToString(MathAbs(g_dailyProfit),2));
      for(int i=PositionsTotal()-1;i>=0;i--){
         ulong tkt=PositionGetTicket(i);
         if(PositionSelectByTicket(tkt)){
            ulong m=PositionGetInteger(POSITION_MAGIC);
            if(m==g_buy.magic||m==g_sell.magic||m==InpMagicHedgeBuy||m==InpMagicHedgeSell)
               Trade.PositionClose(tkt);
         }
      }
   }
}

//+------------------------------------------------------------------+
void PanelRegister(string name)
{
   for(int i=0;i<PanelObjectCount;i++) if(PanelObjects[i]==name) return;
   if(PanelObjectCount<ArraySize(PanelObjects)) PanelObjects[PanelObjectCount++]=name;
}

void PanelCreate(string name,int x,int y,int w,int h,color bg,color border,int corner=0)
{
   if(ObjectFind(0,name)<0){
      ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      PanelRegister(name);
   }
   ObjectSetInteger(0,name,OBJPROP_CORNER,     corner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,      w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,      h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,      border);
}

void PanelLabel(string name,string text,int x,int y,int w,int h,
                color clr,int fs=8,string font="Consolas",int corner=0)
{
   if(ObjectFind(0,name)<0){
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  fs);
      ObjectSetString(  0,name,OBJPROP_FONT,      font);
      ObjectSetInteger(0,name,OBJPROP_BACK,       false);
      PanelRegister(name);
   }
   ObjectSetInteger(0,name,OBJPROP_CORNER,    corner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, y);
   ObjectSetString (0,name,OBJPROP_TEXT,  text);
   ObjectSetInteger(0,name,OBJPROP_COLOR, clr);
}

void PanelProgress(string name,int x,int y,int w,int h,
                   double pct,color fc,color bc,int corner=0)
{
   string bgN=name+"_BG", fiN=name+"_FILL";
   
   if(ObjectFind(0,bgN)<0){
      ObjectCreate(0,bgN,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bgN,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bgN,OBJPROP_BACK,false);
      PanelRegister(bgN);
   }
   ObjectSetInteger(0,bgN,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,bgN,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,bgN,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,bgN,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,bgN,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,bgN,OBJPROP_BGCOLOR,bc);
   ObjectSetInteger(0,bgN,OBJPROP_COLOR,bc);

   int fw=(int)(w*MathMax(0.0,MathMin(1.0,pct)));
   if(fw<2) fw=2;
   if(ObjectFind(0,fiN)<0){
      ObjectCreate(0,fiN,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,fiN,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,fiN,OBJPROP_BACK,false);
      PanelRegister(fiN);
   }
   ObjectSetInteger(0,fiN,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,fiN,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,fiN,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,fiN,OBJPROP_XSIZE,fw);
   ObjectSetInteger(0,fiN,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,fiN,OBJPROP_BGCOLOR,fc);
   ObjectSetInteger(0,fiN,OBJPROP_COLOR,fc);
}

void PanelLine(string name,int x1,int y1,int x2,int y2,color clr,int corner=0)
{
   if(ObjectFind(0,name)<0){
      ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      PanelRegister(name);
   }
   ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x1);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y1);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,x2-x1);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,1);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
}

void DestroyPanel()
{
   for(int i=PanelObjectCount-1;i>=0;i--) ObjectDelete(0,PanelObjects[i]);
   PanelObjectCount=0; ZeroMemory(PanelObjects);
}

//+------------------------------------------------------------------+
void CalculatePanelDimensions()
{
   g_scale = MathMax(50, MathMin(200, InpPanelScalePercent));

   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   int baseW = 295;
   int baseS = 16;
   int baseRowH = 18;
   int baseSecH = 20;
   int baseSB = 13;

   g_panelW = (int)(baseW * g_scale / 100.0);
   g_S = MathMax(10, (int)(baseS * g_scale / 100.0));
   g_rowH = MathMax(12, (int)(baseRowH * g_scale / 100.0));
   g_secH = MathMax(14, (int)(baseSecH * g_scale / 100.0));
   g_SB = MathMax(8, (int)(baseSB * g_scale / 100.0));

   int corner = InpPanelCornerRight ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER;
   if(InpPanelCornerRight){
      g_panelX = MathMax(10, chartW - g_panelW - 10);
   } else {
      g_panelX = 10;
   }
   g_panelY = 30;

   g_padL = g_panelX + (int)(10 * g_scale / 100.0);
   g_padR = g_panelX + g_panelW - (int)(10 * g_scale / 100.0);
   g_colV = g_panelX + (int)(148 * g_scale / 100.0);
}

//+------------------------------------------------------------------+
void UpdatePanelData()
{
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);
   double fl =eq-bal;

   g_pFloat   =(fl>=0?"+$":"-$")+DoubleToString(MathAbs(fl),2);
   g_pDailyPct=(g_initialBalance>0)?g_dailyProfit/g_initialBalance*100.0:0;
   g_pDaily   =DoubleToString(g_dailyProfit,2)+" ("+DoubleToString(g_pDailyPct,1)+"%)";

   string st="OPERANDO";
   if(g_emergencyStop)          st="EMERGENCY";
   else if(g_dailyFloorHit)     st="FLOOR HIT";
   else if(g_dailyTargetHit)    st="TARGET HIT";
   else if(!IsSessionActive())  st="FUERA SESION";
   else if(IsNoTradeWindow())   st="NO-TRADE";
   else if(!ConnectionOK())     st="SIN CONEXION";
   else if(!SpreadOK())         st="SPREAD ALTO";
   g_pStatus=st;

   string ps="NINGUNA";
   if(g_buy.hasPosition&&!g_buy.isHedge)        ps="LONG";
   else if(g_sell.hasPosition&&!g_sell.isHedge) ps="SHORT";
   else if(g_buy.hasPosition&&g_buy.isHedge)    ps="HEDGE LONG";
   else if(g_sell.hasPosition&&g_sell.isHedge)  ps="HEDGE SHORT";
   g_pPos=ps;

   g_pTime =(GetEffectiveTimeStr());
   g_pBasket=g_basketActive
             ? IntegerToString(g_basketBuyCount+g_basketSellCount)+" pos | "+
               (g_basketTotalPnL>=0?"+$":"-$")+DoubleToString(MathAbs(g_basketTotalPnL),2)
             : "OFF";

   g_pSpreadPts=(int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   g_pSpread   =IntegerToString(g_pSpreadPts)+" pts";

   SignalStrength bs = g_cachedBuyScore;
   SignalStrength ss = g_cachedSellScore;
   double db = g_lastBuyScore;
   double ds = g_lastSellScore;

   g_pBuyScore  =DoubleToString(db,1)+"/"+DoubleToString(InpMinBuyScore, 1);
   g_pSellScore =DoubleToString(ds,1)+"/"+DoubleToString(InpMinSellScore,1);
   g_pBuyVel    =DoubleToString(bs.normalizedVelocity,2);
   g_pSellVel   =DoubleToString(ss.normalizedVelocity,2);
   g_pBuyBarPct =db/10.0;
   g_pSellBarPct=ds/10.0;

   if(g_buy.hasPosition||g_sell.hasPosition){
      bool ib=g_buy.hasPosition;
      ulong at=ib?g_buy.ticket:g_sell.ticket;
      double ao=ib?g_buy.openPrice:g_sell.openPrice;
      datetime aot=ib?g_buy.openTime:g_sell.openTime;
      g_pProfitVal=GetPositionProfit(at);
      g_pProfit   =(g_pProfitVal>=0?"+$":"-$")+DoubleToString(MathAbs(g_pProfitVal),2);
      g_pHealthVal=EvaluatePositionHealth(ib?POSITION_TYPE_BUY:POSITION_TYPE_SELL,ao,aot);
      g_pHealth   =DoubleToString(g_pHealthVal,2);
      g_pMins     =(int)((TimeCurrent()-aot)/60);
   } else {
      g_pProfitVal=999999; g_pHealthVal=-1; g_pMins=-1;
      g_pProfit="---"; g_pHealth="---";
   }
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   CalculatePanelDimensions();

   int corner = InpPanelCornerRight ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER;
   int x = g_panelX;
   int y = g_panelY;
   int w = g_panelW;
   int padL = g_padL;
   int padR = g_padR;
   int colV = g_colV;
   int S = g_S;
   int SB = g_SB;

   int hc = 26 + 10; 
   hc += g_secH + g_rowH + g_rowH + g_rowH + 22 + g_rowH + SB + 8;
   hc += g_secH + g_rowH + g_rowH + g_rowH + g_rowH + g_rowH + 8;
   hc += g_secH + g_rowH + g_rowH + g_rowH + g_rowH + 22 + 8;
   
   hc += g_secH + g_rowH + g_rowH; 
   hc += g_rowH; 
   hc += g_rowH; 
   bool hasHedge = (g_buy.hasPosition&&g_buy.isHedge) || (g_sell.hasPosition&&g_sell.isHedge);
   if(hasHedge) hc += g_rowH;
   hc += SB; 
   hc += 8;
   
   hc += 22; 
   g_panelH = hc;

   int fs = MathMax(7, (int)(8 * g_scale / 100.0));
   int fsTitle = MathMax(7, (int)(9 * g_scale / 100.0));
   int fsProfit = MathMax(8, (int)(9 * g_scale / 100.0));
   int fsSmall = MathMax(6, (int)(7 * g_scale / 100.0));

   PanelCreate("SGS_BG",    x,y,w,hc,CLR_BG,      CLR_BORDER,  corner);
   PanelCreate("SGS_HDR",   x,y,w,26, CLR_GOLD_DIM,CLR_GOLD_DIM,corner);
   PanelLabel ("SGS_TITLE","SHEPHERD GOLD v4.401",x+(int)(10*g_scale/100.0),y+5,w-(int)(20*g_scale/100.0),18,CLR_BG,fsTitle,"Consolas",corner);

   int row=y+34;

   PanelLabel("SGS_SEC1","= CUENTA",padL,row,120,S,CLR_GOLD,fs,"Consolas",corner); row+=g_secH;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);
   color eqC=(eq>=bal)?CLR_GREEN:CLR_RED;
   PanelLabel("SGS_L_BAL","Balance:", padL,row,80,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_BAL","$"+DoubleToString(bal,2),colV,row,120,S,CLR_WHITE,fs,"Consolas",corner); row+=g_rowH;
   PanelLabel("SGS_L_EQ","Equity:",  padL,row,80,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_EQ","$"+DoubleToString(eq,2), colV,row,120,S,eqC,fs,"Consolas",corner); row+=g_rowH;
   PanelLabel("SGS_L_FL","Flotante:",padL,row,80,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_FL",g_pFloat,  colV,row,120,S,eqC,fs,"Consolas",corner); row+=22;
   color dC=(g_dailyProfit>=0)?CLR_GREEN:CLR_RED;
   PanelLabel("SGS_L_DY","Daily P/L:",padL,row,80,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_DY",g_pDaily,   colV,row,120,S,dC,fs,"Consolas",corner); row+=g_rowH;
   PanelProgress("SGS_BAR_DY",padL,row,w-(int)(20*g_scale/100.0),5,MathAbs(g_pDailyPct)/5.0,dC,CLR_BAR_BG,corner); row+=SB;
   PanelLine("SGS_S1",padL,row,padR,row,CLR_BORDER,corner); row+=8;

   PanelLabel("SGS_SEC2","= ESTADO",padL,row,120,S,CLR_GOLD,fs,"Consolas",corner); row+=g_secH;
   color stC=CLR_GREEN;
   if(g_emergencyStop||g_dailyFloorHit||!ConnectionOK()) stC=CLR_RED;
   else if(g_dailyTargetHit) stC=CLR_GOLD;
   else if(!IsSessionActive()||IsNoTradeWindow()||!SpreadOK()) stC=CLR_ORANGE;
   PanelLabel("SGS_L_ST","Estado:",  padL,row,80,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_ST",g_pStatus, colV,row,110,S,stC,fs,"Consolas",corner); row+=g_rowH;
   color poC=CLR_NEUTRAL;
   if(g_pPos=="LONG") poC=CLR_BUY;
   else if(g_pPos=="SHORT") poC=CLR_SELL;
   else if(StringFind(g_pPos,"HEDGE")>=0) poC=CLR_HEDGE;
   PanelLabel("SGS_L_PO","Posicion:",padL,row,80,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_PO",g_pPos,    colV,row,110,S,poC,fs,"Consolas",corner); row+=g_rowH;
   string tsrc=InpUseLocalTimeSync?"PC":(InpManualTimeOffsetHours!=0?"MANUAL":"SERVER");
   PanelLabel("SGS_L_TM","Hora("+tsrc+"):",padL,row,90,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_TM",g_pTime,         colV,row,80,S,CLR_BLUE,fs,"Consolas",corner); row+=g_rowH;
   color bkC=g_basketActive?CLR_HEDGE:CLR_GRAY;
   PanelLabel("SGS_L_BK","Basket:",  padL,row,80,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_BK",g_pBasket, colV,row,130,S,bkC,fs,"Consolas",corner); row+=g_rowH;
   color spC=(g_pSpreadPts<=30)?CLR_GREEN:(g_pSpreadPts<=50?CLR_ORANGE:CLR_RED);
   PanelLabel("SGS_L_SP","Spread:",   padL,row,80,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_SP",g_pSpread,  colV,row,80,S,spC,fs,"Consolas",corner); row+=g_rowH;
   PanelLine("SGS_S2",padL,row,padR,row,CLR_BORDER,corner); row+=8;

   PanelLabel("SGS_SEC3","= SEÑALES NYAO",padL,row,150,S,CLR_GOLD,fs,"Consolas",corner); row+=g_secH;
   color bsC=(g_pBuyBarPct*10.0>=InpMinBuyScore)?CLR_BUY:CLR_NEUTRAL;
   PanelLabel("SGS_L_BS","BUY:",       padL,    row,40,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_BS",g_pBuyScore, padL+(int)(38*g_scale/100.0), row,70,S,bsC,fsTitle,"Consolas",corner);
   PanelProgress("SGS_BAR_BS",colV+(int)(20*g_scale/100.0),row+4,70,7,g_pBuyBarPct,bsC,CLR_BAR_BG,corner); row+=g_rowH;
   color bvC=(StringToDouble(g_pBuyVel)>0.5)?CLR_GREEN:CLR_NEUTRAL;
   PanelLabel("SGS_L_BV","  vel:",    padL,    row,40,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_BV",g_pBuyVel, padL+(int)(38*g_scale/100.0), row,60,S,bvC,fs,"Consolas",corner); row+=g_rowH;
   color ssC=(g_pSellBarPct*10.0>=InpMinSellScore)?CLR_SELL:CLR_NEUTRAL;
   PanelLabel("SGS_L_SS","SELL:",      padL,    row,40,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_SS",g_pSellScore,padL+(int)(38*g_scale/100.0), row,70,S,ssC,fsTitle,"Consolas",corner);
   PanelProgress("SGS_BAR_SS",colV+(int)(20*g_scale/100.0),row+4,70,7,g_pSellBarPct,ssC,CLR_BAR_BG,corner); row+=g_rowH;
   color svC=(StringToDouble(g_pSellVel)>0.5)?CLR_GREEN:CLR_NEUTRAL;
   PanelLabel("SGS_L_SV","  vel:",     padL,    row,40,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_SV",g_pSellVel, padL+(int)(38*g_scale/100.0), row,60,S,svC,fs,"Consolas",corner); row+=22;
   PanelLine("SGS_S3",padL,row,padR,row,CLR_BORDER,corner); row+=8;

   PanelLabel("SGS_SEC5","= POSICION ACTIVA",padL,row,160,S,CLR_GOLD,fs,"Consolas",corner); row+=g_secH;
   bool ib=g_buy.hasPosition;
   bool isS=g_sell.hasPosition;
   bool ih=ib?g_buy.isHedge:(isS?g_sell.isHedge:false);
   
   color sdC=ib?(ih?CLR_HEDGE:CLR_BUY):(isS?(ih?CLR_HEDGE:CLR_SELL):CLR_NEUTRAL);
   string sdS=ib?(ih?"HEDGE LONG":"LONG"):(isS?(ih?"HEDGE SHORT":"SHORT"):"NINGUNA");
   PanelLabel("SGS_L_SD","Dir:",    padL,row,50,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_SD",sdS,      colV,row,120,S,sdC,fs,"Consolas",corner); row+=g_rowH;
   
   color ppC=(g_pProfitVal!=999999)?((g_pProfitVal>=0)?CLR_GREEN:CLR_RED):CLR_NEUTRAL;
   PanelLabel("SGS_L_PP","Profit:", padL,row,60,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_PP",g_pProfit,colV,row,100,S,ppC,fsProfit,"Consolas",corner); row+=g_rowH;
   
   color hC=(g_pHealthVal>=InpMinHealthScore)?CLR_GREEN:(g_pHealthVal>=InpMinHealthScore*0.7?CLR_ORANGE:CLR_RED);
   PanelLabel("SGS_L_HH","Health:",padL,   row,60,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_HH",g_pHealth,colV,   row,50,S,hC,fs,"Consolas",corner);
   if(g_pHealthVal>=0) PanelProgress("SGS_BAR_HH",colV+(int)(55*g_scale/100.0),row+4,55,7,g_pHealthVal,hC,CLR_BAR_BG,corner); 
   row+=g_rowH;
   
   bool tron=ib?g_buy.trailingActive:(isS?g_sell.trailingActive:false);
   PanelLabel("SGS_L_TA","Trailing:",padL,row,70,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_TA",(ib||isS)?(tron?"ACTIVO":"INACTIVO"):"---",colV,row,100,S,tron?CLR_GREEN:CLR_NEUTRAL,fs,"Consolas",corner); row+=g_rowH;
   
   if(ih){
      PanelLabel("SGS_L_BL","Basket lv:",padL,row,70,S,CLR_GRAY,fs,"Consolas",corner);
      PanelLabel("SGS_V_BL",IntegerToString(g_basketBuyCount+g_basketSellCount),colV,row,40,S,CLR_HEDGE,fs,"Consolas",corner); row+=g_rowH;
   }
   
   color tmC=(InpMaxTradeMinutes>0&&g_pMins>=InpMaxTradeMinutes)?CLR_RED:CLR_WHITE;
   PanelLabel("SGS_L_MT","Tiempo:",padL,row,70,S,CLR_GRAY,fs,"Consolas",corner);
   PanelLabel("SGS_V_MT",(g_pMins<0?"0":IntegerToString(g_pMins))+" min",colV,row,80,S,tmC,fs,"Consolas",corner); row+=SB;
   row+=8;

   PanelLine("SGS_FTL",x,y+hc-18,x+w,y+hc-18,CLR_GOLD_DIM,corner);
   PanelLabel("SGS_FTT","PASTOR-RECUPERADOR v4.401 | EN EL NOMBRE DE JESUS",
              x+6,y+hc-13,w-12,12,CLR_GRAY,fsSmall,"Consolas",corner);
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void UpdateConsecutiveCandles()
{
   datetime cb=iTime(_Symbol,PERIOD_CURRENT,0);
   if(g_lastBarTime!=cb)
   {
      g_lastBuyScorePrev =g_lastBuyScore;
      g_lastSellScorePrev=g_lastSellScore;
      g_lastBuyScore =GetSignalStrength(ORDER_TYPE_BUY).finalScore;
      g_lastSellScore=GetSignalStrength(ORDER_TYPE_SELL).finalScore;
      g_consecutiveBuyCandles =g_buy.hasPosition ?g_consecutiveBuyCandles +1:0;
      g_consecutiveSellCandles=g_sell.hasPosition?g_consecutiveSellCandles+1:0;
      g_lastBarTime=cb;
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetDeviationInPoints(10);
   Trade.SetAsyncMode(false);
   if(!SymInfo.Name(_Symbol)) return INIT_FAILED;

   g_handleFast    =iMA(_Symbol,PERIOD_CURRENT,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_handleSlow    =iMA(_Symbol,PERIOD_CURRENT,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_handleRSI     =iRSI(_Symbol,PERIOD_CURRENT,InpRSIPeriod,PRICE_CLOSE);
   g_handleATR     =iATR(_Symbol,PERIOD_CURRENT,InpATRPeriod);
   g_handleTrailATR=iATR(_Symbol,PERIOD_CURRENT,InpTrailATRPeriod);

   if(g_handleFast==INVALID_HANDLE||g_handleSlow==INVALID_HANDLE||
      g_handleRSI ==INVALID_HANDLE||g_handleATR ==INVALID_HANDLE||
      g_handleTrailATR==INVALID_HANDLE) return INIT_FAILED;

   g_buy.enabled=true;  g_buy.magic =(ulong)InpMagicBuy;
   g_sell.enabled=true; g_sell.magic=(ulong)InpMagicSell;

   g_initialBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakEquity    =AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradesToday=0; g_dailyProfit=0;
   g_dailyTargetHit=false; g_dailyFloorHit=false;
   g_lastSignalBarTime=0;
   g_consecutiveLossCount=0; g_cooldownUntilBarTime=0;
   g_consecutiveBuyCandles=0; g_consecutiveSellCandles=0;
   g_emergencyStop=false; g_basketActive=false;
   g_basketPeakProfit=0; g_basketLockLevel=0; g_basketTrailActive=false;

   MqlDateTime mdt; TimeToStruct(TimeCurrent(),mdt);
   g_dayStart=StringToTime(StringFormat("%04d.%02d.%02d 00:00",mdt.year,mdt.mon,mdt.day));

   ScanPositions();
   InitLogging();
   LogMessage(2,"Init v4.401. Bal:$"+DoubleToString(g_initialBalance,2));
   Print("[Bot Claude V1] INICIALIZADO v4.401. Balance: $",g_initialBalance);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_handleFast    !=INVALID_HANDLE) IndicatorRelease(g_handleFast);
   if(g_handleSlow    !=INVALID_HANDLE) IndicatorRelease(g_handleSlow);
   if(g_handleRSI     !=INVALID_HANDLE) IndicatorRelease(g_handleRSI);
   if(g_handleATR     !=INVALID_HANDLE) IndicatorRelease(g_handleATR);
   if(g_handleTrailATR!=INVALID_HANDLE) IndicatorRelease(g_handleTrailATR);
   DestroyPanel();
   CloseLogging();
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!SymInfo.RefreshRates()) return;
   g_orderOpenedThisTick=false;

   datetime cb=iTime(_Symbol,PERIOD_CURRENT,0);
   static datetime lc=0;
   if(cb!=lc){ g_buyScoreValid=false; g_sellScoreValid=false; lc=cb; }

   double ceq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(ceq>g_peakEquity) g_peakEquity=ceq;

   if(IsNewDay()){
      g_dailyTargetHit=false; g_dailyFloorHit=false;
      g_tradesToday=0; g_dailyProfit=0;
      g_initialBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      g_peakEquity=g_initialBalance;
      g_lastSignalBarTime=0;
      g_consecutiveLossCount=0; g_cooldownUntilBarTime=0;
      g_consecutiveBuyCandles=0; g_consecutiveSellCandles=0;
      g_emergencyStop=false;
      g_basketPeakProfit=0; g_basketLockLevel=0; g_basketTrailActive=false;
      LogMessage(2,"NEW DAY. Bal:$"+DoubleToString(g_initialBalance,2));
   }

   UpdateConsecutiveCandles();
   ScanPositions();
   CheckDailyLimits();
   CheckEmergencyBrake();
   UpdateTrailing();
   CheckProfitLock();
   CheckTimeStop();
   CheckPositionHealth();
   ManageBasketRecovery();
   ManageEntries();

   datetime now=TimeCurrent();
   if(now-g_lastPanelUpdate>=InpPanelUpdateSeconds){
      UpdatePanelData();
      UpdatePanel();
      g_lastPanelUpdate=now;
   }
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong dtkt=trans.deal; if(dtkt==0) return;
   if(!HistorySelect(0,TimeCurrent())) return;

   for(int i=HistoryDealsTotal()-1;i>=0;i--){
      ulong ht=HistoryDealGetTicket(i);
      if(ht!=dtkt) continue;
      if(HistoryDealGetString(ht,DEAL_SYMBOL)!=_Symbol) continue;
      ulong dm=HistoryDealGetInteger(ht,DEAL_MAGIC);
      if(dm!=(ulong)g_buy.magic&&dm!=(ulong)g_sell.magic&&
         dm!=(ulong)InpMagicHedgeBuy&&dm!=(ulong)InpMagicHedgeSell) continue;
      ENUM_DEAL_ENTRY de=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ht,DEAL_ENTRY);
      if(de!=DEAL_ENTRY_OUT&&de!=DEAL_ENTRY_OUT_BY) continue;
      double tp=HistoryDealGetDouble(ht,DEAL_PROFIT)+HistoryDealGetDouble(ht,DEAL_SWAP);
      TrackConsecutiveLosses(tp);
      g_lastCloseTime=TimeCurrent();
      break;
   }
}
//+------------------------------------------------------------------+