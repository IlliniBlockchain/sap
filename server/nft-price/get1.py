import requests
from typing import Union, List


def get_floor_price_from_module(address: str) -> float:
    url = 'https://api.modulenft.xyz/api/v2/eth/nft/floor?contractAddress={}'.format(address)

    headers = {'accept': 'application/json'}

    response = requests.get(url, headers=headers)

    return float(response.json()['data']['price']) # given in ETH


def get_floor_price_from_reservoir(address: str) -> List[float]:
    url = 'https://api.reservoir.tools/collections/sources/v1?collection={}'.format(address)

    headers = {
        'accept': '*/*',
        'x-api-key': 'demo-api-key'
    }

    response = requests.get(url, headers=headers)

    return [x['floorAskPrice'] for x in response.json()['sources']]


if __name__ == '__main__':
    bayc = '0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D'
    price = get_floor_price_from_reservoir(bayc)

    print(price)
