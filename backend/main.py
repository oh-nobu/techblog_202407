from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/', methods=['GET'])
def get_dummy_data():
    dummy_data = {
        "id": 1,
        "name": "John Doe",
        "email": "john.doe@example.com",
        "age": 30,
        "address": {
            "street": "123 Main St",
            "city": "Anytown",
            "state": "CA",
            "zip": "12345"
        }
    }
    return jsonify(dummy_data)

if __name__ == '__main__':
    app.run(debug=True, host="0.0.0.0", port=os.environ["PORT"])
