from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def hello():
    environment = os.environ.get('ENVIRONMENT', 'unknown')
    return f'Hello from the {environment} environment!'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
