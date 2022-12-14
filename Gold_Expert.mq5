//+------------------------------------------------------------------+
//|                                                  Gold_Expert.mq5 |
//|                                  Copyright 2022, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
// Constants
#property copyright "Copyright 2022, Bao Tran"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include "iMaArray.mqh"

enum OrderType {
   BUY,
   SELL,
   BOTH
};

enum Trend {
   UPWARD,  // 0
   DOWNWARD,   // 1
   UNKNOWN  // 2
};

//--- input parameters
input int      StopLoss=150;         // Stop Loss points
input int      TakeProfit=100;      // Take Profit points

input int      RSI_Period=25;        // RSI number of periods/bars/candles
input int      MACD_Period=14;      // MACD number of periods/bars/candles

input int      EA_Magic=12345;      // Magic number for all orders

input double   lot=0.1;             // Lots to Trade; Volume of the financial instrument we want to trade.
//input double   lotMultiplier=2;     // Lot multiplier; increase if stacks

input OrderType   orderType=BUY;      // Order type BUY or SELL or BOTH
input bool     openMultiplePositions=false;  // Whether to have multiple BUY and/or SELL positions

int rsiHandle; // handle for our Relative Strength Index indicator
int macdHandle; //handle for our Moving Average Convergence / Divergence indicator

double rsiBuffer[];
double macdBuffer[];
double macdSignalBuffer[];

int STP, TKP;   // To be used for Stop Loss Points & Take Profit Points values
bool isRsiBelowAvg;  // Keep track of when the RSI is below or above its Average. This is to determine whether they cross.
bool isMacdBelowSignal;

int CROSSED_BARS_RESET = 5;
int RSI_UPPER_LIMIT = 70;
int RSI_LOWER_LIMIT = 30;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{

   macdHandle = iMACD(_Symbol, _Period , 12, 26, MACD_Period, PRICE_CLOSE);

   rsiHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   
   
   // Ensure adx and ma handles are valid
   if (macdHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE) {
      Alert("Error creating handles for indicators - error: ", GetLastError());
   }

   
   //--- Let us handle currency pairs with 5 or 3 digit prices instead of 4
   STP = StopLoss;
   TKP = TakeProfit;
   
   // Digits or Digits() returns the number of decimal digits determining the accuracy of price of the current chart symbol.
   if (_Digits==5 || _Digits==3) {
      STP = STP * 10;
      TKP = TKP * 10;
   }
   
   /*
     Let's make sure our arrays values 
     is store serially similar to the timeseries array (0, 1, 2, 3, ...)
   */

   ArraySetAsSeries(rsiBuffer, true);
   ArraySetAsSeries(macdBuffer, true);
     

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Run when new quote is received. 
//| - Trades are executed on new bars
//+------------------------------------------------------------------+
void OnTick()
{
   // Prechecks are not satisifed
   if (!tickChecks()) {
      return;
   }

   // Define MQL5 Structures to use for our trade
   MqlTick latestPrice;       // Used to get the latest price quotes
   MqlTradeRequest mRequest;  // Used for sending our trade requests
   MqlTradeResult mResult;   // Used to get our trade results
   MqlRates mRates[];          // Used to store the prices, volumes, and spread of each bar
   ZeroMemory(mRequest);      // Initialize the mRequest structure
   
   ArraySetAsSeries(mRates,true);
   
   // Get the latest price quote using SymbolInfoTick. If error alert!
   if (!SymbolInfoTick(_Symbol, latestPrice)) {
      Alert("Error getting the latest price quote - error:", GetLastError());
      return;
   }
   
   // Get latest 3 bars using CopyRates
   if (CopyRates(_Symbol, _Period, 0, 3, mRates) < 0) {
      Alert("Error copying rates/history data - error:",GetLastError(),"!!");
      return;
   } 
      
   Trend trend = determineTrend(mRates);
   
   int barsCount = 60;

    // Store RSI info into rsiBuffer
   if (CopyBuffer(macdHandle, 0, 0, barsCount, macdBuffer) < 0) {
      Alert("Error copying to MACD buffer ", GetLastError());
      return;
   }

   if (CopyBuffer(macdHandle, 1, 0, barsCount, macdSignalBuffer) < 0) {
      Alert("Error copying to MACD Signal buffer ", GetLastError());
      return;
   }

   // Store RSI info into rsiBuffer
   if (CopyBuffer(rsiHandle, 0, 0, barsCount, rsiBuffer) < 0) {
      Alert("Error copying to RSI buffer ", GetLastError());
      return;
   }

   double currentRsiValue = NormalizeDouble(rsiBuffer[0], 2);
   double currentRsiAverage = NormalizeDouble(iMAOnArray(rsiBuffer, 15, 5, MODE_SMA, 0), 2);
   
   bool isRsiCrossedAvg = false;
   
   if (isRsiBelowAvg == true && currentRsiValue > currentRsiAverage) {
      isRsiCrossedAvg = true;
   } else if (isRsiBelowAvg == false && currentRsiValue < currentRsiAverage) {
      isRsiCrossedAvg = true;
   }
   
   // used to determine when the lines crossed.
   if (currentRsiValue > currentRsiAverage) {
      isRsiBelowAvg = false;
   } else if (currentRsiValue < currentRsiAverage) {
      isRsiBelowAvg = true;
   }
   
   Comment("Current RSI value: ", currentRsiValue,
   "\n RSI Average: ", currentRsiAverage,
   "\n isRsiBelowAvg: ", isRsiBelowAvg,
   "\n isRsiCrossedAvg: ", isRsiCrossedAvg,
   "\n Current Trend: ", trend);

   double currentMacdValue = NormalizeDouble(macdBuffer[0], 2);
   double currentSignalValue = NormalizeDouble(macdSignalBuffer[0], 2);

   if (currentMacdValue > currentSignalValue) {
      isMacdBelowSignal = false;
   } else if (currentMacdValue < currentSignalValue) {
      isMacdBelowSignal = true;
   }
   
   // Do we have positions opened?
   bool isBuyOpened = false;
   bool isSellOpened = false;
   
   if (openMultiplePositions == false) {
      if (PositionSelect(_Symbol) == true) { // There is an opened position
         long positionType = PositionGetInteger(POSITION_TYPE);
         if (positionType == POSITION_TYPE_BUY) {
            isBuyOpened = true;
         } else if (positionType == POSITION_TYPE_SELL) {
            isSellOpened = true;
         }
      }
   }

   bool isOversold = currentRsiValue < RSI_LOWER_LIMIT;
   // bool buyConditions = isOversold && isRsiCrossedAvg && !isMacdBelowSignal;
   bool buyConditions = trend == UPWARD && !isRsiBelowAvg && !isMacdBelowSignal;
   
   if ((orderType == BUY || orderType == BOTH) 
         && buyConditions) {
      if (!isBuyOpened) {
         mRequest = getTradeRequest(BUY, latestPrice);

         OrderSend(mRequest, mResult);
         
         if (mResult.retcode == 10009 || mResult.retcode == 10008) { //Request is completed or order placed
            Alert("A BUY order has been successfully placed with Ticket#:", mResult.order,"!!");
            
         } else {
            Alert("The BUY order request could not be completed -error:", GetLastError());
            ResetLastError();
            return;
         }
      } else {
         Alert("We already have a Buy Position!!!"); 
         return;    // Don't open a new Buy Position
      }
   }
   
   bool isOverbought = currentRsiValue > RSI_UPPER_LIMIT;
   // bool sellConditions = isOverbought && isRsiCrossedAvg && isMacdBelowSignal;
   bool sellConditions = trend == DOWNWARD && isRsiBelowAvg && isMacdBelowSignal;
   
   if ((orderType == SELL || orderType == BOTH) 
         && sellConditions) {
      if (!isSellOpened) {
         mRequest = getTradeRequest(SELL, latestPrice);

         OrderSend(mRequest, mResult);
         
         if (mResult.retcode == 10009 || mResult.retcode == 10008) { //Request is completed or order placed
            Alert("A SELL order has been successfully placed with Ticket#:", mResult.order,"!!");
            
         } else {
            Alert("The SELL order request could not be completed -error:", GetLastError());
            ResetLastError();
            return;
         }
      } else {
         Alert("We already have a Sell position open!"); 
         return;
      }
   }
   
}

//+------------------------------------------------------------------+
//| Utility functions                                                |
//+------------------------------------------------------------------+

bool tickChecks() {
   // Do we have enough bars to work with
   if (Bars(_Symbol, _Period) <= 60) {
      Alert("Less than 60 bars on chart, EA will exit!");
      return false;
   }
   
   // Keep track of the bar time.
   static datetime oldTime;   // declared as static so it is retained in memory for the next onTick call. Shouldn't this be outside as a global variable??
   datetime newTime[1];
   bool isNewBar = false;
   
   // Obtain the newTime of the current bar
   int copied = CopyTime(_Symbol, _Period, 0, 1, newTime);
   if (copied > 0) { // Ensure copy function worked
      if (oldTime != newTime[0]) { // If old time isn't equal to the new time
         isNewBar = true;
         if (MQL5InfoInteger(MQL5_DEBUGGING)) Print("We have new bar here ",newTime[0], " old time was ", oldTime);
         oldTime = newTime[0];
      }
   } else {
      Alert("Error copying historical times data, error =", GetLastError());
      ResetLastError();
      return false;
   }
   
   // Should only check for new trade if we have a new bar
   if (!isNewBar) {
      return false;
   }

   return true;
}

MqlTradeRequest getTradeRequest(OrderType type, MqlTick &latestPrice) {
   MqlTradeRequest mRequest;
   ZeroMemory(mRequest);      // Initialize the mRequest structure

    // Setup and send new order
   mRequest.action = TRADE_ACTION_DEAL;                                // immediate order execution
   if (type == BUY) {
      mRequest.price = NormalizeDouble(latestPrice.ask, _Digits);          // latest ask price
      mRequest.sl = NormalizeDouble(latestPrice.ask - STP * _Point, _Digits); // Stop Loss
      mRequest.tp = NormalizeDouble(latestPrice.ask + TKP * _Point, _Digits); // Take Profit
   } else if (type == SELL) {
      mRequest.price = NormalizeDouble(latestPrice.bid, _Digits);          // latest bid price
      mRequest.sl = NormalizeDouble(latestPrice.bid + STP * _Point, _Digits); // Stop Loss
      mRequest.tp = NormalizeDouble(latestPrice.bid - TKP * _Point, _Digits); // Take Profit
   }
   
   mRequest.symbol = _Symbol;                                         // currency pair

   mRequest.volume = lot;                                            // number of lots to trade

   mRequest.magic = EA_Magic;                                        // Expert unique identifier 

   if (type == BUY) {
      mRequest.type = ORDER_TYPE_BUY;
   } else if (type == SELL) {
      mRequest.type = ORDER_TYPE_SELL;
   }
   
   mRequest.type_filling = ORDER_FILLING_FOK;                          // Order execution type
   mRequest.deviation=100;  

   return mRequest;
}

//Determine trend by looking at the last 3 bars closed prices
Trend determineTrend(MqlRates &mRates[]) {
   // mRates[1].time   // Bar 1 Start time
   // mRates[1].open   // Bar 1 Open price
   // mRates[0].high   // Bar 0 (current bar) high price, etc

   Trend trend = UNKNOWN;
   
   if (mRates[0].close > mRates[1].close && mRates[1].close > mRates[2].close) {
      trend = UPWARD;
   }

   if (mRates[0].close < mRates[1].close && mRates[1].close < mRates[2].close) {
      trend = DOWNWARD;
   }

   return trend;
}

/*
   Loop through open orders and count based on the OrderType
*/
int orderCount(int positionType)
{
   int count = 0;
   int total = PositionsTotal();
   
   for(int i = total-1; i >= 0; i--) {
      if (PositionSelect(_Symbol) == false) break;
     
      if (OrderType() == positionType) count = count+1;     
   }
 
   
    return(count);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
      // Release the handles that were created
   IndicatorRelease(rsiHandle);
   IndicatorRelease(macdHandle);
}
//+------------------------------------------------------------------+