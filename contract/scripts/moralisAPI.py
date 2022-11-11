import requests

apikey = "tC5RP6zeHwQJMBu4ZN4UrxM4L88H6N0fSanuaNvD2kZpFnH1OeDDEH3TTLtHwuUe"

# Queries OpenSea . . . also takes days as a parameter and returns the lowest price sold in the 7 days . . . 
# Useful b/c we can make it to fit whatever functionality we want  . . .

def get_nft_floor_price_moralis(address: str):
    url = "https://deep-index.moralis.io/api/v2/nft/" + address+ "/lowestprice?chain=eth&days=7&marketplace=opensea"

    headers = {
    "accept": "application/json",
    "X-API-Key": "tC5RP6zeHwQJMBu4ZN4UrxM4L88H6N0fSanuaNvD2kZpFnH1OeDDEH3TTLtHwuUe"
    }

    response = requests.get(url, headers=headers)
    data = response.json()

    return data['price'] #lots of other data available about the specific transaction

print (get_nft_floor_price_moralis("0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D"))