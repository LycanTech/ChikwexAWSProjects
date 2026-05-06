'use client';

import { useState, useEffect } from 'react';
import { getOrders, Order } from '@/lib/api';
import { Package, Clock, CheckCircle, Truck } from 'lucide-react';

export default function OrdersPage() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getOrders()
      .then(setOrders)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'pending':
        return <Clock className="w-5 h-5 text-yellow-500" />;
      case 'processing':
        return <Package className="w-5 h-5 text-blue-500" />;
      case 'shipped':
        return <Truck className="w-5 h-5 text-purple-500" />;
      case 'delivered':
        return <CheckCircle className="w-5 h-5 text-green-500" />;
      default:
        return <Clock className="w-5 h-5 text-gray-500" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'pending':
        return 'bg-yellow-100 text-yellow-800';
      case 'processing':
        return 'bg-blue-100 text-blue-800';
      case 'shipped':
        return 'bg-purple-100 text-purple-800';
      case 'delivered':
        return 'bg-green-100 text-green-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  // Demo orders for display
  const demoOrders: Order[] = [
    {
      id: 1001,
      userId: 1,
      items: [
        { productId: 1, name: 'Laptop', price: 999.99, quantity: 1 },
        { productId: 3, name: 'Headphones', price: 199.99, quantity: 1 },
      ],
      total: 1199.98,
      status: 'delivered',
      createdAt: '2024-01-15T10:30:00Z',
    },
    {
      id: 1002,
      userId: 1,
      items: [
        { productId: 2, name: 'Phone', price: 699.99, quantity: 1 },
      ],
      total: 699.99,
      status: 'shipped',
      createdAt: '2024-01-20T14:45:00Z',
    },
    {
      id: 1003,
      userId: 1,
      items: [
        { productId: 4, name: 'Keyboard', price: 149.99, quantity: 2 },
      ],
      total: 299.98,
      status: 'processing',
      createdAt: '2024-01-25T09:15:00Z',
    },
  ];

  const displayOrders = orders.length > 0 ? orders : demoOrders;

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-800 mb-8">My Orders</h1>

      {loading ? (
        <div className="space-y-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className="bg-white rounded-xl shadow-sm p-6 animate-pulse">
              <div className="h-4 bg-gray-200 rounded w-1/4 mb-4"></div>
              <div className="h-4 bg-gray-200 rounded w-1/2"></div>
            </div>
          ))}
        </div>
      ) : displayOrders.length === 0 ? (
        <div className="text-center py-16">
          <Package className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h2 className="text-2xl font-semibold text-gray-600 mb-2">No orders yet</h2>
          <p className="text-gray-500">Start shopping to see your orders here.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {displayOrders.map((order) => (
            <div key={order.id} className="bg-white rounded-xl shadow-sm overflow-hidden">
              <div className="p-6">
                <div className="flex flex-wrap items-center justify-between gap-4 mb-4">
                  <div>
                    <span className="text-gray-500 text-sm">Order #</span>
                    <span className="font-bold text-lg ml-1">{order.id}</span>
                  </div>
                  <div className="flex items-center space-x-2">
                    {getStatusIcon(order.status)}
                    <span className={`px-3 py-1 rounded-full text-sm font-medium ${getStatusColor(order.status)}`}>
                      {order.status.charAt(0).toUpperCase() + order.status.slice(1)}
                    </span>
                  </div>
                </div>

                <div className="border-t border-b py-4 my-4">
                  {order.items.map((item, index) => (
                    <div key={index} className="flex justify-between items-center py-2">
                      <div className="flex items-center space-x-3">
                        <div className="bg-gray-100 w-12 h-12 rounded-lg flex items-center justify-center">
                          <span className="text-xl">📦</span>
                        </div>
                        <div>
                          <p className="font-medium">{item.name}</p>
                          <p className="text-gray-500 text-sm">Qty: {item.quantity}</p>
                        </div>
                      </div>
                      <span className="font-medium">${(item.price * item.quantity).toFixed(2)}</span>
                    </div>
                  ))}
                </div>

                <div className="flex justify-between items-center">
                  <span className="text-gray-500 text-sm">
                    {new Date(order.createdAt).toLocaleDateString('en-US', {
                      year: 'numeric',
                      month: 'long',
                      day: 'numeric',
                    })}
                  </span>
                  <div className="text-right">
                    <span className="text-gray-500 text-sm">Total</span>
                    <p className="text-xl font-bold text-blue-600">${order.total.toFixed(2)}</p>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
