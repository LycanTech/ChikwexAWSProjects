const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const promClient = require('prom-client');
require('dotenv').config();

// ──────────────────────────────────────────────
// Prometheus Metrics
// ──────────────────────────────────────────────
const collectDefaultMetrics = promClient.collectDefaultMetrics;
collectDefaultMetrics({ prefix: 'payment_service_' });

const httpRequestDurationHistogram = new promClient.Histogram({
  name: 'payment_service_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
});

const paymentCounter = new promClient.Counter({
  name: 'payment_service_payments_total',
  help: 'Total number of payments processed',
  labelNames: ['status'],
});

// ──────────────────────────────────────────────
// In-Memory Store
// ──────────────────────────────────────────────
const payments = [];

// ──────────────────────────────────────────────
// Structured Logger
// ──────────────────────────────────────────────
function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'payment-service',
    message,
    ...meta,
  };
  console.log(JSON.stringify(entry));
}

// ──────────────────────────────────────────────
// Express App
// ──────────────────────────────────────────────
const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());

// Request duration tracking middleware
app.use((req, res, next) => {
  const end = httpRequestDurationHistogram.startTimer();
  res.on('finish', () => {
    end({
      method: req.method,
      route: req.route ? req.route.path : req.path,
      status_code: res.statusCode,
    });
  });
  next();
});

// Request logging middleware
app.use((req, res, next) => {
  log('info', 'Incoming request', {
    method: req.method,
    path: req.path,
    ip: req.ip,
  });
  next();
});

// ──────────────────────────────────────────────
// Routes
// ──────────────────────────────────────────────

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'payment-service' });
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', promClient.register.contentType);
    const metrics = await promClient.register.metrics();
    res.end(metrics);
  } catch (err) {
    log('error', 'Failed to collect metrics', { error: err.message });
    res.status(500).end();
  }
});

// Process a payment
app.post('/api/payments/process', (req, res) => {
  const { orderId, userId, amount, currency, paymentMethod } = req.body;

  // Validate required fields
  if (!orderId || !userId || !amount || !currency || !paymentMethod) {
    log('warn', 'Payment request missing required fields', { body: req.body });
    return res.status(400).json({
      error: 'Missing required fields: orderId, userId, amount, currency, paymentMethod',
    });
  }

  // Validate amount
  if (typeof amount !== 'number' || amount <= 0) {
    log('warn', 'Invalid payment amount', { amount });
    return res.status(400).json({ error: 'Amount must be a positive number' });
  }

  // Simulate processing: 90% success rate
  const isSuccess = Math.random() < 0.9;
  const status = isSuccess ? 'completed' : 'failed';

  const payment = {
    paymentId: uuidv4(),
    orderId,
    userId,
    amount,
    currency,
    paymentMethod,
    status,
    transactionId: uuidv4(),
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };

  payments.push(payment);
  paymentCounter.inc({ status });

  log('info', `Payment ${status}`, {
    paymentId: payment.paymentId,
    orderId,
    amount,
    currency,
    status,
  });

  const statusCode = isSuccess ? 201 : 402;
  res.status(statusCode).json({
    paymentId: payment.paymentId,
    status: payment.status,
    transactionId: payment.transactionId,
  });
});

// Get payment by ID
app.get('/api/payments/:paymentId', (req, res) => {
  const { paymentId } = req.params;
  const payment = payments.find((p) => p.paymentId === paymentId);

  if (!payment) {
    log('warn', 'Payment not found', { paymentId });
    return res.status(404).json({ error: 'Payment not found' });
  }

  log('info', 'Payment retrieved', { paymentId });
  res.json(payment);
});

// Get payments for an order
app.get('/api/payments/order/:orderId', (req, res) => {
  const { orderId } = req.params;
  const orderPayments = payments.filter((p) => p.orderId === orderId);

  log('info', 'Payments retrieved for order', {
    orderId,
    count: orderPayments.length,
  });

  res.json(orderPayments);
});

// Refund a payment
app.post('/api/payments/:paymentId/refund', (req, res) => {
  const { paymentId } = req.params;
  const payment = payments.find((p) => p.paymentId === paymentId);

  if (!payment) {
    log('warn', 'Payment not found for refund', { paymentId });
    return res.status(404).json({ error: 'Payment not found' });
  }

  if (payment.status === 'refunded') {
    log('warn', 'Payment already refunded', { paymentId });
    return res.status(400).json({ error: 'Payment has already been refunded' });
  }

  if (payment.status === 'failed') {
    log('warn', 'Cannot refund a failed payment', { paymentId });
    return res.status(400).json({ error: 'Cannot refund a failed payment' });
  }

  payment.status = 'refunded';
  payment.updatedAt = new Date().toISOString();
  payment.refundId = uuidv4();
  paymentCounter.inc({ status: 'refunded' });

  log('info', 'Payment refunded', {
    paymentId,
    refundId: payment.refundId,
  });

  res.json({
    paymentId: payment.paymentId,
    status: payment.status,
    refundId: payment.refundId,
  });
});

// ──────────────────────────────────────────────
// Error handling middleware
// ──────────────────────────────────────────────
app.use((err, req, res, next) => {
  log('error', 'Unhandled error', {
    error: err.message,
    stack: err.stack,
  });
  res.status(500).json({ error: 'Internal server error' });
});

// ──────────────────────────────────────────────
// Start Server
// ──────────────────────────────────────────────
const PORT = process.env.PORT || 3004;

app.listen(PORT, () => {
  log('info', `Payment service started on port ${PORT}`, { port: PORT });
});

module.exports = app;
