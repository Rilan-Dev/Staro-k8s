import requests
import os

PROMETHEUS_URL = "http://kube-prometheus-stack-prometheus.observability:9090"

def dump_labels():
    try:
        # Query 'up' to see all targets and their labels
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={"query": "up"})
        data = response.json()
        if data["status"] == "success":
            print(f"Found {len(data['data']['result'])} targets in 'up' metric:")
            for result in data["data"]["result"]:
                print(f"Metric: {result['metric']}")
        else:
            print(f"Query failed: {data}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    dump_labels()
