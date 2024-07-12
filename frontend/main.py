from flask import Flask, jsonify
import requests
import os

# API の URL を環境変数から取得
API_URL = os.environ["API_URL"]

app = Flask(__name__)

@app.route('/', methods=['GET'])
def get_external_data():
    try:
        response = requests.get(API_URL)
        response.raise_for_status()
        data = response.json()
        return jsonify(data)
    except requests.exceptions.RequestException as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, host="0.0.0.0", port=os.environ["PORT"])