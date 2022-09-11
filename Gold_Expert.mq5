//+------------------------------------------------------------------+
//|                                                  Gold_Expert.mq5 |
//|                                  Copyright 2022, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
// Constants
#property copyright "Copyright 2022, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- RSI horizontal levels in the indicator window
#property RSI_UPPER  70.0
#property RSI_LOWER  30.0

enum OrderType {
   BUY,
   SELL,
   BOTH
};

//--- input parameters
input int      StopLoss=50;         // Stop Loss points
input int      TakeProfit=100;      // Take Profit points
input int      ADX_Period=8;        // Average Directional Movement Period
input int      MA_Period=8;         // Moving Average Period
input int      RSI_Period=14;       // RSI number of periods/bars/candles
input int      EA_Magic=12345;      // Magic number for all orders
input double   Adx_Min=22.0;        // Minimum ADX
input double   lot=0.1;             // Lots to Trade; Volume of the financial instrument we want to trade.
input double   lotMultiplier=2;     // Lot multiplier; increase if stacks
input OrderType   orderType=BUY;      // Order type BUY or SELL or BOTH

int adxHandle; // handle for our ADX indicator
int maHandle;  // handle for our Moving Average indicator
int rsiHandle; // handle for our Relative Strength Index indicator
int macdHandle; //handle for our Moving Average Convergence / Divergence indicator

double iRSIBuffer[];
double macdBuffer[];
double plsDI[], minDI[], adxVal[]; // Dynamic arrays to hold the values of (Directional Indicator) +DI, -DI and ADX values for each bars
double maVal[]; // Dynamic array to hold the values of Moving Average for each bars
double priceClose; // Variable to store the close value of a bar
int STP, TKP;   // To be used for Stop Loss Points & Take Profit Points values

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Get handle for Average Directional Movement indicator
   //    _Symbol means current symbol on the current chart
   //    _Period means the current timeframe
   //    ADX averaging period for calculating the index.
   adxHandle = iADX(_Symbol, _Period, ADX_Period);
   
   // Get handle for Moving Average indicator
   //    _Symbol - is the current chart's symbol 
   //    _Period means the current timeframe
   //    Moving Average averaging period
   //    Shift of the indicator relative to the price chart (0)
   //    Moving average smoothing type (Exponential)
   //    Price used for averaging (close price)
   maHandle = iMA(_Symbol, _Period, MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   // Get handle for Relative Strength Index indicator
   //    _Symbol - is the current chart's symbol 
   //    _Period means the current timeframe
   //    Moving Average averaging period
   //    Price used for averaging (close price)
   rsiHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   
   
   // Ensure adx and ma handles are valid
   if (adxHandle == INVALID_HANDLE || maHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE) {
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
     Let's make sure our arrays values for the Rates, ADX Values and MA values 
     is store serially similar to the timeseries array (0, 1, 2, 3, ...)
   */
   
   ArraySetAsSeries(plsDI,true);
   ArraySetAsSeries(minDI,true);
   ArraySetAsSeries(adxVal,true);
   ArraySetAsSeries(maVal,true);
   ArraySetAsSeries(iRSIBuffer, true);
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
   
   
      
   // mRates[1].time   // Bar 1 Start time
   // mRates[1].open   // Bar 1 Open price
   // mRates[0].high   // Bar 0 (current bar) high price, etc
   
   priceClose = mRates[1].close; // bar 1 close price
   
   // Copy the new values of our indicators to buffers (arrays) using the handle
   /*
       The ADX indicator has three (3) buffers / digits:
         0 - MAIN_LINE,
         1 - PLUSDI_LINE,
         2 - MINUSDI_LINE.
         
       The Moving Average indicator has only one (1) buffer:
         
         0 – MAIN_LINE.
   */
   
   int barsCount = 3;

   // Store ADX values 
   if (CopyBuffer(adxHandle, 0, 0, barsCount, adxVal) < 0 
         || CopyBuffer(adxHandle, 1, 0, barsCount, plsDI) < 0
         || CopyBuffer(adxHandle, 2, 0, barsCount, minDI) < 0) {
      Alert("Error copying ADX indicator Buffers - error:", GetLastError(), "!!");
      return;
   }
   
   // Store Moving Average values
   if (CopyBuffer(maHandle, 0, 0, barsCount, maVal) < 0) {
      Alert("Error copying Moving Average indicator buffer - error:", GetLastError());
      return;
   }

   // Store RSI info into iRSIBuffer
   if (CopyBuffer(rsiHandle, 0, 0, barsCount, iRSIBuffer) < 0) {
      Alert("Error copying to RSI buffer ", GetLastError());
      return;
   }

   double currentRsiValue = NormalizeDouble(iRSIBuffer[0], 2);

   Comment("Current RSI value: " currentRsiValue);
   
   // Do we have positions opened?
   bool isBuyOpened = false;
   bool isSellOpened = false;
   
   if (PositionSelect(_Symbol) == true) { // There is an opened position
      long positionType = PositionGetInteger(POSITION_TYPE);
      if (positionType == POSITION_TYPE_BUY) {
         isBuyOpened = true;
      }else if (positionType == POSITION_TYPE_SELL) {
         isSellOpened = true;
      }
   }
   
   /*
      1. Check for a long/Buy Setup: MA-8 is increasing upwards, 
         previous close above it, ADX > 22, +DI > -DI
   */
   
   bool buyCondition1 = (maVal[0] > maVal[1]) && (maVal[1] > maVal[2]); // MA-8 increasing upwards
   bool buyCondition2 = (priceClose > maVal[1]);   // previousPrice closed above MA-8
   bool buyCondition3 = (adxVal[0] > Adx_Min);     // Current ADX value greater than the minimum value specified
   bool buyCondition4 = (plsDI[0] > minDI[0]);     // +DI greater than -DI
   
   if ((orderType == BUY || orderType == BOTH) && buyCondition1 && buyCondition2
         && buyCondition3 && buyCondition4) {
      if (!isBuyOpened) {
         // Setup and send new order
         mRequest.action = TRADE_ACTION_DEAL;                                // immediate order execution
         mRequest.price = NormalizeDouble(latestPrice.ask, _Digits);          // latest ask price
         // mRequest.sl = NormalizeDouble(latestPrice.ask - STP * _Point, _Digits); // Stop Loss
         mRequest.tp = NormalizeDouble(latestPrice.ask + TKP * _Point, _Digits); // Take Profit
         mRequest.symbol = _Symbol;                                         // currency pair
         mRequest.volume = lot;                                            // number of lots to trade
         mRequest.magic = EA_Magic;                                        // Order Magic Number
         mRequest.type = ORDER_TYPE_BUY;                                     // Buy Order
         mRequest.type_filling = ORDER_FILLING_FOK;                          // Order execution type
         mRequest.deviation=100;                                            // Deviation from current price
         //--- send order
         OrderSend(mRequest, mResult);
         
         if(mResult.retcode==10009 || mResult.retcode==10008) { //Request is completed or order placed
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
   
   bool sellCondition1 = (maVal[0] < maVal[1]) && (maVal[1] < maVal[2]);   // MA-8 decreasing
   bool sellCondition2 = (priceClose < maVal[1]);                          // Previous price closed below MA-8
   bool sellCondition3 = (adxVal[0] > Adx_Min);                            // Current ADX value greater than minimum value specified
   bool sellCondition4 = (plsDI[0] < minDI[0]);                            // -DI greater than +DI
   
   if ((orderType == SELL || orderType == BOTH) && sellCondition1 && sellCondition2
         && sellCondition3 && sellCondition4) {
      if (!isSellOpened) {
         // Setup and send new order
         mRequest.action = TRADE_ACTION_DEAL;                                // immediate order execution
         mRequest.price = NormalizeDouble(latestPrice.bid, _Digits);          // latest bid price
         // mRequest.sl = NormalizeDouble(latestPrice.bid + STP * _Point, _Digits); // Stop Loss
         mRequest.tp = NormalizeDouble(latestPrice.bid - TKP * _Point, _Digits); // Take Profit
         mRequest.symbol = _Symbol;                                         // currency pair
         mRequest.volume = lot;                                            // number of lots to trade
         mRequest.magic = EA_Magic;                                        // Order Magic Number
         mRequest.type = ORDER_TYPE_SELL;                                     // Sell Order
         mRequest.type_filling = ORDER_FILLING_FOK;                          // Order execution type
         mRequest.deviation=100;                                            // Deviation from current price
         //--- send order
         OrderSend(mRequest, mResult);
         
         if (mResult.retcode==10009 || mResult.retcode==10008) { //Request is completed or order placed
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
   
   bool tickChecks() {
      // Do we have enough bars to work with
      if (Bars(_Symbol, _Period) < 60) {
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

   //+------------------------------------------------------------------+
   //| Expert deinitialization function                                 |
   //+------------------------------------------------------------------+
   void OnDeinit(const int reason)
   {
      // Release the handles that were created
      IndicatorRelease(adxHandle);
      IndicatorRelease(maHandle);
      IndicatorRelease(rsiHandle);
      IndicatorRelease(macdHandle);
      
   }
   
}
//+------------------------------------------------------------------+
