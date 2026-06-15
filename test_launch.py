
import asyncio
from gama_client.sync_client import GamaSyncClient
import os

async def test():
    async def h1(m): pass
    async def h2(m): pass
    client = GamaSyncClient("localhost", 6868, h1, h2)
    await client.connect(False)
    print("Loading test.gaml...")
    res = client.sync_load(os.path.abspath("test.gaml"), "test_exp", parameters=[{"name": "my_param", "type": "int", "value": "42"}])
    print("Response:", res)
    if "content" in res and isinstance(res["content"], str):
        exp_id = res["content"]
        print("Success! Exp ID:", exp_id)
        client.sync_play(exp_id)
        print("Played.")
    await client.close_connection()

if __name__ == "__main__":
    asyncio.run(test())
