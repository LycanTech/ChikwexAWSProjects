"""
Flask Backend API
- Connects to PostgreSQL database
- Uses Redis for caching
- Provides REST API endpoints
"""
from flask import Flask, jsonify, request
from flask_cors import CORS
import psycopg2
import redis
import os
import json
from datetime import datetime

app = Flask(__name__)
CORS(app)

# Configuration from environment variables
DB_HOST = os.getenv('DB_HOST', 'db')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME', 'appdb')
DB_USER = os.getenv('DB_USER', 'appuser')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'apppassword')

REDIS_HOST = os.getenv('REDIS_HOST', 'redis')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))

# Redis connection
def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

# Database connection
def get_db():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.utcnow().isoformat()})

@app.route('/api/status')
def status():
    """Check all service connections"""
    status = {'api': 'ok', 'database': 'unknown', 'cache': 'unknown'}
    
    # Check Redis
    try:
        r = get_redis()
        r.ping()
        status['cache'] = 'ok'
    except Exception as e:
        status['cache'] = f'error: {str(e)}'
    
    # Check Database
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('SELECT 1')
        conn.close()
        status['database'] = 'ok'
    except Exception as e:
        status['database'] = f'error: {str(e)}'
    
    return jsonify(status)

@app.route('/api/items', methods=['GET'])
def get_items():
    """Get all items (with Redis caching)"""
    r = get_redis()
    
    # Try cache first
    cached = r.get('items')
    if cached:
        return jsonify({'source': 'cache', 'items': json.loads(cached)})
    
    # Query database
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('SELECT id, name, created_at FROM items ORDER BY id')
        items = [{'id': row[0], 'name': row[1], 'created_at': str(row[2])} for row in cur.fetchall()]
        conn.close()
        
        # Cache for 60 seconds
        r.setex('items', 60, json.dumps(items))
        return jsonify({'source': 'database', 'items': items})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/items', methods=['POST'])
def create_item():
    """Create a new item"""
    data = request.get_json()
    if not data or 'name' not in data:
        return jsonify({'error': 'name is required'}), 400
    
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('INSERT INTO items (name) VALUES (%s) RETURNING id', (data['name'],))
        item_id = cur.fetchone()[0]
        conn.commit()
        conn.close()
        
        # Invalidate cache
        r = get_redis()
        r.delete('items')
        
        return jsonify({'id': item_id, 'name': data['name']}), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=os.getenv('FLASK_DEBUG', 'false').lower() == 'true')
