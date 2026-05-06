'use strict';

require('dotenv').config();

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const promClient = require('prom-client');

// ---------------------------------------------------------------------------
// AWS X-Ray tracing (graceful fallback when daemon is unavailable)
// ---------------------------------------------------------------------------
let AWSXRay;
try {
  AWSXRay = require('aws-xray-sdk');
  AWSXRay.captureHTTPsGlobal(require('http'));
  AWSXRay.setContextMissingStrategy('LOG_ERROR');
  console.log(JSON.stringify({ level: 'info', message: 'AWS X-Ray SDK loaded' }));
} catch (err) {
  console.log(JSON.stringify({ level: 'warn', message: 'AWS X-Ray SDK unavailable, tracing disabled', error: err.message }));
}

// ---------------------------------------------------------------------------
// Prometheus metrics
// ---------------------------------------------------------------------------
const register = promClient.register;
promClient.collectDefaultMetrics({ register });

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
});

// ---------------------------------------------------------------------------
// In-memory user store (demo / integration-test purposes)
// ---------------------------------------------------------------------------
const users = [];
let nextId = 1;

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';
const PORT = parseInt(process.env.PORT, 10) || 3001;

// ---------------------------------------------------------------------------
// Express application
// ---------------------------------------------------------------------------
const app = express();

// X-Ray middleware (open segment) -- wrapped so the service works without daemon
if (AWSXRay) {
  try {
    app.use(AWSXRay.express.openSegment('user-service'));
  } catch (err) {
    console.log(JSON.stringify({ level: 'warn', message: 'X-Ray open segment failed', error: err.message }));
  }
}

app.use(helmet());
app.use(cors());
app.use(express.json());

// ---------------------------------------------------------------------------
// Request duration tracking middleware
// ---------------------------------------------------------------------------
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.route.path : req.path;
    end({ method: req.method, route, status_code: res.statusCode });
  });
  next();
});

// ---------------------------------------------------------------------------
// Structured request logging middleware
// ---------------------------------------------------------------------------
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    console.log(JSON.stringify({
      level: 'info',
      timestamp: new Date().toISOString(),
      method: req.method,
      path: req.originalUrl,
      statusCode: res.statusCode,
      durationMs: Date.now() - start,
      service: 'user-service',
    }));
  });
  next();
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'user-service' });
});

// Prometheus metrics endpoint
app.get('/metrics', async (_req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (err) {
    res.status(500).json({ error: 'Failed to collect metrics' });
  }
});

// Register a new user
app.post('/api/users/register', async (req, res, next) => {
  try {
    const { username, email, password } = req.body;

    if (!username || !email || !password) {
      return res.status(400).json({ error: 'username, email, and password are required' });
    }

    const exists = users.find((u) => u.email === email);
    if (exists) {
      return res.status(409).json({ error: 'A user with that email already exists' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const user = {
      id: nextId++,
      username,
      email,
      password: hashedPassword,
      createdAt: new Date().toISOString(),
    };

    users.push(user);

    console.log(JSON.stringify({ level: 'info', message: 'User registered', userId: user.id, email }));

    const { password: _pw, ...safeUser } = user;
    res.status(201).json(safeUser);
  } catch (err) {
    next(err);
  }
});

// Login
app.post('/api/users/login', async (req, res, next) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'email and password are required' });
    }

    const user = users.find((u) => u.email === email);
    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const valid = await bcrypt.compare(password, user.password);
    if (!valid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = jwt.sign({ id: user.id, email: user.email }, JWT_SECRET, { expiresIn: '1h' });

    console.log(JSON.stringify({ level: 'info', message: 'User logged in', userId: user.id }));

    res.json({ token, userId: user.id });
  } catch (err) {
    next(err);
  }
});

// Get user by ID
app.get('/api/users/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  const user = users.find((u) => u.id === id);

  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  const { password, ...safeUser } = user;
  res.json(safeUser);
});

// List all users
app.get('/api/users', (_req, res) => {
  const safeUsers = users.map(({ password, ...rest }) => rest);
  res.json(safeUsers);
});

// ---------------------------------------------------------------------------
// X-Ray close segment
// ---------------------------------------------------------------------------
if (AWSXRay) {
  try {
    app.use(AWSXRay.express.closeSegment());
  } catch (err) {
    console.log(JSON.stringify({ level: 'warn', message: 'X-Ray close segment failed', error: err.message }));
  }
}

// ---------------------------------------------------------------------------
// Global error handling middleware
// ---------------------------------------------------------------------------
app.use((err, _req, res, _next) => {
  console.log(JSON.stringify({
    level: 'error',
    message: err.message,
    stack: err.stack,
    service: 'user-service',
  }));
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------
const server = app.listen(PORT, () => {
  console.log(JSON.stringify({
    level: 'info',
    message: `user-service listening on port ${PORT}`,
    service: 'user-service',
  }));
});

// Graceful shutdown
const shutdown = (signal) => {
  console.log(JSON.stringify({ level: 'info', message: `${signal} received, shutting down gracefully` }));
  server.close(() => {
    console.log(JSON.stringify({ level: 'info', message: 'HTTP server closed' }));
    process.exit(0);
  });
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = app;
