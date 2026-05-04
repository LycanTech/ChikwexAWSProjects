import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [status, setStatus] = useState(null);
  const [items, setItems] = useState([]);
  const [newItem, setNewItem] = useState('');
  const [loading, setLoading] = useState(true);

  // API base URL - uses nginx proxy in production
  const API_URL = '/api';

  // Fetch service status
  useEffect(() => {
    fetch(`${API_URL}/status`)
      .then(res => res.json())
      .then(data => setStatus(data))
      .catch(err => setStatus({ error: err.message }));
  }, []);

  // Fetch items
  useEffect(() => {
    fetchItems();
  }, []);

  const fetchItems = () => {
    setLoading(true);
    fetch(`${API_URL}/items`)
      .then(res => res.json())
      .then(data => {
        setItems(data.items || []);
        setLoading(false);
      })
      .catch(err => {
        console.error('Error fetching items:', err);
        setLoading(false);
      });
  };

  const addItem = (e) => {
    e.preventDefault();
    if (!newItem.trim()) return;

    fetch(`${API_URL}/items`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: newItem })
    })
      .then(res => res.json())
      .then(() => {
        setNewItem('');
        fetchItems();
      })
      .catch(err => console.error('Error adding item:', err));
  };

  return (
    <div className="app">
      <header className="header">
        <h1>ChikwexDockerApp</h1>
        <p>Multi-tier Docker Compose Application</p>
      </header>

      <section className="status-section">
        <h2>Service Status</h2>
        {status ? (
          <div className="status-grid">
            <div className={`status-item ${status.api === 'ok' ? 'ok' : 'error'}`}>
              <span>API</span>
              <span>{status.api || 'unknown'}</span>
            </div>
            <div className={`status-item ${status.database === 'ok' ? 'ok' : 'error'}`}>
              <span>Database</span>
              <span>{status.database || 'unknown'}</span>
            </div>
            <div className={`status-item ${status.cache === 'ok' ? 'ok' : 'error'}`}>
              <span>Cache</span>
              <span>{status.cache || 'unknown'}</span>
            </div>
          </div>
        ) : (
          <p>Loading status...</p>
        )}
      </section>

      <section className="items-section">
        <h2>Items</h2>
        <form onSubmit={addItem} className="add-form">
          <input
            type="text"
            value={newItem}
            onChange={(e) => setNewItem(e.target.value)}
            placeholder="Enter new item..."
          />
          <button type="submit">Add Item</button>
        </form>

        {loading ? (
          <p>Loading items...</p>
        ) : items.length > 0 ? (
          <ul className="items-list">
            {items.map(item => (
              <li key={item.id}>{item.name}</li>
            ))}
          </ul>
        ) : (
          <p>No items yet. Add one above!</p>
        )}
      </section>
    </div>
  );
}

export default App;
