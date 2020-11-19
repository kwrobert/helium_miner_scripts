import csv
import pprint
from datetime import datetime

AVG_WINDOW = 5

def main():
    
    data = []
    with open("/home/pi/miner_data/block_times.txt") as f:
        reader = csv.DictReader(f)
        for d in reader:
            d["datetime"] = datetime.strptime(d["#datetime"], "%m/%d/%y_%H:%M:%S")
            del d["#datetime"]
            data.append(d)

    blockchain_rates = []
    miner_rates = []
    for i in range(len(data) - AVG_WINDOW, len(data) - 1):
        d0 = data[i]
        d1 = data[i + 1]
        time_diff = (d1["datetime"] - d0["datetime"]).total_seconds()
        try:
            added_blocks = int(d1["blockchain_height"]) - int(d0["blockchain_height"])
            synced_blocks = int(d1["miner_height"]) - int(d0["miner_height"])
        except:
            continue
        miner_rates.append(synced_blocks/time_diff)
        blockchain_rates.append(added_blocks/time_diff)
        print(time_diff)

#    pprint.pprint(data)
    block_diff = int(data[-1]["blockchain_height"]) - int(data[-1]["miner_height"])
    avg_blockchain = sum(blockchain_rates)/len(blockchain_rates)
    avg_miner = sum(miner_rates)/len(miner_rates)
    eta = block_diff / (avg_miner - avg_blockchain) / 60

    print(f"Average Miner Rate: {avg_miner} blocks/min")
    print(f"Average Blockchain Rate: {avg_blockchain} blocks/min")
    print(f"Sync ETA: {eta} hours")

    

if __name__ == '__main__':
    main()
