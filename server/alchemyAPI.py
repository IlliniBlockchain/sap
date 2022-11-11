import requests

apikey = "i7qPW8op39rT1rNtrnv2koW1g_NCDWhS"



# Alchemy queries openSea and LooksRare


def get_nft_floor_price_alchemy(address: str):
    url = "https://eth-mainnet.g.alchemy.com/nft/v2/" + apikey + "/getFloorPrice?contractAddress=" + address
    headers = {"accept": "application/json"}

    response = requests.get(url, headers=headers)
    data = response.json()

    if "openSea" in data:
        return(float(data['openSea']['floorPrice']))
    else:
        return(float(data['looksRare']['floorPrice']))

print (get_nft_floor_price_alchemy("0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D"))