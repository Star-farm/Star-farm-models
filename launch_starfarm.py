
import asyncio
import os
import time
import subprocess
from gama_client.sync_client import GamaSyncClient

# --- CONFIGURATION ---
GAMA_PATH = r"C:\Program Files\Gama\headless\gama-headless.bat"
# Resolving model path relative to this script's location
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "STAR FARM", "models", "Experiments", "Calibration_and_Validation.gaml")
EXPERIMENT_NAME = "calibration_"
PORT = 6868

# Given values for calibration parameters
# These will be passed to the GAMA experiment
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
    """Converts a dictionary to GAMA parameters format."""
    return [
        {"name": name, "type": "float" if isinstance(val, float) else "int", "value": str(val)}
        for name, val in params_dict.items()
    ]

async def run_calibration():
    # 1. Start GAMA Server (if not already running)
    print("Starting GAMA Headless Server...")
    # Using a simple check to see if we should start it
    # For now, we assume we need to start it or it's already running.
    # We won't block here but you might need to run: 
    # gama-headless.bat -socket 6868
    
    # 2. Connect Client
    async def async_command_answer_handler(message): pass
    async def gama_server_message_handler(message): pass

    client = GamaSyncClient("localhost", PORT, async_command_answer_handler, gama_server_message_handler)
    
    try:
        print(f"Connecting to GAMA on port {PORT}...")
        await client.connect(False)
        
        # 3. Load Experiment
        print(f"Loading experiment '{EXPERIMENT_NAME}'...")
        params = format_parameters(GIVEN_PARAMS)
        
        # We use the absolute path for the model
        response = client.sync_load(os.path.abspath(MODEL_PATH), EXPERIMENT_NAME, parameters=params)
        
        if "content" in response:
            exp_id = response["content"]
            print(f"Experiment loaded successfully. ID: {exp_id}")
            
            # 4. Start Simulation
            print("Launching PSO Calibration...")
            client.sync_play(exp_id)
            
            print("Simulation is running. Batch experiments run until they finish their optimization.")
            print("You can check the output file at: " + os.path.dirname(MODEL_PATH) + "/Calibration/calibration_result.csv")
            
            # Optional: Wait or monitor progress
            # For this example, we'll just exit after launching
            
        else:
            print("Failed to load experiment. Response:", response)
            
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await client.close_connection()
        print("Disconnected.")

if __name__ == "__main__":
    # Ensure the model path is absolute and exists
    if not os.path.exists(MODEL_PATH):
        print(f"ERROR: Model file not found at {MODEL_PATH}")
    else:
        asyncio.run(run_calibration())
