import os
from datetime import datetime, timedelta
from web3 import Web3
from web.auto import w3
from eth_account import Account
from eth_account.signers.local import LocalAccount
from eth_account.messages import encode_defunct
from eth_abi.packed import encode_abi_packed
from eth_utils import keccak


config = {
    PRICE_VALID_DURATION: timedelta(hours=1)
}


def to_32byte_hex(val):
    return Web3.toHex(Web3.toBytes(val).rjust(32, b'\0'))


def sign_price(nft_address: str, median_price: float) -> (str, int):
    private_key = os.environ.get('PRIVATE_KEY')
    assert private_key is not None, "You must set PRIVATE_KEY environment variable"
    assert private_key.startswith("0x"), "Private key must start with 0x hex prefix"

    account: LocalAccount = Account.from_key(private_key)

    price_deadline = datetime.now() + config['PRICE_VALID_DURATION']

    # for signing NFT collection price oracle, we consider four values (in order):
    # - NFT address
    # - Price (multiplied by 10^18)
    # - Deadline
    hash = keccak(encode_abi_packed(
        ['address','uint256','uint256'],
        [nft_address, median_price * 10 ** 18,  deadline],
    ))

    message = encode_defunct(text=hash.hex())

    signed_message =  w3.eth.account.sign_message(message, private_key=private_key)

    signed = str(signed_message.messageHash.hex())

    return signed, deadline


if __name__ == '__main__':
    
