
import asyncio
import os
import time
from gama_client.sync_client import GamaSyncClient

# --- CONFIGURATION ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "STAR FARM", "models", "Experiments", "Calibration-Paul.gaml")
CSV_PATH = os.path.join(BASE_DIR, "STAR FARM", "models", "Experiments", "Calibration", "calibration_result.csv")
EXPERIMENT_NAME = "single_evaluation"
PORT = 6868

GIVEN_PARAMS = {
    "rue_efficiency_factor": 0.7,
    "pest_infection_prob": 0.6,
    "pest_daily_increment": 0.03,
    "daily_water_loss_mm": 5.0,
    "max_water_capacity": 80.0,
    "lateral_leakage_coefficient": 0.01,
    "water_excess_coefficient": 0.1,
    "daily_n_consumption": 0.8,
    "toxicity_per_straw_unit": 0.01
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

    client = GamaSyncClient("localhost", PORT, async_command_answer_handler, gama_server_message_handler)
    
    try:
        print(f"Connecting to GAMA on port {PORT}...")
        await client.connect(False)
        
        # Load Experiment
        print(f"Loading experiment '{EXPERIMENT_NAME}'...")
        params = format_parameters(GIVEN_PARAMS)
        
        response = client.sync_load(os.path.abspath(MODEL_PATH), EXPERIMENT_NAME, parameters=params)
        
        if "content" in response and isinstance(response["content"], str):
            exp_id = response["content"]
            print(f"Experiment loaded successfully. ID: {exp_id}")
            
            # Delete old CSV file if it exists so we start fresh
            if os.path.exists(CSV_PATH):
                try:
                    os.remove(CSV_PATH)
                except Exception:
                    pass

            # Start Simulation
            print("Launching single evaluation...")
            client.sync_play(exp_id)
            
            print(f"Simulation is running. Waiting for output in {CSV_PATH}...")
            
            # Wait for CSV file to contain more than the header
            timeout = 3600 # 1 hour max
            elapsed = 0
            while elapsed < timeout:
                if os.path.exists(CSV_PATH):
                    with open(CSV_PATH, 'r', encoding='utf-8') as f:
                        lines = f.readlines()
                        if len(lines) > 1:
                            print(f"Success! Evaluation finished. Results written to CSV:")
                            print("--------------------------------------------------")
                            print(lines[-1].strip())
                            print("--------------------------------------------------")
                            break
                await asyncio.sleep(2)
                elapsed += 2
            
            if elapsed >= timeout:
                print("TIMEOUT: Simulation took too long.")
                
        else:
            print("Failed to load experiment. Response:", response)
            
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await client.close_connection()
        print("Disconnected.")

if __name__ == "__main__":
    if not os.path.exists(MODEL_PATH):
        print(f"ERROR: Model file not found at {MODEL_PATH}")
    else:
        asyncio.run(run_calibration())
