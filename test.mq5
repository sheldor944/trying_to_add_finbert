//+------------------------------------------------------------------+
//|                                               PredictionTrader.mq5 |
//+------------------------------------------------------------------+
#property copyright "This is for debugging purpouse"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

// Include trade functions
#include <Trade/Trade.mqh>
#include <JAson.mqh>

// Input Parameters
input string   API_URL = "http://127.0.0.1:8000/api/v1/prediction";  // Prediction API URL
input double   TRADE_VOLUME = 0.1;                        // Trading volume
input int      MAGIC_NUMBER = 12345;                       // EA identifier

// Global Variables
CTrade  trade;                    // Trading object
string  g_symbol;                 // Current symbol
ENUM_TIMEFRAMES g_tf;            // Timeframe
datetime g_lastPredictionTime;    // Last prediction time
bool g_isInitialized;            // Initialization flag

//+------------------------------------------------------------------+
//| Structures for data handling                                       |
//+------------------------------------------------------------------+
struct PredictionData
{
    datetime predictionTime;    // When the prediction was made
    double predictedValue;      // Predicted price
    bool predictionDirection;   // true for bullish (buy), false for bearish (sell)
    bool isValid;              // Indicates if prediction is valid
    string error;              // Error message if any
};

//---
//====================================
//---
//+------------------------------------------------------------------+
//| Include the HashMap library                                       |
//+------------------------------------------------------------------+
#include <Generic\HashMap.mqh>

//+------------------------------------------------------------------+
//| Define key and value types for our position map                   |
//+------------------------------------------------------------------+
// We'll use string as key (userId) and ulong as value (position ticket)
#include <Generic\Interfaces\IComparable.mqh>
#include <Generic\Interfaces\IEqualityComparer.mqh>

//+------------------------------------------------------------------+
//| Custom string hash code function                                  |
//+------------------------------------------------------------------+
int StringGetHashCode(const string &str)
{
    int hash = 0;
    int length = StringLen(str);
    
    for(int i = 0; i < length; i++)
    {
        hash = 31 * hash + StringGetCharacter(str, i);
    }
    
    return hash;
}

//+------------------------------------------------------------------+
//| String equality comparer for HashMap                              |
//+------------------------------------------------------------------+
class CStringEqualityComparer : public IEqualityComparer<string>
{
public:
    bool Equals(string x, string y) { return (x == y); }
    int HashCode(string x) { return StringGetHashCode(x); }
};

//+------------------------------------------------------------------+
//| Global variables for position tracking                            |
//+------------------------------------------------------------------+
CHashMap<string, ulong>* g_positionMap; // Maps user IDs to position tickets
CStringEqualityComparer* g_stringComparer;

//==============================
struct MarketData
{
    datetime time;
    double price;
    bool isValid;
    string error;
};



//+------------------------------------------------------------------+
//| Function to add position to the map                               |
//+------------------------------------------------------------------+
void AddPositionToMap(string userId, ulong ticket)
{
    if(g_positionMap == NULL)
    {
        Print("Error: Position map not initialized");
        return;
    }
    
    // Remove any existing mapping for this user
    if(g_positionMap.ContainsKey(userId))
    {
        ulong oldTicket;
        g_positionMap.TryGetValue(userId, oldTicket);
        g_positionMap.Remove(userId);
        Print("Removed old position mapping for user ID: ", userId, ", ticket: ", oldTicket);
    }
    
    // Add new mapping
    g_positionMap.Add(userId, ticket);
    Print("Added position #", ticket, " for user ID: ", userId, " to map. Total positions: ", g_positionMap.Count());
}

//+------------------------------------------------------------------+
//| Function to remove position from the map                          |
//+------------------------------------------------------------------+
void RemovePositionByUserId(string userId)
{
    if(g_positionMap == NULL)
    {
        Print("Error: Position map not initialized");
        return;
    }
    
    if(g_positionMap.ContainsKey(userId))
    {
        ulong ticket;
        g_positionMap.TryGetValue(userId, ticket);
        g_positionMap.Remove(userId);
        Print("Removed position for user ID: ", userId, ", ticket: ", ticket, " from map. Remaining positions: ", g_positionMap.Count());
    }
}

//+------------------------------------------------------------------+
//| Function to find position ticket by user ID                       |
//+------------------------------------------------------------------+
ulong FindPositionTicketByUserId(string userId)
{
    if(g_positionMap == NULL)
    {
        Print("Error: Position map not initialized");
        return 0;
    }
    
    ulong ticket = 0;
    if(g_positionMap.TryGetValue(userId, ticket))
    {
        return ticket;
    }
    
    return 0; // Not found
}

///============

//+------------------------------------------------------------------+
//| Function to create trade record in backend                         |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Function to create trade record in backend                         |
//+------------------------------------------------------------------+



bool CreateTradeRecord(string userId, string symbol, double price, double volume, bool isBuy, string handlerId, string ticket)
{
    string headers = "Content-Type: application/json\r\n";
    char post[], result[];
    string resultHeaders;
    int res;
    
    // Create JSON string directly
    string postData = "{";
    postData += "\"user_id\":\"" + userId + "\",";
    postData += "\"stock_id\":\"ade11ce0-a353-427d-9ae7-26b948454eab\",";
    postData += "\"trade_start_price\":" + DoubleToString(price, 8) + ",";
    postData += "\"quantity\":" + DoubleToString(volume, 8) + ",";
    //postData += "\"trade_start_date\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";
    postData += "\"trade_type\":\"" + (isBuy ? "LONG" : "SHORT") + "\",";
    postData += "\"is_Automated\":true,";
    postData += "\"trade_done_by\":\"Automated\","; // Added comma here
    postData += "\"trade_ticket\":\"" + ticket + "\""; // Added ticket
    postData += "}";
    
    // Convert to char array and remove null terminator
    StringToCharArray(postData, post, 0, StringLen(postData), CP_UTF8);
    
    // Print debug info
    Print("Sending JSON: ", postData);
    Print("JSON length: ", StringLen(postData));
    Print("Array size: ", ArraySize(post));
    
    // API endpoint
    string URL = "http://127.0.0.1:8000/api/v1/trade/automated";
    
    ResetLastError();
    res = WebRequest("POST", URL, headers, 10000, post, result, resultHeaders);
   
    if(res != 201)
    {
        int errorCode = GetLastError();
        Print("Failed to create trade record. Error: ", errorCode);
        Print("Server response: ", CharArrayToString(result, 0, -1, CP_UTF8));
        Print("Response headers: ", resultHeaders);
        return false;
    }
    
    // Convert result to string
    string resultStr = CharArrayToString(result, 0, -1, CP_UTF8);
    Print("Trade record created successfully: ", resultStr);
    
    return true;
}
//+------------------------------------------------------------------+
//| Structure to store automated account handler data                  |
//+------------------------------------------------------------------+
struct AutomatedAccountHandler
{
    string id;                  // UUID as string
    string user_id; // UUID as string
    string symbol;              // Trading symbol
    datetime start_time;        // Start time
    datetime end_time;          // End time
    double profit_lower_bound;  // Profit lower bound
    double profit_upper_bound;  // Profit upper bound
    double profit;              // Current profit
    string status;              // Status
    double balance;             // Balance
};

//+------------------------------------------------------------------+
//| Global array to store subscribed users                             |
//+------------------------------------------------------------------+
#define MAX_HANDLERS 100
AutomatedAccountHandler g_handlers[MAX_HANDLERS];
int g_handlersCount = 0;

//+------------------------------------------------------------------+
//| Function to check if handler exists in array by ID                 |
//+------------------------------------------------------------------+
bool HandlerExists(string id)
{
    for(int i = 0; i < g_handlersCount; i++)
    {
        if(g_handlers[i].id == id)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Function to update the handlers array from backend                 |
//+------------------------------------------------------------------+
void UpdateHandlersArray()
{
    string cookie=NULL, headers="";
    char post[], result[];
    int res;
    string URL = "http://127.0.0.1:8000/api/v1/all_automated_handler"; // API endpoint
    
    ResetLastError();
    res = WebRequest("GET", URL, cookie, NULL, 20000, post, 0, result, headers);
    
    if(res != 200)
    {
        int errorCode = GetLastError();
        Print("Failed to get automated handlers. Error: ", errorCode);
        return;
    }
    
    // Convert result to string
    string resultStr = CharArrayToString(result);
    Print("API Response (Handlers): ", resultStr);
    
    // Parse JSON response
    CJAVal json;
    if(!json.Deserialize(resultStr))
    {
        Print("Failed to parse JSON response for handlers");
        return;
    }
    
    // Process each handler from the response
    for(int i = 0; i < json.Size(); i++)
    {
        CJAVal item = json[i];
        string handlerId = item["id"].ToStr();
        
        // Check if handler already exists in our array
        if(!HandlerExists(handlerId) && g_handlersCount < MAX_HANDLERS)
        {
            // Add new handler to array
            g_handlers[g_handlersCount].id = handlerId;
            g_handlers[g_handlersCount].user_id = item["user_id"].ToStr();
            g_handlers[g_handlersCount].symbol = item["symbol"].ToStr();
            g_handlers[g_handlersCount].start_time = StringToTime(item["start_time"].ToStr());
            g_handlers[g_handlersCount].end_time = StringToTime(item["end_time"].ToStr());
            g_handlers[g_handlersCount].profit_lower_bound = item["profit_lower_bound"].ToDbl();
            g_handlers[g_handlersCount].profit_upper_bound = item["profit_upper_bound"].ToDbl();
            g_handlers[g_handlersCount].profit = item["profit"].ToDbl();
            g_handlers[g_handlersCount].status = item["status"].ToStr();
            g_handlers[g_handlersCount].balance = item["balance"].ToDbl();
            
            Print("New handler added: ", handlerId, ", Symbol: ", g_handlers[g_handlersCount].symbol);
            g_handlersCount++;
        }
    }
    
    Print("Total handlers: ", g_handlersCount);
}

//+------------------------------------------------------------------+
//| Function to check if a symbol is being handled                     |
//+------------------------------------------------------------------+
bool IsSymbolHandled(string symbol)
{
    for(int i = 0; i < g_handlersCount; i++)
    {
        if(g_handlers[i].symbol == symbol && g_handlers[i].status == "active")
        {
            return true;
        }
    }
    return false;
}


//+------------------------------------------------------------------+
//| Function to check if a user has an open position                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Function to check if a user has an open position                   |
//+------------------------------------------------------------------+
bool HasOpenPositionForUser(string user_id)
{
    if(g_positionMap == NULL)
    {
        Print("Error: Position map not initialized");
        return false;
    }
    
    // First check our map
    ulong ticket = 0;
    Print("Ticket is: ", ticket);
    if(g_positionMap.TryGetValue(user_id, ticket))
    {
         Print("Ticket is: ",ticket);
        // Verify the position still exists
        if(PositionSelectByTicket(ticket))
        {
            Print("Position found in map for user ID: ", user_id, ", ticket: ", ticket);
            return true;
        }
        else
        {
            // Position no longer exists, remove from map
            Print("Position #", ticket, " no longer exists, removing from map");
            g_positionMap.Remove(user_id);
        }
    }
    
    // If not found in map, check all positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong posTicket = PositionGetTicket(i);
        if(posTicket <= 0) continue;
        
        if(!PositionSelectByTicket(posTicket)) continue;
        
        if(PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
        {
            string posComment = PositionGetString(POSITION_COMMENT);
            
            // Check if this position's comment is part of the user ID
            if(StringFind(user_id, posComment) != -1)
            {
                // Found a match, add to our map for future reference
                AddPositionToMap(user_id, posTicket);
                Print("Found position #", posTicket, " with matching comment for user ID: ", user_id);
                return true;
            }
        }
    }
    
    Print("No position found for user ID: ", user_id);
    return false;
}
//+------------------------------------------------------------------+
//| Function to open a new position with handler ID as comment         |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Function to open a new position with user ID as comment            |
//+------------------------------------------------------------------+
bool OpenPositionForHandler(PredictionData &prediction,bool isBuy, double volume, double SL, double TP, string user_id, double balance)
{
   
    double price = isBuy ? SymbolInfoDouble(g_symbol, SYMBOL_ASK) : SymbolInfoDouble(g_symbol, SYMBOL_BID);
    Print("Price is: ", price);
    Print("Prediction price is: ", prediction.predictedValue);
    if(prediction.predictedValue > price){
          Print("prediction value > price so buying ");
          volume = int(balance/price);
          volume /=100;
          trade.SetExpertMagicNumber(MAGIC_NUMBER);
          TP = prediction.predictedValue ;
         
          //SL = price - 1; 
          
          // Use a shortened version of the user ID as comment if needed
          string comment = user_id;
          if(StringLen(user_id) > 31) // MT5 has a limit on comment length
          {
              comment = StringSubstr(user_id, 0, 31);
          }
          
          bool result = isBuy ? 
              trade.Buy(volume, g_symbol, price, SL, TP, comment) :
              trade.Sell(volume, g_symbol, price, SL, TP, comment);
              
          if(!result)
          {
              Print("Trade execution failed for user ID: ", user_id, ", Error: ", GetLastError());
              return false;
          }
          else
          {
              // Get the ticket of the newly opened position
              ulong ticket = trade.ResultOrder();
              
              // Add to our position map
              if(g_positionMap != NULL)
              {
                  AddPositionToMap(user_id, ticket);
              }
              
              Print("Trade opened successfully for user ID: ", user_id, ", at price: ", price, ", ticket: ", ticket);
              
              // Create trade record in backend with ticket
              if(!CreateTradeRecord(user_id, g_symbol, price, volume, isBuy, user_id, IntegerToString(ticket)))
              {
                  Print("Warning: Trade executed but failed to create record in backend");
              }
          }
          
          return result;
          
    }
    else{
         return false;
     }
    /*
    trade.SetExpertMagicNumber(MAGIC_NUMBER);
    TP = price + 10.35;
    
    // Use a shortened version of the user ID as comment if needed
    string comment = user_id;
    if(StringLen(user_id) > 31) // MT5 has a limit on comment length
    {
        comment = StringSubstr(user_id, 0, 31);
    }
    
    bool result = isBuy ? 
        trade.Buy(volume, g_symbol, price, SL, TP, comment) :
        trade.Sell(volume, g_symbol, price, SL, TP, comment);
        
    if(!result)
    {
        Print("Trade execution failed for user ID: ", user_id, ", Error: ", GetLastError());
        return false;
    }
    else
    {
        // Get the ticket of the newly opened position
        ulong ticket = trade.ResultOrder();
        
        // Add to our position map
        if(g_positionMap != NULL)
        {
            AddPositionToMap(user_id, ticket);
        }
        
        Print("Trade opened successfully for user ID: ", user_id, ", at price: ", price, ", ticket: ", ticket);
        
        // Create trade record in backend with ticket
        if(!CreateTradeRecord(user_id, g_symbol, price, volume, isBuy, user_id, IntegerToString(ticket)))
        {
            Print("Warning: Trade executed but failed to create record in backend");
        }
    }
    
    return result;
    */
}
//---
// Trade close 
//---

void HandleExistingPositionForUser(string user_id, PredictionData &prediction, MarketData &current)
{
    if(g_positionMap == NULL)
    {
        Print("Error: Position map not initialized");
        return;
    }
    
    // Get the position ticket for this user
    ulong ticket = FindPositionTicketByUserId(user_id);
    if(ticket == 0)
    {
        Print("No position found for user ID: ", user_id);
        return;
    }
    
    // Select the position
    if(!PositionSelectByTicket(ticket))
    {
        Print("Error selecting position #", ticket);
        return;
    }
    
    ENUM_POSITION_TYPE currentPosType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    
    // Close position based on prediction
    if(currentPosType == POSITION_TYPE_BUY)
    {    
        double midValue = 0;
        if(positionOpenPrice < prediction.predictedValue)
        {
            midValue = (prediction.predictedValue + positionOpenPrice) / 2;
        }
        
        // First closing condition
        if(positionOpenPrice + 0.1 < current.price)
        {
            Print("Closing BUY position #", ticket, " for user ", user_id, " based on profit target");
            trade.PositionClose(ticket);
            RemovePositionByUserId(user_id);
        }
        // Second closing condition
        else if(prediction.predictedValue > current.price && 
                positionOpenPrice < current.price && 
                prediction.predictionDirection == false)
        {
            Print("Closing BUY position #", ticket, " for user ", user_id, " based on prediction reversal");
            trade.PositionClose(ticket);
            RemovePositionByUserId(user_id);
        }
    }
}


//+------------------------------------------------------------------+
//| TradeTransaction function                                         |
//+------------------------------------------------------------------+

bool RecordTradeClose(string userId, string symbol, double closePrice, double profit, string ticket)
{
    string headers = "Content-Type: application/json\r\n";
    char post[], result[];
    string resultHeaders;
    int res;
    
    // Create JSON string directly
    string postData = "{";
    postData += "\"user_id\":\"" + userId + "\",";
    postData += "\"trade_end_price\":" + DoubleToString(closePrice, 8) + ",";
    postData += "\"trade_ticket\":\"" + ticket + "\",";
    postData += "\"profit\":" + DoubleToString(profit, 8);
    postData += "}";
    
    // Convert to char array and remove null terminator
    StringToCharArray(postData, post, 0, StringLen(postData), CP_UTF8);
    
    // Print debug info
    Print("Sending JSON for trade close: ", postData);
    Print("JSON length: ", StringLen(postData));
    Print("Array size: ", ArraySize(post));
    
    // API endpoint for PUT request
    string URL = "http://127.0.0.1:8000/api/v1/trade_close/automated";
    
    ResetLastError();
    res = WebRequest("PUT", URL, headers, 10000, post, result, resultHeaders);
   
    if(res != 200) // Usually PUT returns 200 OK
    {
        int errorCode = GetLastError();
        Print("Failed to record trade close. Error: ", errorCode);
        Print("Server response: ", CharArrayToString(result, 0, -1, CP_UTF8));
        Print("Response headers: ", resultHeaders);
        return false;
    }
    
    // Convert result to string
    string resultStr = CharArrayToString(result, 0, -1, CP_UTF8);
    Print("Trade close recorded successfully: ", resultStr);
    
    return true;
}
//---
//---
//---

void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    // Check if this is a position close event
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        // Get the deal ticket
        ulong dealTicket = trans.deal;
        
        // Select the deal in history
        if(HistoryDealSelect(dealTicket))
        {
            // Check if this is a closing deal
            if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT ||
               HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT_BY)
            {
                // Get position details
                ulong posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
                double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                datetime closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
                string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
                
                Print("DEBUG ==================================");
                Print("Position #", posTicket, " closed with profit: ", profit);
                Print("Close price: ", closePrice);
                Print("Close time: ", TimeToString(closeTime));
                Print("Comment: ", comment);
                
                // Get the original position to find the user ID
                long positionMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
                
                // Find the opening deal for this position
                if(positionMagic == MAGIC_NUMBER)
                {
                    // First, try to find the user ID from our position map
                    string userId = "";
                    
                    // We need to search through all handlers to find which one has this position ticket
                    for(int i = 0; i < g_handlersCount; i++)
                    {
                        string currentUserId = g_handlers[i].user_id;
                        ulong currentTicket = FindPositionTicketByUserId(currentUserId);
                        
                        if(currentTicket == posTicket)
                        {
                            userId = currentUserId;
                            Print("Found user ID in map for position #", posTicket, ": ", userId);
                            
                            // Remove this entry from the map since position is now closed
                            RemovePositionByUserId(userId);
                            Print("Removed position #", posTicket, " from map for user ID: ", userId);
                            
                            // Record the trade close with the full user ID
                            RecordTradeClose(userId, symbol, closePrice, profit, IntegerToString(posTicket));
                            break;
                        }
                    }
                    
                    // If we didn't find the user ID in our map, try to get it from the opening deal comment
                    if(userId == "")
                    {
                        Print("User ID not found in map, searching in history...");
                        
                        // Search through history for the opening deal
                        HistorySelect(0, TimeCurrent());
                        int totalDeals = HistoryDealsTotal();
                        
                        for(int i = 0; i < totalDeals; i++)
                        {
                            ulong openDealTicket = HistoryDealGetTicket(i);
                            
                            // Check if this deal is related to our position
                            if(HistoryDealGetInteger(openDealTicket, DEAL_POSITION_ID) == posTicket &&
                               HistoryDealGetInteger(openDealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
                            {
                                // This is the opening deal, get the original comment (user ID)
                                string commentUserId = HistoryDealGetString(openDealTicket, DEAL_COMMENT);
                                Print("Found original comment in history: ", commentUserId);
                                
                                // Now we need to find the full user ID from our handlers array
                                for(int j = 0; j < g_handlersCount; j++)
                                {
                                    // Check if the shortened user ID is part of the full user ID
                                    if(StringFind(g_handlers[j].user_id, commentUserId) >= 0)
                                    {
                                        userId = g_handlers[j].user_id;
                                        Print("Matched shortened comment to full user ID: ", userId);
                                        
                                        // Record the trade close with the full user ID
                                        RecordTradeClose(userId, symbol, closePrice, profit, IntegerToString(posTicket));
                                        break;
                                    }
                                }
                                
                                if(userId == "")
                                {
                                    // If we still couldn't find a match, use the comment as is
                                    Print("No match found in handlers, using comment as user ID");
                                    RecordTradeClose(commentUserId, symbol, closePrice, profit, IntegerToString(posTicket));
                                }
                                
                                break;
                            }
                        }
                    }
                    
                    if(userId == "")
                    {
                        Print("Warning: Could not find user ID for closed position #", posTicket);
                    }
                }
            }
        }
    }
}
bool IsHandlerValid(datetime endTime)
{
    datetime currentTime = TimeCurrent() + (6 * 3600); // Adding 6 hours (6 * 3600 seconds)
    Print("Current time (UTC+6) is: ", TimeToString(currentTime, TIME_DATE|TIME_SECONDS));
    Print("End time is: ", TimeToString(endTime, TIME_DATE|TIME_SECONDS));
    return (endTime > currentTime);
}
///============

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
    // Clean up position map
    if(g_positionMap != NULL)
    {
        delete g_positionMap;
        g_positionMap = NULL;
    }
    
    if(g_stringComparer != NULL)
    {
        delete g_stringComparer;
        g_stringComparer = NULL;
    }
    
    Print("Position map cleaned up");
}
//+------------------------------------------------------------------+
//| Function to get prediction from API                                |

//+------------------------------------------------------------------+


PredictionData GetPrediction()
{
    PredictionData prediction;
    prediction.isValid = false;
    
    string cookie=NULL, headers="", apikey="your api key";
    char post[],result[];
    int res;
    string URL = "http://127.0.0.1:8000/api/v1/current_prediction"; // Rest API address
    string resultStr;
    
    ResetLastError(); // Reset last error
    res = WebRequest("GET", URL, cookie, NULL, 20000, post, 0, result, headers);
    
    // Check for WebRequest errors
    if(res != 200) // HTTP 200 is success
    {
        int errorCode = GetLastError();
        
        // Specific error handling
        switch(errorCode)
        {
            case 4014: // No connection to server
                prediction.error = "No internet connection or server unreachable";
                break;
            case 4015: // Unable to connect to server
                prediction.error = "Unable to connect to prediction server";
                break;
            case 5200: // Invalid URL
                prediction.error = "Invalid API URL";
                break;
            case 0:    // No error code but response not 200
                prediction.error = "API returned status: " + IntegerToString(res);
                break;
            default:
                prediction.error = "WebRequest failed. Error: " + IntegerToString(errorCode);
        }
        
        Print(prediction.error);
        return prediction;
    }
    
    // Convert result to string
    resultStr = CharArrayToString(result);
    Print("API Response: ", resultStr);
    
    // Parse JSON response
    CJAVal json;
    if(!json.Deserialize(resultStr))
    {
        prediction.error = "Failed to parse JSON response";
        Print(prediction.error);
        return prediction;
    }
    
    // Check if the response is an array with at least one element
    if( json.Size() == 0)
    {
        prediction.error = "Invalid response format - expected array with data";
        Print(prediction.error);
        return prediction;
    }
    
    
    // Extract first element from the array
    CJAVal firstItem = json[0];
    
    // Extract prediction data from JSON
   // prediction.predictionTime = TimeCurrent(); // Current server time
   // prediction.symbol = firstItem["symbol"].ToStr();
    prediction.predictedValue = firstItem["closing_price"].ToDbl();
    prediction.predictionDirection = firstItem["prediction_direction"].ToBool();
    
    // Optionally parse the date from API if needed
    string apiDate = firstItem["date"].ToStr();
    prediction.predictionTime = StringToTime(apiDate);
    
    prediction.isValid = true;
    
    return prediction;
}
//+------------------------------------------------------------------+
//| Function to get current market data                                |
//+------------------------------------------------------------------+
MarketData GetCurrentMarketData()
{
    MarketData data;
    
    data.price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
    data.time = TimeCurrent();
    data.isValid = (data.price > 0);
    
    if(!data.isValid)
    {
        data.error = "Failed to get current market data";
    }
    
    return data;
}

//+------------------------------------------------------------------+
//| Function to check if we have an open position                      |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) == g_symbol && 
           PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
        {
            Print("There is some position");
            return true;
        }
    }
    Print("There is no position ");
    return false;
}

//+------------------------------------------------------------------+
//| Function to get current position type                              |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE GetCurrentPositionType()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) == g_symbol && 
           PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
        {
            return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        }
    }
    return WRONG_VALUE;
}

//+------------------------------------------------------------------+
//| Function to close all positions                                    |
//+------------------------------------------------------------------+
bool CloseAllPositions()
{
    bool result = true;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) == g_symbol && 
           PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
        {
            if(!trade.PositionClose(ticket))
            {
                Print("Error closing position ", ticket, ": ", GetLastError());
                result = false;
            }
        }
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Function to open a new position                                    |
//+------------------------------------------------------------------+
bool OpenPosition(bool isBuy, double volume, double SL, double TP)
{
    double price = isBuy ? SymbolInfoDouble(g_symbol, SYMBOL_ASK) : SymbolInfoDouble(g_symbol, SYMBOL_BID);
    
    bool result = isBuy ? 
        trade.Buy(volume, g_symbol, price, SL, TP, "Prediction Buy") :  // No SL/TP
        trade.Sell(volume, g_symbol, price, 0, 0, "Prediction Sell"); // No SL/TP
        
    if(!result)
    {
        Print("Trade execution failed. Error: ", GetLastError());
    }
    else
    {
        Print("Trade opened successfully at price: ", price);
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Function to handle existing position                               |
//+------------------------------------------------------------------+
void HandleExistingPosition(PredictionData &prediction, MarketData &current)
{
   // if(prediction.predictionTime < current.time)
    //{
     //   Print("Waiting for new prediction...");
       // return;
   // }
    
    ENUM_POSITION_TYPE currentPosType = GetCurrentPositionType();
    double positionOpenPrice = 0;
    
    // Get position open price
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) == g_symbol && 
           PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
        {
            positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            break;
        }
    }
    
    // Close position based on prediction
    if(currentPosType == POSITION_TYPE_BUY)
    {    
        //if (positionOpenPrice < current.price )//---
        //prediction_price > current_price and trade.trade_start_price < current_price and prediction.prediction_direction == False:
        double midValue = 0;
        if(positionOpenPrice < prediction.predictedValue){
            midValue = (prediction.predictedValue + positionOpenPrice) /2 ;
        }
        if(positionOpenPrice + 0.1 < (current.price))
        //if(prediction.predictedValue < current.price && positionOpenPrice < current.price + 0.1)
        {
            Print("Closing BUY position based on prediction");
            CloseAllPositions();
        }
        else if(prediction.predictedValue > current.price && positionOpenPrice  < (current.price) && prediction.predictionDirection == false)
        {
            Print("Closing Buy postion based on prediction in the second condition");
            CloseAllPositions();
        }
    }
}

//+------------------------------------------------------------------+
//| Function to handle new position opportunity                        |
//+------------------------------------------------------------------+
void HandleNewPosition(PredictionData &prediction, MarketData &current, double &SL, double &TP)
{
      
    Print("What ever the prediction just buying to test");
    OpenPosition(true,TRADE_VOLUME, SL, TP);
    /*
    Print("the prediction directions is: ",prediction.predictionDirection)
    if(prediction.predictionDirection) // True for buy signal
    {
         Print("Prediction direction is true");
        if(prediction.predictedValue > current.price)
        {
            if(OpenPosition(true, TRADE_VOLUME))
            {
                Print("Successfully opened BUY position");
                Print("Entry Price: ", current.price);
                Print("Predicted Target: ", prediction.predictedValue);
            }
        }
    }
    */
}

void checkForAPi(){
   string cookie=NULL, headers="", apikey="your api key",
   value1="value 1", value2="value 2";
   char post[],result[];
   int res;
   string URL   =  "http://127.0.0.1:8000/api/v1/prediction"; // Rest API address
   
   ResetLastError(); // Reset ast error
   // HTTP request via MQL Webrequest, GET method with apikey, value1, and value2 and 2000 millisecond timeout 
   res=WebRequest("GET", URL, cookie, NULL, 20000, post, 0, result, headers);
   if(res==-1) // WebRequest error handling
    {
       int error =  GetLastError();
       if(error==4060) Print("Webrequest Error ",error);
       else if(error==5203) Print("HTTP request failed!");
       else Print("Unknow HTTP request error("+string(error)+")! ");
       
    }
   else if (res==200) // The HTTP 200 status response code indicates that the request has succeeded
    {
       Print("HTTP request successful!");
   
       // Use CharArrayToString to convert HTTP result array to a string
       string HTTP_Result = CharArrayToString(result, 0, 0, CP_UTF8); 
       Print(HTTP_Result);      
   
    }
}



//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("This is the OnStart");
    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
    {
        Alert("MT5 has NO internet connection!");
    }
    Alert("Internet connection verified!");

    // Initialize basic variables
    g_symbol = Symbol();
    g_tf = Period();
    g_isInitialized = false;
    g_lastPredictionTime = 0;
    
    if(g_positionMap != NULL)
    {
        delete g_positionMap;
        g_positionMap = NULL;
    }
    
    if(g_stringComparer != NULL)
    {
        delete g_stringComparer;
        g_stringComparer = NULL;
    }
    
    // Initialize position map
    if(g_stringComparer == NULL)
        g_stringComparer = new CStringEqualityComparer();
        
    if(g_positionMap == NULL)
        g_positionMap = new CHashMap<string, ulong>(g_stringComparer);
    
    Print("Position map initialized with size: ", g_positionMap.Count());
    
    
    // Configure trade object
    trade.SetExpertMagicNumber(MAGIC_NUMBER);
    
    // Initialize successful
    g_isInitialized = true;
    //Debug
    EventSetTimer(1);
    Print("EventSetTimer started with 1 second!");
    
    return(INIT_SUCCEEDED);
}
void OnTimer()
{
  // MarketData currentMarket = GetCurrentMarketData();
  // Print("Current market price is: ", currentMarket.price);
   
}


//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
/*
void OnTick()
{

    if(!g_isInitialized) return;
    
    // Check if it's a new bar
    static datetime lastBar = 0;
    datetime currentBar = iTime(g_symbol, g_tf, 0);
    if(currentBar == lastBar) return;  // Only trade on new bar
    lastBar = currentBar;
    
    UpdateHandlersArray();
    if(g_handlersCount > 0) {
    Print("Handler first data: ID=", g_handlers[0].id, 
          ", Symbol=", g_handlers[0].symbol, 
          ", Status=", g_handlers[0].status,
          ", Profit=", g_handlers[0].profit,
          ", Balance=", g_handlers[0].balance);
   }
    // Get current market data
    MarketData currentMarket = GetCurrentMarketData();
    if(!currentMarket.isValid)
    {
        Print("Error getting market data: ", currentMarket.error);
        return;
    }
    
    // Get prediction
    PredictionData prediction = GetPrediction();
    if(!prediction.isValid)
    {
        Print("Error getting prediction: ", prediction.error);
        return;
    }
    
    // Debug info
    Print("Current Price: ", currentMarket.price);
    Print("Predicted Value: ", prediction.predictedValue);
    Print("Prediction Direction: ", prediction.predictionDirection ? "BUY" : "SELL");
    
    // Check if we have an open position
    bool hasPosition = HasOpenPosition();
    
    if(hasPosition)
    {
        HandleExistingPosition(prediction, currentMarket);
    }
    else
    {
        Print("No existing position, so creating one");
        double SL = 0; 
        double TP = currentMarket.price + .3;
        HandleNewPosition(prediction, currentMarket, SL , TP); // pred, curr_market, SL, TP
    }

}

*/
//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    //Print("In the on tick: ", g_isInitialized);
    if(!g_isInitialized) return;
    
    // Check if it's a new bar
    static datetime lastBar = 0;
    datetime currentBar = iTime(g_symbol, g_tf, 0);
    if(currentBar == lastBar) return;  // Only trade on new bar
    lastBar = currentBar;
    
    // Update handlers array
    UpdateHandlersArray();
    if(g_handlersCount > 0) {
        Print("Handler first data: ID=", g_handlers[0].id, 
              ", User ID=", g_handlers[0].user_id,
              ", Symbol=", g_handlers[0].symbol, 
              ", Status=", g_handlers[0].status,
              ", Balance=", g_handlers[0].balance);
    }
    
    // Get current market data
    MarketData currentMarket = GetCurrentMarketData();
    if(!currentMarket.isValid)
    {
        Print("Error getting market data: ", currentMarket.error);
        return;
    }
    
    // Get prediction
    PredictionData prediction = GetPrediction();
    if(!prediction.isValid)
    {
        Print("Error getting prediction: ", prediction.error);
        return;
    }
    
    
    // Debug info
    Print("Current Price: ", currentMarket.price);
    Print("CURRENT PREDICTION IS: ", prediction.predictedValue);
    
    // Loop through all handlers and manage positions
    for(int i = 0; i < g_handlersCount; i++)
    {
        Print("Processing handler #", i);
        Print("Symbol: ", g_handlers[i].symbol);
        Print("Global symbol: ", g_symbol);
        
        // Only process handlers with matching symbol and active status
        if(g_handlers[i].status == "ACTIVE")
        {
            string user_id = g_handlers[i].user_id;
            Print("Active handler found with user ID: ", user_id);
            Print("g_handlers end time: ", g_handlers[i].end_time);
            bool isValidNow = IsHandlerValid(g_handlers[i].end_time);
            Print("isValidNow ", isValidNow);
            if(!HasOpenPositionForUser(user_id) && !isValidNow){
               RemovePositionByUserId(user_id);
               g_handlers[i].status = "INACTIVE";
               Print("user removed");
               continue;
            }
            
            // Check if user already has an open position
            if(!HasOpenPositionForUser(user_id))
            {
                // No position exists, open a new one
                Print("Opening new position for user ID: ", user_id);
                double SL = 10; 
                double TP = currentMarket.price + 10.1;
                double balance = g_handlers[i].balance;
                if(prediction.predictionDirection){
                
                    // Always buy for now as in your original code
                    OpenPositionForHandler(prediction,true, TRADE_VOLUME, SL, TP, user_id,balance);
                }
                else{
                    Print("Prediction direction false so cannot buy!");
                }
                

            }
            else
            {
                // Position exists, could handle it here if needed
                Print("Position already exists for user ID: ", user_id);
                HandleExistingPositionForUser(user_id, prediction, currentMarket);
            }
        }
    }
}