import asyncio
import os
import time
from gama_client.sync_client import GamaSyncClient
import random

# --- CONFIGURATION ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "STAR FARM", "models", "Experiments", "Calibration-Paul.gaml")
CSV_PATH = os.path.join(BASE_DIR, "STAR FARM", "models", "Experiments", "Calibration", "calibration_result.csv")
EXPERIMENT_NAME = "single_evaluation"
PORT = 6868


x = [0.57,0.6,0.08,11.0,101.0,0.1,0.011215817939350649,0.2075636039539783,0.08279824749708323]


GIVEN_PARAMS = {
    "rue_efficiency_factor": x[0],
    "pest_infection_prob": x[1],
    "pest_daily_increment": x[2],
    "daily_water_loss_mm": x[3],
    "max_water_capacity": x[4],
    "lateral_leakage_coefficient": x[5],
    "water_excess_coefficient": x[6],
    "daily_n_consumption": x[7],
    "toxicity_per_straw_unit": x[8]
}

def format_parameters(params_dict):
    return [
        {"name": name, "type": "float" if isinstance(val, float) else "int", "value": str(val)}
        for name, val in params_dict.items()
    ]

async def run_calibration():
    print("Starting GAMA Headless Server connection...")
    
    async def async_command_answer_handler(message): pass
    async def gama_server_message_handler(message): pass

    num_clients = 4
    clients = [GamaSyncClient("localhost", PORT, async_command_answer_handler, gama_server_message_handler) for _ in range(num_clients)]
    
    try:
        # Delete old CSV file if it exists so we start fresh
        if os.path.exists(CSV_PATH):
            try:
                os.remove(CSV_PATH)
            except Exception:
                pass

        for i, client in enumerate(clients):
            print(f"Connecting to GAMA for Client {i+1} on port {PORT}...")
            await client.connect(False)
            
            # Load Experiment
            print(f"Loading experiment '{EXPERIMENT_NAME}' for Client {i+1}...")
            params = format_parameters(GIVEN_PARAMS)
            # Add a random seed to the parameters
            params.append({"name": "seed", "type": "int", "value": str(random.randint(1, 1000000000))})
            
            response = client.sync_load(os.path.abspath(MODEL_PATH), EXPERIMENT_NAME, parameters=params)
            
            if "content" in response and isinstance(response["content"], str):
                exp_id = response["content"]
                print(f"Experiment loaded successfully for Client {i+1}. ID: {exp_id}")
                
                # Start Simulation
                print(f"Launching evaluation for Client {i+1}...")
                client.sync_play(exp_id)
            else:
                print(f"Failed to load experiment for Client {i+1}. Response:", response)
                
        print(f"All {num_clients} simulations are running. Waiting for output in {CSV_PATH}...")
        
        # Wait for CSV file to contain more than the header
        timeout = 3600 # 1 hour max
        elapsed = 0
        while elapsed < timeout:
            if os.path.exists(CSV_PATH):
                with open(CSV_PATH, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
                    if len(lines) > 4:
                        print(f"Success! {num_clients} evaluations finished. Results written to CSV:")
                        print("--------------------------------------------------")
                        for line in lines[1:]:
                            print(line.strip())
                        print("--------------------------------------------------")
                        break
            await asyncio.sleep(2)
            elapsed += 2
        
        if elapsed >= timeout:
            print("TIMEOUT: Simulation took too long.")
            
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        for client in clients:
            try:
                await client.close_connection()
            except AttributeError:
                pass
        print("Disconnected all clients.")

if __name__ == "__main__":
    if not os.path.exists(MODEL_PATH):
        print(f"ERROR: Model file not found at {MODEL_PATH}")
    else:
        asyncio.run(run_calibration())
