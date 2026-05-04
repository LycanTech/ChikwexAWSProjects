-- ChikwexDockerApp Database Initialization
-- This script runs when PostgreSQL container starts for the first time

-- Create the items table
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert some sample data
INSERT INTO items (name) VALUES 
    ('Welcome to ChikwexDockerApp'),
    ('This is a multi-tier Docker application'),
    ('Built with Flask, React, PostgreSQL, and Redis');

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_items_created_at ON items(created_at);

-- Grant permissions (if needed)
GRANT ALL PRIVILEGES ON TABLE items TO appuser;
GRANT USAGE, SELECT ON SEQUENCE items_id_seq TO appuser;
