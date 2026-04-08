import time
import random
import requests

BACKEND_URL = "https://farmconnect-production-500d.up.railway.app/v1/sensors/ingest"
INGEST_KEY = "<SENSOR_INGEST_API_KEY>"

def read_sensors():
    # Replace this block with real sensor reads
    return {
        "soil_moisture": round(random.uniform(20, 60), 1),
        "temperature": round(random.uniform(18, 32), 1),
        "humidity": round(random.uniform(35, 80), 1),
    }

while True:
    values = read_sensors()
    payload = {
        "deviceId": "pi-node-1",
        "deviceName": "Raspberry Pi Node 1",
        "farmName": "Persephone Farm",
        "locationLabel": "North Plot",
        "status": "online",
        "readings": [
            {"sensorType": "soil_moisture", "value": values["soil_moisture"], "unit": "%"},
            {"sensorType": "temperature", "value": values["temperature"], "unit": "C"},
            {"sensorType": "humidity", "value": values["humidity"], "unit": "%"},
        ],
    }

    try:
        r = requests.post(
            BACKEND_URL,
            json=payload,
            headers={"x-sensor-key": INGEST_KEY},
            timeout=10,
        )
        print(r.status_code, r.text)
    except Exception as e:
        print("send failed:", e)

    time.sleep(60)  # send every 60 seconds
