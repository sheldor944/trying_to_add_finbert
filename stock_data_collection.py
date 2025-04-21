import pandas as pd

def download_stock_data(ticker, start, end, interval='1d'):
    """
    download stock price data from Yahoo Finance
    """
    import yfinance as yf
    # stock_data = yf.download(ticker, start, end)
        # Download the stock data
    stock_data = yf.download(ticker, start=start, end=end, interval=interval)
    

    df = pd.DataFrame(stock_data)
    df.to_csv("gold_price.csv")


download_stock_data("GC=F", "2021-01-01", "2023-12-30", "1d")

# import requests

# api_key = '0SUEVQYBZKBM976U'
# url = f'https://www.alphavantage.co/query?function=TIME_SERIES_INTRADAY&symbol=XAUUSD&interval=15min&apikey={api_key}'

# r = requests.get(url)

# if r.status_code == 200:
#     data = r.json()
#     print(data)
# else:
#     print(f"Failed to retrieve data: {r.status_code}")