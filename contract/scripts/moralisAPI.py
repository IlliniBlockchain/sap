import requests

url = "https://deep-index.moralis.io/api/v2/nft/0xa2107fa5b38d9bbd2c461d6edf11b11a50f6b974/lowestprice?chain=eth&days=7&marketplace=opensea"

headers = {
    "accept": "application/json",
    "X-API-Key": "tC5RP6zeHwQJMBu4ZN4UrxM4L88H6N0fSanuaNvD2kZpFnH1OeDDEH3TTLtHwuUe"
}

response = requests.get(url, headers=headers)

print(response.text)